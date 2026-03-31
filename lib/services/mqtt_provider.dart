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
    if (provider == null) {
      throw FlutterError(
        'No MqttProvider found in widget tree.\n\n'
        'Fix: Make sure MainShell is wrapped with MqttProvider in main.dart:\n'
        'return MqttProvider(\n'
        '  mqtt: mqttService,\n'
        '  child: const MainShell(),\n'
        ');\n\n'
        'Also ensure you are NOT accessing MqttProvider from initState() '
        'before the widget tree is fully built. Use wisely with proper null checks.',
      );
    }
    return provider.notifier!;
  }

  /// Use this when you don't need to rebuild on changes (e.g., just publish).
  static MqttService read(BuildContext context) {
    final provider =
        context.getInheritedWidgetOfExactType<MqttProvider>();
    if (provider == null) {
      throw FlutterError(
        'No MqttProvider found in widget tree.\n\n'
        'Fix: Make sure MainShell is wrapped with MqttProvider in main.dart:\n'
        'return MqttProvider(\n'
        '  mqtt: mqttService,\n'
        '  child: const MainShell(),\n'
        ');\n\n'
        'Also ensure you are NOT accessing MqttProvider from initState() '
        'before the widget tree is fully built. Use wisely with proper null checks.',
      );
    }
    return provider.notifier!;
  }
}
