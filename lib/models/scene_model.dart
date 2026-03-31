import 'package:cloud_firestore/cloud_firestore.dart';

class SceneAction {
  final String deviceId;
  final String deviceName;
  final int switchIndex;
  final String switchLabel;
  final bool targetState;

  SceneAction({
    required this.deviceId,
    required this.deviceName,
    required this.switchIndex,
    required this.switchLabel,
    required this.targetState,
  });

  factory SceneAction.fromMap(Map<String, dynamic> map) {
    return SceneAction(
      deviceId: map['deviceId'] ?? '',
      deviceName: map['deviceName'] ?? '',
      switchIndex: map['switchIndex'] ?? 0,
      switchLabel: map['switchLabel'] ?? '',
      targetState: map['targetState'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'switchIndex': switchIndex,
      'switchLabel': switchLabel,
      'targetState': targetState,
    };
  }
}

class SceneModel {
  final String sceneId;
  final String name;
  final String icon;
  final String homeId;
  final List<SceneAction> actions;
  final bool isScheduled;
  final String? scheduledTime;   // "HH:mm" format
  final List<int> scheduledDays; // 1=Mon ... 7=Sun
  final bool isActive;
  final Timestamp? createdAt;

  SceneModel({
    required this.sceneId,
    required this.name,
    required this.icon,
    required this.homeId,
    required this.actions,
    this.isScheduled = false,
    this.scheduledTime,
    this.scheduledDays = const [],
    this.isActive = true,
    this.createdAt,
  });

  factory SceneModel.fromMap(String id, Map<String, dynamic> map) {
    return SceneModel(
      sceneId: id,
      name: map['name'] ?? '',
      icon: map['icon'] ?? 'auto_awesome',
      homeId: map['homeId'] ?? '',
      actions: (map['actions'] as List<dynamic>? ?? [])
          .map((a) => SceneAction.fromMap(a as Map<String, dynamic>))
          .toList(),
      isScheduled: map['isScheduled'] ?? false,
      scheduledTime: map['scheduledTime'],
      scheduledDays: List<int>.from(map['scheduledDays'] ?? []),
      isActive: map['isActive'] ?? true,
      createdAt: map['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'homeId': homeId,
      'actions': actions.map((a) => a.toMap()).toList(),
      'isScheduled': isScheduled,
      'scheduledTime': scheduledTime,
      'scheduledDays': scheduledDays,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}