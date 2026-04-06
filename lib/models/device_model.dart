import 'package:cloud_firestore/cloud_firestore.dart';

class SwitchModel {
  final String switchId;
  String label; // editable
  bool isOn;
  String type; // toggle / fan / dimmer / curtain / scene
  String icon; // icon codePoint as string
  int value; // fan speed (0-5) or dimmer (0-100)

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

class SensorModel {
  final String sensorId;
  String label;
  String type;
  String unit;
  String icon;
  double value;
  double minValue;
  double maxValue;
  double step;

  SensorModel({
    required this.sensorId,
    required this.label,
    required this.type,
    this.unit = '',
    this.icon = '',
    this.value = 0,
    this.minValue = 0,
    this.maxValue = 100,
    this.step = 1,
  });

  factory SensorModel.fromMap(Map<String, dynamic> map) {
    return SensorModel(
      sensorId: map['sensorId'] ?? '',
      label: map['label'] ?? '',
      type: map['type'] ?? 'sensor',
      unit: map['unit'] ?? '',
      icon: map['icon'] ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0,
      minValue: (map['minValue'] as num?)?.toDouble() ?? 0,
      maxValue: (map['maxValue'] as num?)?.toDouble() ?? 100,
      step: (map['step'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensorId': sensorId,
      'label': label,
      'type': type,
      'unit': unit,
      'icon': icon,
      'value': value,
      'minValue': minValue,
      'maxValue': maxValue,
      'step': step,
    };
  }
}

class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String type;
  final bool isOnline;
  final String? linkedRoom; // renamed from roomRef
  final String? linkedHome; // new field
  final String ownedBy; // new field
  final DateTime? lastHeartbeat; // new field for heartbeat tracking
  final String? macId; // MAC address of the device
  final List<SwitchModel> switches;
  final List<SensorModel> sensors;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.type,
    required this.isOnline,
    required this.switches,
    required this.ownedBy,
    this.sensors = const [],
    this.linkedRoom,
    this.linkedHome,
    this.lastHeartbeat,
    this.macId,
  });

  factory DeviceModel.fromMap(String id, Map<String, dynamic> map) {
    List<SwitchModel> parsedSwitches = [];
    List<SensorModel> parsedSensors = [];
    final rawSwitches = map['switches'];
    final rawSensors = map['sensors'];

    if (rawSwitches is List) {
      parsedSwitches = rawSwitches
          .map((s) => SwitchModel.fromMap(s as Map<String, dynamic>))
          .toList();
    } else if (rawSwitches is Map) {
      parsedSwitches = rawSwitches.values
          .map((s) => SwitchModel.fromMap(s as Map<String, dynamic>))
          .toList();
    }

    if (rawSensors is List) {
      parsedSensors = rawSensors
          .map((s) => SensorModel.fromMap(s as Map<String, dynamic>))
          .toList();
    } else if (rawSensors is Map) {
      parsedSensors = rawSensors.values
          .map((s) => SensorModel.fromMap(s as Map<String, dynamic>))
          .toList();
    }

    return DeviceModel(
      deviceId: id,
      deviceName: map['deviceName'] ?? '',
      type: map['type'] ?? '',
      isOnline: map['isOnline'] ?? false,
      ownedBy: map['ownedBy'] ?? '',
      linkedRoom: map['linkedRoom'], // renamed
      linkedHome: map['linkedHome'], // new
      sensors: parsedSensors,
      switches: parsedSwitches,
      lastHeartbeat: map['lastHeartbeat'] != null
          ? (map['lastHeartbeat'] as Timestamp).toDate()
          : null,
      macId: map['macId'],
    );
  }

  // uid passed in so ownedBy is always set correctly
  Map<String, dynamic> toMap(String uid) {
    return {
      'deviceName': deviceName,
      'type': type,
      'isOnline': isOnline,
      'ownedBy': uid, // top level owner field
      'linkedRoom': linkedRoom,
      'linkedHome': linkedHome,
      'macId': macId,
      'switches': switches.map((s) => s.toMap()).toList(),
      'sensors': sensors.map((s) => s.toMap()).toList(),
      'lastSeen': FieldValue.serverTimestamp(),
      'lastHeartbeat': lastHeartbeat != null
          ? Timestamp.fromDate(lastHeartbeat!)
          : FieldValue.serverTimestamp(),
    };
  }
}
