import 'package:flutter/material.dart';
import 'device_model.dart';

enum SwitchType { toggle, fan, dimmer, curtain, scene }

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

  DeviceTemplate({
    required this.templateId,
    required this.name,
    required this.description,
    required this.category,
    required this.iconCode,
    required this.order,
    required this.isActive,
    required this.switches,
  });

  IconData get icon => IconData(iconCode, fontFamily: 'MaterialIcons');

  factory DeviceTemplate.fromMap(String id, Map<String, dynamic> map) {
    final rawSwitches = map['switches'] as List<dynamic>? ?? [];
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
    };
  }

  // Convert to SwitchModel list for saving to device
  List<SwitchModel> toSwitchModels() {
    return switches
        .map((s) => SwitchModel(
              switchId: s.switchId,
              label: s.label,
              isOn: false,
              type: s.type.name,
              icon: s.iconCode.toString(),
              value: 0,
            ))
        .toList();
  }
}