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

  CollectionReference get _devicesRef => _db.collection('devices');

  // ── User ───────────────────────────────────────────────────

  // Call this right after signup to create the user document
  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  // Get user document once (to read favouriteHomeId)
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data() as Map<String, dynamic>?;
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
    final ref = await _devicesRef.add(device.toMap(uid)); // pass uid into toMap
    return ref.id;
  }

  // Stream all devices owned by this user
  Stream<List<DeviceModel>> streamDevices(String uid) {
    return _devicesRef
        .where('ownedBy', isEqualTo: uid) // filter by owner
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => DeviceModel.fromMap(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // Stream only devices assigned to a specific room
  Stream<List<DeviceModel>> streamDevicesInRoom(String uid, String roomId) {
    return _devicesRef
        .where('roomRef', isEqualTo: roomId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => DeviceModel.fromMap(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  // Toggle switch
  Future<void> toggleSwitch(
    String uid,
    String deviceId,
    int switchIndex,
    bool newValue,
  ) async {
    final doc = await _devicesRef.doc(deviceId).get();
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

    await _devicesRef.doc(deviceId).update({'switches': switches});
  }

  // Set all switches in a room to off (or given value)
  Future<void> setRoomAllSwitchesOff(
    String uid,
    String roomId, {
    bool isOn = false,
  }) async {
    final querySnap = await _devicesRef
        .where('ownedBy', isEqualTo: uid)
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

  // Assign to room
  Future<void> assignDeviceToRoom(
    String uid,
    String deviceId,
    String? roomId,
    String? homeId,
  ) async {
    await _devicesRef.doc(deviceId).update({
      'linkedRoom': roomId,
      'linkedHome': homeId,
    });
  }

  // Rename device
  Future<void> updateDevice(String uid, String deviceId, String newName) async {
    await _devicesRef.doc(deviceId).update({'deviceName': newName});
  }

  // Delete device
  Future<void> deleteDevice(String uid, String deviceId) async {
    await _devicesRef.doc(deviceId).delete();
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
  Future<void> reassignDevice(String deviceId, String newUserId) async {
    final doc = await _devicesRef.doc(deviceId).get();
    final oldOwner = (doc.data() as Map<String, dynamic>)['ownedBy'];
    await _devicesRef.doc(deviceId).update({
      'ownedBy': newUserId,
      'linkedRoom': null,
      'linkedHome': null,
      'lastOwnedBy': oldOwner,
    });
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
                  doc.data() as Map<String, dynamic>,
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

  Future<void> addScene(String uid, SceneModel scene) async {
    await _scenes(uid).add(scene.toMap());
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

  // Execute a scene — apply all switch states
  Future<void> triggerScene(String uid, SceneModel scene) async {
    for (final action in scene.actions) {
      final doc = await _devicesRef.doc(action.deviceId).get();
      final data = doc.data() as Map<String, dynamic>;

      final rawSwitches = data['switches'];
      List<Map<String, dynamic>> switches = [];
      if (rawSwitches is List) {
        switches = rawSwitches
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      } else if (rawSwitches is Map) {
        switches = rawSwitches.values
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      }

      if (action.switchIndex < switches.length) {
        switches[action.switchIndex]['isOn'] = action.targetState;
      }

      await _devicesRef.doc(action.deviceId).update({'switches': switches});
    }
  }
}
