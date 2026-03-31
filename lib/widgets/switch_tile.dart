import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../services/mqtt_service.dart';
import '../services/mqtt_provider.dart';

/// A single switch tile that:
/// - Shows current ON/OFF state (from MQTT or seeded from Firestore)
/// - Shows fan slider (0–5 steps) or dimmer slider (0–100) when applicable
/// - Shows a spinning progress indicator while waiting for device echo
/// - Allows controlling other switches while one is in progress
class SwitchTile extends StatefulWidget {
  final String deviceMac;    // device's MAC address (used as deviceId)
  final int switchIndex;
  final SwitchModel switchModel; // initial data from Firestore
  final bool compact;           // true = small grid tile, false = full list tile

  const SwitchTile({
    super.key,
    required this.deviceMac,
    required this.switchIndex,
    required this.switchModel,
    this.compact = true,
  });

  @override
  State<SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<SwitchTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  StreamSubscription? _sub;
  SwitchState? _mqttState;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mqtt = MqttProvider.of(context);

    // Seed initial state from Firestore data so UI is correct before any MQTT
    mqtt.seedStates(widget.deviceMac, [widget.switchModel.toMap()]);

    // Subscribe to state stream
    _sub?.cancel();
    _sub = mqtt.stateStream.listen((states) {
      final key = SwitchKey(widget.deviceMac, widget.switchIndex);
      if (states.containsKey(key)) {
        if (mounted) {
          setState(() => _mqttState = states[key]);
          if (_mqttState!.inProgress) {
            _spinController.repeat();
          } else {
            _spinController.stop();
            _spinController.reset();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  // ── Getters pulling from MQTT state or falling back to Firestore ───

  bool get _isOn =>
      _mqttState?.isOn ?? widget.switchModel.isOn;

  double get _value =>
      _mqttState?.value ??
      widget.switchModel.value.toDouble();

  bool get _inProgress => _mqttState?.inProgress ?? false;

  String get _type => widget.switchModel.type;

  bool get _isFan => _type == 'fan';
  bool get _isDimmer => _type == 'dimmer';
  bool get _hasSlider => _isFan || _isDimmer;

  // ── Publish helpers ────────────────────────────────────────

  void _toggle(MqttService mqtt) {
    mqtt.publishCommand(
      macAddress: widget.deviceMac,
      switchIndex: widget.switchIndex,
      isOn: !_isOn,
      value: _value,
      type: _type,
    );
  }

  void _setSliderValue(MqttService mqtt, double newVal) {
    mqtt.publishCommand(
      macAddress: widget.deviceMac,
      switchIndex: widget.switchIndex,
      isOn: newVal > 0,
      value: newVal,
      type: _type,
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mqtt = MqttProvider.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_hasSlider && !widget.compact) {
      return _buildSliderTile(mqtt, theme, colorScheme);
    }

    return widget.compact
        ? _buildCompactTile(mqtt, theme, colorScheme)
        : _buildFullTile(mqtt, theme, colorScheme);
  }

  // ── Compact grid tile (used in room cards and device screen) ──

  Widget _buildCompactTile(
      MqttService mqtt, ThemeData theme, ColorScheme cs) {
    final onColor = cs.primary;
    final offColor = cs.surfaceContainerHighest; // visible in both light & dark
    final onTextColor = cs.onPrimary;
    final offTextColor = cs.onSurfaceVariant;

    return GestureDetector(
      onTap: () => _toggle(mqtt),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isOn ? onColor : offColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isOn ? onColor : cs.outlineVariant,
            width: 1,
          ),
          boxShadow: _isOn
              ? [
                  BoxShadow(
                    color: onColor.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.switchModel.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: _isOn ? onTextColor : offTextColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _buildStatusIndicator(cs, onTextColor, offTextColor),
          ],
        ),
      ),
    );
  }

  // ── Full list tile (used in device detail screen) ──────────

  Widget _buildFullTile(
      MqttService mqtt, ThemeData theme, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _isOn
          ? cs.primaryContainer
          : cs.surfaceContainerHighest,
      child: ListTile(
        leading: _buildIconWidget(cs),
        title: Text(
          widget.switchModel.label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _isOn ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          _type[0].toUpperCase() + _type.substring(1),
          style: TextStyle(
            fontSize: 12,
            color: _isOn
                ? cs.onPrimaryContainer.withOpacity(0.7)
                : cs.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
        trailing: _buildStatusIndicator(
          cs,
          cs.onPrimaryContainer,
          cs.onSurfaceVariant,
        ),
        onTap: () => _toggle(mqtt),
      ),
    );
  }

  // ── Slider tile for fan/dimmer ─────────────────────────────

  Widget _buildSliderTile(
      MqttService mqtt, ThemeData theme, ColorScheme cs) {
    final maxVal = _isFan ? 5.0 : 100.0;
    final divisions = _isFan ? 5 : 20;
    final label = _isFan
        ? 'Speed: ${_value.toInt()}'
        : 'Brightness: ${_value.toInt()}%';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _isOn
          ? cs.primaryContainer
          : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIconWidget(cs),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.switchModel.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _isOn
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: _isOn
                              ? cs.onPrimaryContainer.withOpacity(0.7)
                              : cs.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusIndicator(
                  cs,
                  cs.onPrimaryContainer,
                  cs.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: _value.clamp(0, maxVal),
                min: 0,
                max: maxVal,
                divisions: divisions,
                activeColor: cs.primary,
                inactiveColor: cs.outlineVariant,
                onChanged: _inProgress
                    ? null
                    : (v) => setState(() => _mqttState = SwitchState(
                          isOn: v > 0,
                          value: v,
                          inProgress: false,
                        )),
                onChangeEnd: (v) => _setSliderValue(mqtt, v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared sub-widgets ─────────────────────────────────────

  Widget _buildStatusIndicator(
      ColorScheme cs, Color onColor, Color offColor) {
    if (_inProgress) {
      return SizedBox(
        width: 20,
        height: 20,
        child: RotationTransition(
          turns: _spinController,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: onColor,
          ),
        ),
      );
    }
    return Icon(
      _isOn ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
      color: _isOn ? onColor : offColor,
      size: 28,
    );
  }

  Widget _buildIconWidget(ColorScheme cs) {
    final iconCode = int.tryParse(widget.switchModel.icon) ??
        Icons.lightbulb_outline.codePoint;
    return Icon(
      IconData(iconCode, fontFamily: 'MaterialIcons'),
      color: _isOn ? cs.primary : cs.onSurfaceVariant,
      size: 22,
    );
  }
}
