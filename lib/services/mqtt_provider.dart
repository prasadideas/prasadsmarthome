import 'package:flutter/material.dart';
import 'mqtt_service.dart';

/// Provides a singleton [MqttService] to the entire widget tree.
/// Wrap your MaterialApp (or at least MainShell) with this.
class MqttProvider extends InheritedNotifier<MqttService> {
  const MqttProvider({
    super.key,
    required MqttService mqtt,
    required super.child,
  }) : super(notifier: mqtt);

  static MqttService of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<MqttProvider>();
    assert(provider != null, 'No MqttProvider found in widget tree');
    return provider!.notifier!;
  }

  /// Use this when you don't need to rebuild on changes (e.g., just publish).
  static MqttService read(BuildContext context) {
    final provider =
        context.getInheritedWidgetOfExactType<MqttProvider>();
    assert(provider != null, 'No MqttProvider found in widget tree');
    return provider!.notifier!;
  }
}
