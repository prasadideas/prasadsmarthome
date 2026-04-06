import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../models/user_model.dart';
import '../models/device_template.dart';
import '../models/scene_model.dart';
import 'firestore_metrics.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreMetrics _metrics = FirestoreMetrics.instance;

  void _recordOneTimeRead(String source, int count) {
    _metrics.recordOneTimeRead(source, count: count);
  }

  void _recordListenerRead(String source, int count) {
    _metrics.recordListenerRead(source, count: count);
  }

  void _recordWrite(String source, [int count = 1]) {
    _metrics.recordWrite(source, count: count);
  }

  Future<DocumentSnapshot> _trackedDocGet(
    DocumentReference ref,
    String source,
  ) async {
    final doc = await ref.get();
    _recordOneTimeRead(source, 1);
    return doc;
  }

  Future<QuerySnapshot> _trackedQueryGet(Query query, String source) async {
    final snapshot = await query.get();
    _recordOneTimeRead(source, snapshot.docs.length);
    return snapshot;
  }

  Future<DocumentReference> _trackedAdd(
    CollectionReference collection,
    Map<String, dynamic> data,
    String source,
  ) async {
    final ref = await collection.add(data);
    _recordWrite(source);
    return ref;
  }

  Future<void> _trackedSet(
    DocumentReference ref,
    Map<String, dynamic> data,
    String source, {
    SetOptions? options,
  }) async {
    if (options != null) {
      await ref.set(data, options);
    } else {
      await ref.set(data);
    }
    _recordWrite(source);
  }

  Future<void> _trackedUpdate(
    DocumentReference ref,
    Map<String, dynamic> data,
    String source,
  ) async {
    await ref.update(data);
    _recordWrite(source);
  }

  Future<void> _trackedDelete(DocumentReference ref, String source) async {
    await ref.delete();
    _recordWrite(source);
  }

  Future<void> _trackedBatchCommit(
    WriteBatch batch,
    String source,
    int operations,
  ) async {
    await batch.commit();
    _recordWrite(source, operations);
  }

  // ── Shortcuts to collection paths ──────────────────────────

  CollectionReference _homes(String uid) =>
      _db.collection('users').doc(uid).collection('homes');

  CollectionReference _rooms(String uid, String homeId) =>
      _homes(uid).doc(homeId).collection('rooms');

  CollectionReference _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');

  // ── User ───────────────────────────────────────────────────

  // Call this right after signup to create the user document
  Future<void> createUser(UserModel user) async {
    await _trackedSet(
      _db.collection('users').doc(user.uid),
      user.toMap(),
      'createUser',
    );
  }

  // Get user document once (to read favouriteHomeId)
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _trackedDocGet(
      _db.collection('users').doc(uid),
      'getUser',
    );
    return doc.data() as Map<String, dynamic>?;
  }

  Future<void> setUserThemeMode(String uid, String themeMode) async {
    await _trackedUpdate(_db.collection('users').doc(uid), {
      'themeMode': themeMode,
    }, 'setUserThemeMode');
  }

  // ── Homes ──────────────────────────────────────────────────

  Future<void> addHome(String uid, HomeModel home) async {
    await _trackedAdd(_homes(uid), home.toMap(), 'addHome');
  }

  // Stream — UI auto-updates when homes change
  Stream<List<HomeModel>> streamHomes(String uid) {
    return _homes(uid).snapshots().map((snap) {
      _recordListenerRead('streamHomes', snap.docs.length);
      return snap.docs
          .map(
            (doc) =>
                HomeModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<void> deleteHome(String uid, String homeId) async {
    await _trackedDelete(_homes(uid).doc(homeId), 'deleteHome');
  }

  // Update home name
  Future<void> updateHome(
    String uid,
    String homeId,
    String newName,
    String newAddress,
  ) async {
    await _trackedUpdate(_homes(uid).doc(homeId), {
      'homeName': newName,
      'address': newAddress,
    }, 'updateHome');
  }

  // Save favourite homeId into the user document
  Future<void> setFavouriteHome(String uid, String homeId) async {
    await _trackedUpdate(_db.collection('users').doc(uid), {
      'favouriteHomeId': homeId,
    }, 'setFavouriteHome');
  }

  // ── Rooms ──────────────────────────────────────────────────

  Future<void> addRoom(String uid, String homeId, RoomModel room) async {
    await _trackedAdd(_rooms(uid, homeId), room.toMap(), 'addRoom');
  }

  Stream<List<RoomModel>> streamRooms(String uid, String homeId) {
    return _rooms(uid, homeId).snapshots().map((snap) {
      _recordListenerRead('streamRooms', snap.docs.length);
      return snap.docs
          .map(
            (doc) =>
                RoomModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<void> deleteRoom(String uid, String homeId, String roomId) async {
    await _trackedDelete(_rooms(uid, homeId).doc(roomId), 'deleteRoom');
  }

  Future<void> updateRoom(
    String uid,
    String homeId,
    String roomId,
    String newName,
    String newIcon,
  ) async {
    await _trackedUpdate(_rooms(uid, homeId).doc(roomId), {
      'roomName': newName,
      'icon': newIcon,
    }, 'updateRoom');
  }

  // ── Devices ────────────────────────────────────────────────

  Future<String> addDevice(String uid, DeviceModel device) async {
    final ref = await _trackedAdd(
      _devices(uid),
      device.toMap(uid),
      'addDevice',
    );
    return ref.id;
  }

  // Find device by MAC address in BOTH locations, returns (documentId, data) or (null, null)
  Future<({String? docId, Map<String, dynamic>? data, bool isNewLocation})?>
  _findDeviceByMac(String uid, String macAddress) async {
    // First, try new location
    final newSnapshot = await _trackedQueryGet(
      _devices(uid).where('macId', isEqualTo: macAddress).limit(1),
      '_findDeviceByMac.userDevices',
    );

    if (newSnapshot.docs.isNotEmpty) {
      final doc = newSnapshot.docs.first;
      return (
        docId: doc.id,
        data: doc.data() as Map<String, dynamic>,
        isNewLocation: true,
      );
    }

    // Try old location
    final oldSnapshot = await _trackedQueryGet(
      _db
          .collection('devices')
          .where('macId', isEqualTo: macAddress)
          .where('ownedBy', isEqualTo: uid)
          .limit(1),
      '_findDeviceByMac.legacyDevices',
    );

    if (oldSnapshot.docs.isNotEmpty) {
      final doc = oldSnapshot.docs.first;
      return (
        docId: doc.id,
        data: doc.data() as Map<String, dynamic>?,
        isNewLocation: false,
      );
    }

    return null;
  }

  // Update device heartbeat using MAC address
  Future<void> updateDeviceHeartbeatByMac(String uid, String macAddress) async {
    try {
      final result = await _findDeviceByMac(uid, macAddress);
      if (result == null) {
        // Device not found - might be newly added and not yet synced
        return;
      }

      final (docId: docId, data: _, isNewLocation: isNewLocation) = result;

      if (isNewLocation) {
        await _trackedUpdate(_devices(uid).doc(docId), {
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'isOnline': true,
        }, 'updateDeviceHeartbeatByMac');
      } else {
        await _trackedUpdate(
          _db.collection('devices').doc(docId),
          {'lastHeartbeat': FieldValue.serverTimestamp(), 'isOnline': true},
          'updateDeviceHeartbeatByMac.legacy',
        );
      }
    } catch (e) {
      // Silently handle errors - device might be deleted
      debugPrint(
        '[FirestoreService] Error updating heartbeat for $macAddress: $e',
      );
    }
  }

  // Mark device offline using MAC address
  Future<void> markDeviceOfflineByMac(String uid, String macAddress) async {
    try {
      final result = await _findDeviceByMac(uid, macAddress);
      if (result == null) {
        return;
      }

      final (docId: docId, data: _, isNewLocation: isNewLocation) = result;

      if (isNewLocation) {
        await _trackedUpdate(_devices(uid).doc(docId), {
          'isOnline': false,
        }, 'markDeviceOfflineByMac');
      } else {
        await _trackedUpdate(_db.collection('devices').doc(docId), {
          'isOnline': false,
        }, 'markDeviceOfflineByMac.legacy');
      }
    } catch (e) {
      debugPrint(
        '[FirestoreService] Error marking offline for $macAddress: $e',
      );
    }
  }

  // Update device heartbeat (try new location first, fallback to old)
  Future<void> updateDeviceHeartbeat(String uid, String deviceId) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'updateDeviceHeartbeat.userDoc',
    );

    if (doc.exists) {
      await _trackedUpdate(_devices(uid).doc(deviceId), {
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'isOnline': true,
      }, 'updateDeviceHeartbeat');
    } else {
      // Try old location
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'updateDeviceHeartbeat.legacyDoc',
      );
      if (doc.exists) {
        await _trackedUpdate(_db.collection('devices').doc(deviceId), {
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'isOnline': true,
        }, 'updateDeviceHeartbeat.legacy');
      }
    }
  }

  // Mark device as offline (try new location first, fallback to old)
  Future<void> markDeviceOffline(String uid, String deviceId) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'markDeviceOffline.userDoc',
    );

    if (doc.exists) {
      await _trackedUpdate(_devices(uid).doc(deviceId), {
        'isOnline': false,
      }, 'markDeviceOffline');
    } else {
      // Try old location
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'markDeviceOffline.legacyDoc',
      );
      if (doc.exists) {
        await _trackedUpdate(_db.collection('devices').doc(deviceId), {
          'isOnline': false,
        }, 'markDeviceOffline.legacy');
      }
    }
  }

  // Stream all devices owned by this user (from new location + legacy location)
  Stream<List<DeviceModel>> streamDevices(String uid) {
    return _devices(uid).snapshots().asyncMap((newSnapshot) async {
      _recordListenerRead('streamDevices.live', newSnapshot.docs.length);

      // Get devices from new location
      List<DeviceModel> newDevices = newSnapshot.docs
          .map(
            (doc) =>
                DeviceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();

      // Also get devices from old global location that belong to this user
      final oldSnapshot = await _trackedQueryGet(
        _db.collection('devices').where('ownedBy', isEqualTo: uid),
        'streamDevices.legacy',
      );

      List<DeviceModel> oldDevices = oldSnapshot.docs
          .map(
            (doc) =>
                DeviceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();

      // Combine and deduplicate
      final Map<String, DeviceModel> combined = {};
      for (var d in newDevices) {
        combined[d.deviceId] = d;
      }
      for (var d in oldDevices) {
        combined[d.deviceId] = d; // Override if deviceId already exists
      }
      return combined.values.toList();
    });
  }

  // Stream only devices assigned to a specific room (from both old and new locations)
  Stream<List<DeviceModel>> streamDevicesInRoom(String uid, String roomId) {
    return _devices(
      uid,
    ).where('linkedRoom', isEqualTo: roomId).snapshots().asyncMap((
      newSnapshot,
    ) async {
      _recordListenerRead('streamDevicesInRoom.live', newSnapshot.docs.length);

      // Get devices from new location
      List<DeviceModel> newDevices = newSnapshot.docs
          .map(
            (doc) =>
                DeviceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();

      // Also get devices from old global location with roomRef matching
      final oldSnapshot = await _trackedQueryGet(
        _db
            .collection('devices')
            .where('ownedBy', isEqualTo: uid)
            .where('linkedRoom', isEqualTo: roomId),
        'streamDevicesInRoom.legacy',
      );

      List<DeviceModel> oldDevices = oldSnapshot.docs
          .map(
            (doc) =>
                DeviceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();

      // Combine and deduplicate
      final Map<String, DeviceModel> combined = {};
      for (var d in newDevices) {
        combined[d.deviceId] = d;
      }
      for (var d in oldDevices) {
        combined[d.deviceId] = d; // Override if deviceId already exists
      }
      return combined.values.toList();
    });
  }

  // Toggle switch (try new location first, fallback to old)
  Future<void> toggleSwitch(
    String uid,
    String deviceId,
    int switchIndex,
    bool newValue,
  ) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'toggleSwitch.userDoc',
    );

    // If not found in new location, try old location
    if (!doc.exists) {
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'toggleSwitch.legacyDoc',
      );
      if (!doc.exists) return;
    }

    final data = doc.data() as Map<String, dynamic>;

    final rawSwitches = data['switches'];
    List<Map<String, dynamic>> switches = [];

    if (rawSwitches is List) {
      switches = rawSwitches.map((s) => Map<String, dynamic>.from(s)).toList();
    } else if (rawSwitches is Map) {
      switches = rawSwitches.values
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
    }

    if (switchIndex < switches.length) {
      switches[switchIndex]['isOn'] = newValue;
    }

    // Update in the location where it was found
    if (doc.reference.path.startsWith('users/$uid')) {
      await _trackedUpdate(_devices(uid).doc(deviceId), {
        'switches': switches,
      }, 'toggleSwitch');
    } else {
      await _trackedUpdate(_db.collection('devices').doc(deviceId), {
        'switches': switches,
      }, 'toggleSwitch.legacy');
    }
  }

  // Set all switches in a room to off (or given value)
  Future<void> setRoomAllSwitchesOff(
    String uid,
    String roomId, {
    bool isOn = false,
  }) async {
    final querySnap = await _trackedQueryGet(
      _devices(uid).where('linkedRoom', isEqualTo: roomId),
      'setRoomAllSwitchesOff.query',
    );

    final batch = FirebaseFirestore.instance.batch();

    for (final doc in querySnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final rawSwitches = data['switches'];
      List<Map<String, dynamic>> switches = [];

      if (rawSwitches is List) {
        switches = rawSwitches
            .map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>))
            .toList();
      } else if (rawSwitches is Map) {
        switches = rawSwitches.values
            .map((s) => Map<String, dynamic>.from(s as Map<String, dynamic>))
            .toList();
      }

      for (var sw in switches) {
        sw['isOn'] = isOn;
      }

      batch.update(doc.reference, {'switches': switches});
    }

    if (querySnap.docs.isNotEmpty) {
      await _trackedBatchCommit(
        batch,
        'setRoomAllSwitchesOff',
        querySnap.docs.length,
      );
    }
  }

  // Assign to room (try new location first, fallback to old)
  Future<void> assignDeviceToRoom(
    String uid,
    String deviceId,
    String? roomId,
    String? homeId,
  ) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'assignDeviceToRoom.userDoc',
    );

    if (doc.exists) {
      // Update in new location
      await _trackedUpdate(_devices(uid).doc(deviceId), {
        'linkedRoom': roomId,
        'linkedHome': homeId,
      }, 'assignDeviceToRoom');
    } else {
      // Try old location
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'assignDeviceToRoom.legacyDoc',
      );
      if (doc.exists) {
        await _trackedUpdate(_db.collection('devices').doc(deviceId), {
          'linkedRoom': roomId,
          'linkedHome': homeId,
        }, 'assignDeviceToRoom.legacy');
      }
    }
  }

  // Rename device (try new location first, fallback to old)
  Future<void> updateDevice(String uid, String deviceId, String newName) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'updateDevice.userDoc',
    );

    if (doc.exists) {
      await _trackedUpdate(_devices(uid).doc(deviceId), {
        'deviceName': newName,
      }, 'updateDevice');
    } else {
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'updateDevice.legacyDoc',
      );
      if (doc.exists) {
        await _trackedUpdate(_db.collection('devices').doc(deviceId), {
          'deviceName': newName,
        }, 'updateDevice.legacy');
      }
    }
  }

  // Delete device (try new location first, fallback to old)
  Future<void> deleteDevice(String uid, String deviceId) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'deleteDevice.userDoc',
    );

    if (doc.exists) {
      await _trackedDelete(_devices(uid).doc(deviceId), 'deleteDevice');
    } else {
      doc = await _trackedDocGet(
        _db.collection('devices').doc(deviceId),
        'deleteDevice.legacyDoc',
      );
      if (doc.exists) {
        await _trackedDelete(
          _db.collection('devices').doc(deviceId),
          'deleteDevice.legacy',
        );
      }
    }
  }

  // Update a switch's label and icon
  Future<void> updateSwitch(
    String uid,
    String deviceId,
    int switchIndex,
    String newLabel,
    String newIcon,
  ) async {
    var doc = await _trackedDocGet(
      _devices(uid).doc(deviceId),
      'updateSwitch.userDoc',
    );

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      final switches = data?['switches'] as List?;

      if (switches != null && switchIndex < switches.length) {
        final switchData = switches[switchIndex] as Map<String, dynamic>;
        switchData['label'] = newLabel;
        switchData['icon'] = newIcon;
        switches[switchIndex] = switchData;

        await _trackedUpdate(_devices(uid).doc(deviceId), {
          'switches': switches,
        }, 'updateSwitch');
      }
    }
  }

  // Add device ref into room
  Future<void> addDeviceRefToRoom(
    String uid,
    String homeId,
    String roomId,
    String deviceId,
  ) async {
    await _trackedUpdate(_rooms(uid, homeId).doc(roomId), {
      'deviceRefs': FieldValue.arrayUnion([deviceId]),
    }, 'addDeviceRefToRoom');
  }

  // Remove device ref from room
  Future<void> removeDeviceRefFromRoom(
    String uid,
    String homeId,
    String roomId,
    String deviceId,
  ) async {
    await _trackedUpdate(_rooms(uid, homeId).doc(roomId), {
      'deviceRefs': FieldValue.arrayRemove([deviceId]),
    }, 'removeDeviceRefFromRoom');
  }

  // Admin only — reassign device to another user
  Future<void> reassignDevice(
    String oldUid,
    String deviceId,
    String newUserId,
  ) async {
    final doc = await _trackedDocGet(
      _devices(oldUid).doc(deviceId),
      'reassignDevice.sourceDoc',
    );
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final oldOwner = data['ownedBy'];

    // Copy device to new user's collection
    await _trackedSet(_devices(newUserId).doc(deviceId), {
      ...data,
      'ownedBy': newUserId,
      'linkedRoom': null,
      'linkedHome': null,
      'lastOwnedBy': oldOwner,
    }, 'reassignDevice.copy');

    // Delete from old user's collection
    await _trackedDelete(
      _devices(oldUid).doc(deviceId),
      'reassignDevice.delete',
    );
  }

  // Stream all active device templates — ordered by display order
  Stream<List<DeviceTemplate>> streamDeviceTemplates() {
    final defaultTemplates = _buildDefaultTemplates();
    final defaultsById = {
      for (final template in defaultTemplates) template.templateId: template,
    };

    return _db
        .collection('deviceTemplates')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map((snap) {
          _recordListenerRead('streamDeviceTemplates', snap.docs.length);

          if (snap.docs.isEmpty) return defaultTemplates;

          final remoteTemplates = snap.docs
              .map((doc) => DeviceTemplate.fromMap(doc.id, doc.data()))
              .toList();

          final seenTemplateIds = <String>{};
          final mergedTemplates = remoteTemplates.map((template) {
            seenTemplateIds.add(template.templateId);
            return _mergeTemplate(template, defaultsById[template.templateId]);
          }).toList();

          mergedTemplates.addAll(
            defaultTemplates.where(
              (template) => !seenTemplateIds.contains(template.templateId),
            ),
          );

          mergedTemplates.sort((a, b) => a.order.compareTo(b.order));
          return mergedTemplates;
        });
  }

  // Admin only — seed initial templates (run once)
  Future<void> seedDeviceTemplates() async {
    await syncDeviceTemplates();
  }

  Future<void> syncDeviceTemplates() async {
    final templates = _buildDefaultTemplates();
    final batch = _db.batch();
    for (final t in templates) {
      final ref = _db.collection('deviceTemplates').doc(t.templateId);
      batch.set(ref, t.toMap(), SetOptions(merge: true));
    }
    await _trackedBatchCommit(batch, 'syncDeviceTemplates', templates.length);
  }

  DeviceTemplate _mergeTemplate(
    DeviceTemplate template,
    DeviceTemplate? fallback,
  ) {
    if (fallback == null) return template;

    return DeviceTemplate(
      templateId: template.templateId,
      name: template.name.isNotEmpty ? template.name : fallback.name,
      description: template.description.isNotEmpty
          ? template.description
          : fallback.description,
      category: template.category.isNotEmpty
          ? template.category
          : fallback.category,
      iconCode: template.iconCode,
      order: template.order,
      isActive: template.isActive,
      switches: template.switches.isNotEmpty
          ? template.switches
          : fallback.switches,
      sensors: template.sensors.isNotEmpty
          ? template.sensors
          : fallback.sensors,
    );
  }

  List<SensorTemplate> _sensorTemplates(List<String> types) {
    return SensorTemplateCatalog.forTypes(types);
  }

  List<DeviceTemplate> _buildDefaultTemplates() {
    return [
      DeviceTemplate(
        templateId: 'sw_1',
        name: '1-switch board',
        description: 'Single appliance control',
        category: 'Basic',
        iconCode: Icons.toggle_on.codePoint,
        order: 1,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ],
      ),
      DeviceTemplate(
        templateId: 'sw_2',
        name: '2-switch board',
        description: 'Two light or appliance control',
        category: 'Basic',
        iconCode: Icons.toggle_on.codePoint,
        order: 2,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Switch 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ],
      ),
      DeviceTemplate(
        templateId: 'sw_4',
        name: '4-switch board',
        description: '4 lights or appliance control',
        category: 'Basic',
        iconCode: Icons.toggle_on.codePoint,
        order: 3,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Switch 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's3',
            label: 'Switch 3',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's4',
            label: 'Switch 4',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['power']),
      ),
      DeviceTemplate(
        templateId: 'sw_6',
        name: '6-switch board',
        description: '6 lights or mixed loads',
        category: 'Basic',
        iconCode: Icons.toggle_on.codePoint,
        order: 4,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Switch 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's3',
            label: 'Switch 3',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's4',
            label: 'Switch 4',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's5',
            label: 'Switch 5',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's6',
            label: 'Switch 6',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['power', 'voltage']),
      ),
      DeviceTemplate(
        templateId: 'sw_2_fan',
        name: '2 switches + fan',
        description: '2 lights with fan speed control',
        category: 'Fan',
        iconCode: Icons.air.codePoint,
        order: 5,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Light 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Light 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 'f1',
            label: 'Fan Speed',
            type: SwitchType.fan,
            iconCode: Icons.air.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['temperature', 'humidity']),
      ),
      DeviceTemplate(
        templateId: 'sw_4_fan',
        name: '4 switches + fan',
        description: '4 switches with fan speed control',
        category: 'Fan',
        iconCode: Icons.air.codePoint,
        order: 6,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Light 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Light 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's3',
            label: 'Light 3',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's4',
            label: 'Light 4',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 'f1',
            label: 'Fan Speed',
            type: SwitchType.fan,
            iconCode: Icons.air.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['temperature', 'humidity', 'power']),
      ),
      DeviceTemplate(
        templateId: 'sw_2_dim',
        name: '2 switches + dimmer',
        description: '2 switches with brightness control',
        category: 'Dimmer',
        iconCode: Icons.wb_sunny_outlined.codePoint,
        order: 7,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Switch 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 'd1',
            label: 'Dimmer',
            type: SwitchType.dimmer,
            iconCode: Icons.wb_sunny_outlined.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['light-level', 'motion']),
      ),
      DeviceTemplate(
        templateId: 'sw_4_dim',
        name: '4 switches + dimmer',
        description: '4 switches with brightness control',
        category: 'Dimmer',
        iconCode: Icons.wb_sunny_outlined.codePoint,
        order: 8,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 's1',
            label: 'Switch 1',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's2',
            label: 'Switch 2',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's3',
            label: 'Switch 3',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 's4',
            label: 'Switch 4',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
          SwitchTemplate(
            switchId: 'd1',
            label: 'Dimmer',
            type: SwitchType.dimmer,
            iconCode: Icons.wb_sunny_outlined.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['light-level', 'motion', 'power']),
      ),
      DeviceTemplate(
        templateId: 'curtain',
        name: 'Curtain controller',
        description: 'Motorised curtain open/stop/close',
        category: 'Curtain',
        iconCode: Icons.curtains.codePoint,
        order: 9,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 'c1',
            label: 'Open',
            type: SwitchType.curtain,
            iconCode: Icons.arrow_upward.codePoint,
          ),
          SwitchTemplate(
            switchId: 'c2',
            label: 'Stop',
            type: SwitchType.curtain,
            iconCode: Icons.stop.codePoint,
          ),
          SwitchTemplate(
            switchId: 'c3',
            label: 'Close',
            type: SwitchType.curtain,
            iconCode: Icons.arrow_downward.codePoint,
          ),
        ],
        sensors: _sensorTemplates(['light-level', 'contact']),
      ),
      DeviceTemplate(
        templateId: 'scene_8',
        name: '8-button scene panel',
        description: 'Trigger room scenes and moods',
        category: 'Scene',
        iconCode: Icons.auto_awesome.codePoint,
        order: 10,
        isActive: true,
        switches: [
          SwitchTemplate(
            switchId: 'sc1',
            label: 'Scene 1',
            type: SwitchType.scene,
            iconCode: Icons.wb_sunny_outlined.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc2',
            label: 'Scene 2',
            type: SwitchType.scene,
            iconCode: Icons.nights_stay_outlined.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc3',
            label: 'Scene 3',
            type: SwitchType.scene,
            iconCode: Icons.movie_outlined.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc4',
            label: 'Scene 4',
            type: SwitchType.scene,
            iconCode: Icons.restaurant_outlined.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc5',
            label: 'Scene 5',
            type: SwitchType.scene,
            iconCode: Icons.fitness_center.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc6',
            label: 'Scene 6',
            type: SwitchType.scene,
            iconCode: Icons.bed.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc7',
            label: 'Scene 7',
            type: SwitchType.scene,
            iconCode: Icons.celebration.codePoint,
          ),
          SwitchTemplate(
            switchId: 'sc8',
            label: 'Scene 8',
            type: SwitchType.scene,
            iconCode: Icons.auto_awesome.codePoint,
          ),
        ],
      ),
      DeviceTemplate(
        templateId: 'sw_8',
        name: '8-switch panel',
        description: 'Large room full control',
        category: 'Max',
        iconCode: Icons.grid_on.codePoint,
        order: 11,
        isActive: true,
        switches: List.generate(
          8,
          (i) => SwitchTemplate(
            switchId: 's${i + 1}',
            label: 'Switch ${i + 1}',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ),
        sensors: _sensorTemplates(['power', 'voltage', 'current']),
      ),
      DeviceTemplate(
        templateId: 'sw_12',
        name: '12-switch panel',
        description: 'Multi-zone control',
        category: 'Max',
        iconCode: Icons.grid_on.codePoint,
        order: 12,
        isActive: true,
        switches: List.generate(
          12,
          (i) => SwitchTemplate(
            switchId: 's${i + 1}',
            label: 'Switch ${i + 1}',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ),
        sensors: _sensorTemplates(['power', 'voltage', 'current']),
      ),
      DeviceTemplate(
        templateId: 'sw_16',
        name: '16-switch panel',
        description: 'Industrial / large home',
        category: 'Max',
        iconCode: Icons.grid_on.codePoint,
        order: 13,
        isActive: true,
        switches: List.generate(
          16,
          (i) => SwitchTemplate(
            switchId: 's${i + 1}',
            label: 'Switch ${i + 1}',
            type: SwitchType.toggle,
            iconCode: Icons.lightbulb_outline.codePoint,
          ),
        ),
        sensors: _sensorTemplates(['power', 'voltage', 'current']),
      ),
    ];
  }

  // Scenes live under user
  CollectionReference _scenes(String uid) =>
      _db.collection('users').doc(uid).collection('scenes');

  Future<String> addScene(String uid, SceneModel scene) async {
    final ref = await _trackedAdd(_scenes(uid), scene.toMap(), 'addScene');
    return ref.id;
  }

  Stream<List<SceneModel>> streamScenes(String uid) {
    return _scenes(uid).snapshots().map((snap) {
      _recordListenerRead('streamScenes', snap.docs.length);
      return snap.docs
          .map(
            (doc) =>
                SceneModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<void> deleteScene(String uid, String sceneId) async {
    await _trackedDelete(_scenes(uid).doc(sceneId), 'deleteScene');
  }

  Future<void> updateSceneActive(
    String uid,
    String sceneId,
    bool isActive,
  ) async {
    await _trackedUpdate(_scenes(uid).doc(sceneId), {
      'isActive': isActive,
    }, 'updateSceneActive');
  }
}
