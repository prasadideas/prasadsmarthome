import 'package:cloud_firestore/cloud_firestore.dart';

class SwitchModel {
  final String switchId;
  String label;         // editable
  bool isOn;
  String type;          // toggle / fan / dimmer / curtain / scene
  String icon;          // icon codePoint as string
  int value;            // fan speed (0-5) or dimmer (0-100)

  SwitchModel({
    required this.switchId,
    required this.label,
    required this.isOn,
    this.type = 'toggle',
    this.icon = '',
    this.value = 0,
  });

  factory SwitchModel.fromMap(Map<String, dynamic> map) {
    return SwitchModel(
      switchId: map['switchId'] ?? '',
      label: map['label'] ?? '',
      isOn: map['isOn'] ?? false,
      type: map['type'] ?? 'toggle',
      icon: map['icon'] ?? '',
      value: map['value'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'switchId': switchId,
      'label': label,
      'isOn': isOn,
      'type': type,
      'icon': icon,
      'value': value,
    };
  }
}

class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String type;
  final bool isOnline;
  final String? linkedRoom;  // renamed from roomRef
  final String? linkedHome;  // new field
  final String ownedBy;      // new field
  final List<SwitchModel> switches;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.type,
    required this.isOnline,
    required this.switches,
    required this.ownedBy,
    this.linkedRoom,
    this.linkedHome,
  });

  factory DeviceModel.fromMap(String id, Map<String, dynamic> map) {
    List<SwitchModel> parsedSwitches = [];
    final rawSwitches = map['switches'];

    if (rawSwitches is List) {
      parsedSwitches = rawSwitches
          .map((s) => SwitchModel.fromMap(s as Map<String, dynamic>))
          .toList();
    } else if (rawSwitches is Map) {
      parsedSwitches = rawSwitches.values
          .map((s) => SwitchModel.fromMap(s as Map<String, dynamic>))
          .toList();
    }

    return DeviceModel(
      deviceId: id,
      deviceName: map['deviceName'] ?? '',
      type: map['type'] ?? '',
      isOnline: map['isOnline'] ?? false,
      ownedBy: map['ownedBy'] ?? '',
      linkedRoom: map['linkedRoom'],   // renamed
      linkedHome: map['linkedHome'],   // new
      switches: parsedSwitches,
    );
  }

  // uid passed in so ownedBy is always set correctly
  Map<String, dynamic> toMap(String uid) {
    return {
      'deviceName': deviceName,
      'type': type,
      'isOnline': isOnline,
      'ownedBy': uid,          // top level owner field
      'linkedRoom': linkedRoom,
      'linkedHome': linkedHome,
      'switches': switches.map((s) => s.toMap()).toList(),
      'lastSeen': FieldValue.serverTimestamp(),
    };
  }
}