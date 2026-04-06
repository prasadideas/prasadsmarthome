import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../models/user_model.dart';
import '../models/device_template.dart';
import '../models/scene_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  // Get user document once (to read favouriteHomeId)
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<void> setUserThemeMode(String uid, String themeMode) async {
    await _db.collection('users').doc(uid).update({'themeMode': themeMode});
  }

  // ── Homes ──────────────────────────────────────────────────

  Future<void> addHome(String uid, HomeModel home) async {
    await _homes(uid).add(home.toMap());
  }

  // Stream — UI auto-updates when homes change
  Stream<List<HomeModel>> streamHomes(String uid) {
    return _homes(uid).snapshots().map(
      (snap) => snap.docs
          .map(
            (doc) =>
                HomeModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<void> deleteHome(String uid, String homeId) async {
    await _homes(uid).doc(homeId).delete();
  }

  // Update home name
  Future<void> updateHome(
    String uid,
    String homeId,
    String newName,
    String newAddress,
  ) async {
    await _homes(
      uid,
    ).doc(homeId).update({'homeName': newName, 'address': newAddress});
  }

  // Save favourite homeId into the user document
  Future<void> setFavouriteHome(String uid, String homeId) async {
    await _db.collection('users').doc(uid).update({'favouriteHomeId': homeId});
  }

  // ── Rooms ──────────────────────────────────────────────────

  Future<void> addRoom(String uid, String homeId, RoomModel room) async {
    await _rooms(uid, homeId).add(room.toMap());
  }

  Stream<List<RoomModel>> streamRooms(String uid, String homeId) {
    return _rooms(uid, homeId).snapshots().map(
      (snap) => snap.docs
          .map(
            (doc) =>
                RoomModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<void> deleteRoom(String uid, String homeId, String roomId) async {
    await _rooms(uid, homeId).doc(roomId).delete();
  }

  Future<void> updateRoom(
    String uid,
    String homeId,
    String roomId,
    String newName,
    String newIcon,
  ) async {
    await _rooms(
      uid,
      homeId,
    ).doc(roomId).update({'roomName': newName, 'icon': newIcon});
  }

  // ── Devices ────────────────────────────────────────────────

  Future<String> addDevice(String uid, DeviceModel device) async {
    final ref = await _devices(uid).add(device.toMap(uid));
    return ref.id;
  }

  // Find device by MAC address in BOTH locations, returns (documentId, data) or (null, null)
  Future<({String? docId, Map<String, dynamic>? data, bool isNewLocation})?>
      _findDeviceByMac(String uid, String macAddress) async {
    // First, try new location
    final newSnapshot = await _devices(uid)
        .where('macId', isEqualTo: macAddress)
        .limit(1)
        .get();

    if (newSnapshot.docs.isNotEmpty) {
      final doc = newSnapshot.docs.first;
      return (
        docId: doc.id,
        data: doc.data() as Map<String, dynamic>,
        isNewLocation: true
      );
    }

    // Try old location
    final oldSnapshot = await _db
        .collection('devices')
        .where('macId', isEqualTo: macAddress)
        .where('ownedBy', isEqualTo: uid)
        .limit(1)
        .get();

    if (oldSnapshot.docs.isNotEmpty) {
      final doc = oldSnapshot.docs.first;
      return (
        docId: doc.id,
        data: doc.data() as Map<String, dynamic>,
        isNewLocation: false
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
        await _devices(uid).doc(docId).update({
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      } else {
        await _db.collection('devices').doc(docId).update({
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      }
    } catch (e) {
      // Silently handle errors - device might be deleted
      debugPrint('[FirestoreService] Error updating heartbeat for $macAddress: $e');
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
        await _devices(uid).doc(docId).update({
          'isOnline': false,
        });
      } else {
        await _db.collection('devices').doc(docId).update({
          'isOnline': false,
        });
      }
    } catch (e) {
      debugPrint('[FirestoreService] Error marking offline for $macAddress: $e');
    }
  }

  // Update device heartbeat (try new location first, fallback to old)
  Future<void> updateDeviceHeartbeat(String uid, String deviceId) async {
    var doc = await _devices(uid).doc(deviceId).get();
    
    if (doc.exists) {
      await _devices(uid).doc(deviceId).update({
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'isOnline': true,
      });
    } else {
      // Try old location
      doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        await _db.collection('devices').doc(deviceId).update({
          'lastHeartbeat': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      }
    }
  }

  // Mark device as offline (try new location first, fallback to old)
  Future<void> markDeviceOffline(String uid, String deviceId) async {
    var doc = await _devices(uid).doc(deviceId).get();
    
    if (doc.exists) {
      await _devices(uid).doc(deviceId).update({
        'isOnline': false,
      });
    } else {
      // Try old location
      doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        await _db.collection('devices').doc(deviceId).update({
          'isOnline': false,
        });
      }
    }
  }

  // Stream all devices owned by this user (from new location + legacy location)
  Stream<List<DeviceModel>> streamDevices(String uid) {
    return _devices(uid)
        .snapshots()
        .asyncMap((newSnapshot) async {
          // Get devices from new location
          List<DeviceModel> newDevices = newSnapshot.docs
              .map((doc) => DeviceModel.fromMap(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  ))
              .toList();

          // Also get devices from old global location that belong to this user
          final oldSnapshot = await _db
              .collection('devices')
              .where('ownedBy', isEqualTo: uid)
              .get();

          List<DeviceModel> oldDevices = oldSnapshot.docs
              .map((doc) => DeviceModel.fromMap(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  ))
              .toList();

          // Combine and deduplicate
          final Map<String, DeviceModel> combined = {};
          for (var d in newDevices) {
            combined[d.deviceId] = d;
          }
          for (var d in oldDevices) {
            combined[d.deviceId] = d;  // Override if deviceId already exists
          }
          return combined.values.toList();
        });
  }

  // Stream only devices assigned to a specific room (from both old and new locations)
  Stream<List<DeviceModel>> streamDevicesInRoom(String uid, String roomId) {
    return _devices(uid)
        .where('linkedRoom', isEqualTo: roomId)
        .snapshots()
        .asyncMap((newSnapshot) async {
          // Get devices from new location
          List<DeviceModel> newDevices = newSnapshot.docs
              .map((doc) => DeviceModel.fromMap(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  ))
              .toList();

          // Also get devices from old global location with roomRef matching
          final oldSnapshot = await _db
              .collection('devices')
              .where('ownedBy', isEqualTo: uid)
              .where('linkedRoom', isEqualTo: roomId)
              .get();

          List<DeviceModel> oldDevices = oldSnapshot.docs
              .map((doc) => DeviceModel.fromMap(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  ))
              .toList();

          // Combine and deduplicate
          final Map<String, DeviceModel> combined = {};
          for (var d in newDevices) {
            combined[d.deviceId] = d;
          }
          for (var d in oldDevices) {
            combined[d.deviceId] = d;  // Override if deviceId already exists
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
    var doc = await _devices(uid).doc(deviceId).get();
    
    // If not found in new location, try old location
    if (!doc.exists) {
      doc = await _db.collection('devices').doc(deviceId).get();
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
      await _devices(uid).doc(deviceId).update({'switches': switches});
    } else {
      await _db.collection('devices').doc(deviceId).update({'switches': switches});
    }
  }

  // Set all switches in a room to off (or given value)
  Future<void> setRoomAllSwitchesOff(
    String uid,
    String roomId, {
    bool isOn = false,
  }) async {
    final querySnap = await _devices(uid)
        .where('linkedRoom', isEqualTo: roomId)
        .get();

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
      await batch.commit();
    }
  }

  // Assign to room (try new location first, fallback to old)
  Future<void> assignDeviceToRoom(
    String uid,
    String deviceId,
    String? roomId,
    String? homeId,
  ) async {
    var doc = await _devices(uid).doc(deviceId).get();
    
    if (doc.exists) {
      // Update in new location
      await _devices(uid).doc(deviceId).update({
        'linkedRoom': roomId,
        'linkedHome': homeId,
      });
    } else {
      // Try old location
      doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        await _db.collection('devices').doc(deviceId).update({
          'linkedRoom': roomId,
          'linkedHome': homeId,
        });
      }
    }
  }

  // Rename device (try new location first, fallback to old)
  Future<void> updateDevice(String uid, String deviceId, String newName) async {
    var doc = await _devices(uid).doc(deviceId).get();
    
    if (doc.exists) {
      await _devices(uid).doc(deviceId).update({'deviceName': newName});
    } else {
      doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        await _db.collection('devices').doc(deviceId).update({'deviceName': newName});
      }
    }
  }

  // Delete device (try new location first, fallback to old)
  Future<void> deleteDevice(String uid, String deviceId) async {
    var doc = await _devices(uid).doc(deviceId).get();
    
    if (doc.exists) {
      await _devices(uid).doc(deviceId).delete();
    } else {
      doc = await _db.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        await _db.collection('devices').doc(deviceId).delete();
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
    await _rooms(uid, homeId).doc(roomId).update({
      'deviceRefs': FieldValue.arrayUnion([deviceId]),
    });
  }

  // Remove device ref from room
  Future<void> removeDeviceRefFromRoom(
    String uid,
    String homeId,
    String roomId,
    String deviceId,
  ) async {
    await _rooms(uid, homeId).doc(roomId).update({
      'deviceRefs': FieldValue.arrayRemove([deviceId]),
    });
  }

  // Admin only — reassign device to another user
  Future<void> reassignDevice(String oldUid, String deviceId, String newUserId) async {
    final doc = await _devices(oldUid).doc(deviceId).get();
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;
    
    final oldOwner = data['ownedBy'];
    
    // Copy device to new user's collection
    await _devices(newUserId).doc(deviceId).set({
      ...data,
      'ownedBy': newUserId,
      'linkedRoom': null,
      'linkedHome': null,
      'lastOwnedBy': oldOwner,
    });
    
    // Delete from old user's collection
    await _devices(oldUid).doc(deviceId).delete();
  }

  // Stream all active device templates — ordered by display order
  Stream<List<DeviceTemplate>> streamDeviceTemplates() {
    return _db
        .collection('deviceTemplates')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => DeviceTemplate.fromMap(
                  doc.id,
                  doc.data(),
                ),
              )
              .toList(),
        );
  }

  // Admin only — seed initial templates (run once)
  Future<void> seedDeviceTemplates() async {
    final templates = _buildDefaultTemplates();
    final batch = _db.batch();
    for (final t in templates) {
      final ref = _db.collection('deviceTemplates').doc(t.templateId);
      batch.set(ref, t.toMap());
    }
    await batch.commit();
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
      ),
    ];
  }

  // Scenes live under user
  CollectionReference _scenes(String uid) =>
      _db.collection('users').doc(uid).collection('scenes');

  Future<String> addScene(String uid, SceneModel scene) async {
    final ref = await _scenes(uid).add(scene.toMap());
    return ref.id;
  }

  Stream<List<SceneModel>> streamScenes(String uid) {
    return _scenes(uid).snapshots().map(
      (snap) => snap.docs
          .map(
            (doc) =>
                SceneModel.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<void> deleteScene(String uid, String sceneId) async {
    await _scenes(uid).doc(sceneId).delete();
  }

  Future<void> updateSceneActive(
    String uid,
    String sceneId,
    bool isActive,
  ) async {
    await _scenes(uid).doc(sceneId).update({'isActive': isActive});
  }
}
