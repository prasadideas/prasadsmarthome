import 'package:flutter/material.dart';
import 'device_model.dart';

enum SwitchType { toggle, fan, dimmer, curtain, scene }

class SensorTemplate {
  final String sensorId;
  final String label;
  final String type;
  final String unit;
  final int iconCode;
  final double minValue;
  final double maxValue;
  final double step;
  final double defaultValue;

  const SensorTemplate({
    required this.sensorId,
    required this.label,
    required this.type,
    required this.unit,
    required this.iconCode,
    required this.minValue,
    required this.maxValue,
    required this.step,
    required this.defaultValue,
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');

  SensorTemplate copyWith({String? label, int? iconCode}) {
    return SensorTemplate(
      sensorId: sensorId,
      label: label ?? this.label,
      type: type,
      unit: unit,
      iconCode: iconCode ?? this.iconCode,
      minValue: minValue,
      maxValue: maxValue,
      step: step,
      defaultValue: defaultValue,
    );
  }

  factory SensorTemplate.fromMap(Map<String, dynamic> map) {
    return SensorTemplate(
      sensorId: map['sensorId'] ?? '',
      label: map['label'] ?? '',
      type: map['type'] ?? 'sensor',
      unit: map['unit'] ?? '',
      iconCode: map['iconCode'] ?? Icons.sensors.codePoint,
      minValue: (map['minValue'] as num?)?.toDouble() ?? 0,
      maxValue: (map['maxValue'] as num?)?.toDouble() ?? 100,
      step: (map['step'] as num?)?.toDouble() ?? 1,
      defaultValue: (map['defaultValue'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensorId': sensorId,
      'label': label,
      'type': type,
      'unit': unit,
      'iconCode': iconCode,
      'minValue': minValue,
      'maxValue': maxValue,
      'step': step,
      'defaultValue': defaultValue,
    };
  }
}

class SensorTemplateCatalog {
  static final List<SensorTemplate> generalSensors = [
    SensorTemplate(
      sensorId: 'temperature',
      label: 'Temperature',
      type: 'temperature',
      unit: '°C',
      iconCode: Icons.thermostat.codePoint,
      minValue: 10,
      maxValue: 45,
      step: 0.5,
      defaultValue: 24,
    ),
    SensorTemplate(
      sensorId: 'humidity',
      label: 'Humidity',
      type: 'humidity',
      unit: '%',
      iconCode: Icons.water_drop_outlined.codePoint,
      minValue: 0,
      maxValue: 100,
      step: 1,
      defaultValue: 45,
    ),
    SensorTemplate(
      sensorId: 'light-level',
      label: 'Light Level',
      type: 'light-level',
      unit: 'lux',
      iconCode: Icons.wb_sunny_outlined.codePoint,
      minValue: 0,
      maxValue: 1000,
      step: 10,
      defaultValue: 320,
 
    ),
    SensorTemplate(
      sensorId: 'motion',
      label: 'Motion',
      type: 'motion',
      unit: '',
      iconCode: Icons.directions_walk.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'contact',
      label: 'Door Contact',
      type: 'contact',
      unit: '',
      iconCode: Icons.sensor_door.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'smoke',
      label: 'Smoke',
      type: 'smoke',
      unit: '',
      iconCode: Icons.local_fire_department_outlined.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'gas',
      label: 'Gas Leak',
      type: 'gas',
      unit: '',
      iconCode: Icons.warning_amber_rounded.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'co2',
      label: 'CO2',
      type: 'co2',
      unit: 'ppm',
      iconCode: Icons.cloud_outlined.codePoint,
      minValue: 300,
      maxValue: 2000,
      step: 10,
      defaultValue: 420,
    ),
    SensorTemplate(
      sensorId: 'air-quality',
      label: 'Air Quality',
      type: 'air-quality',
      unit: 'AQI',
      iconCode: Icons.air.codePoint,
      minValue: 0,
      maxValue: 500,
      step: 1,
      defaultValue: 80,
    ),
    SensorTemplate(
      sensorId: 'water-level',
      label: 'Water Level',
      type: 'water-level',
      unit: '%',
      iconCode: Icons.waves.codePoint,
      minValue: 0,
      maxValue: 100,
      step: 1,
      defaultValue: 55,
    ),
    SensorTemplate(
      sensorId: 'water-leak',
      label: 'Water Leak',
      type: 'water-leak',
      unit: '',
      iconCode: Icons.water_drop.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'power',
      label: 'Power',
      type: 'power',
      unit: 'W',
      iconCode: Icons.bolt.codePoint,
      minValue: 0,
      maxValue: 5000,
      step: 10,
      defaultValue: 120,
    ),
    SensorTemplate(
      sensorId: 'voltage',
      label: 'Voltage',
      type: 'voltage',
      unit: 'V',
      iconCode: Icons.electric_bolt.codePoint,
      minValue: 0,
      maxValue: 260,
      step: 1,
      defaultValue: 230,
    ),
    SensorTemplate(
      sensorId: 'current',
      label: 'Current',
      type: 'current',
      unit: 'A',
      iconCode: Icons.electric_meter.codePoint,
      minValue: 0,
      maxValue: 32,
      step: 0.5,
      defaultValue: 2.5,
    ),
    SensorTemplate(
      sensorId: 'occupancy',
      label: 'Occupancy',
      type: 'occupancy',
      unit: '',
      iconCode: Icons.person_outline.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
    SensorTemplate(
      sensorId: 'vibration',
      label: 'Vibration',
      type: 'vibration',
      unit: '',
      iconCode: Icons.vibration.codePoint,
      minValue: 0,
      maxValue: 1,
      step: 1,
      defaultValue: 0,
    ),
  ];

  static SensorTemplate byType(String type) {
    return generalSensors.firstWhere(
      (sensor) => sensor.type == type,
      orElse: () => SensorTemplate(
        sensorId: type,
        label: type,
        type: type,
        unit: '',
        iconCode: Icons.sensors.codePoint,
        minValue: 0,
        maxValue: 100,
        step: 1,
        defaultValue: 0,
      ),
    );
  }

  static List<SensorTemplate> forTypes(Iterable<String> types) {
    return types.map(byType).toList(growable: false);
  }
}

class SwitchTemplate {
  final String switchId;
  final String label;
  final SwitchType type;
  final int iconCode; // store as int, convert to IconData at runtime

  SwitchTemplate({
    required this.switchId,
    required this.label,
    required this.type,
    required this.iconCode,
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');

  factory SwitchTemplate.fromMap(Map<String, dynamic> map) {
    return SwitchTemplate(
      switchId: map['switchId'] ?? '',
      label: map['label'] ?? '',
      type: SwitchType.values.firstWhere(
        (e) => e.name == (map['type'] ?? 'toggle'),
        orElse: () => SwitchType.toggle,
      ),
      iconCode: map['iconCode'] ?? Icons.lightbulb_outline.codePoint,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'switchId': switchId,
      'label': label,
      'type': type.name,
      'iconCode': iconCode,
    };
  }
}

class DeviceTemplate {
  final String templateId;
  final String name;
  final String description;
  final String category;
  final int iconCode;
  final int order;
  final bool isActive;
  final List<SwitchTemplate> switches;
  final List<SensorTemplate> sensors;

  DeviceTemplate({
    required this.templateId,
    required this.name,
    required this.description,
    required this.category,
    required this.iconCode,
    required this.order,
    required this.isActive,
    required this.switches,
    this.sensors = const [],
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');

  factory DeviceTemplate.fromMap(String id, Map<String, dynamic> map) {
    final rawSwitches = map['switches'] as List<dynamic>? ?? [];
    final rawSensors = map['sensors'] as List<dynamic>? ?? [];
    return DeviceTemplate(
      templateId: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Basic',
      iconCode: map['iconCode'] ?? Icons.toggle_on.codePoint,
      order: map['order'] ?? 99,
      isActive: map['isActive'] ?? true,
      switches: rawSwitches
          .map((s) => SwitchTemplate.fromMap(s as Map<String, dynamic>))
          .toList(),
      sensors: rawSensors
          .map((s) => SensorTemplate.fromMap(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'templateId': templateId,
      'name': name,
      'description': description,
      'category': category,
      'iconCode': iconCode,
      'order': order,
      'isActive': isActive,
      'switches': switches.map((s) => s.toMap()).toList(),
      'sensors': sensors.map((s) => s.toMap()).toList(),
    };
  }

  // Convert to SwitchModel list for saving to device
  List<SwitchModel> toSwitchModels() {
    return switches
        .map(
          (s) => SwitchModel(
            switchId: s.switchId,
            label: s.label,
            isOn: false,
            type: s.type.name,
            icon: s.iconCode.toString(),
            value: 0,
          ),
        )
        .toList();
  }

  List<SensorModel> toSensorModels() {
    return sensors
        .map(
          (s) => SensorModel(
            sensorId: s.sensorId,
            label: s.label,
            type: s.type,
            unit: s.unit,
            icon: s.iconCode.toString(),
            value: s.defaultValue,
            minValue: s.minValue,
            maxValue: s.maxValue,
            step: s.step,
          ),
        )
        .toList();
  }
}
