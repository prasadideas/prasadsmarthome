import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../services/mqtt_service.dart';
import '../services/mqtt_provider.dart';

/// A single switch tile that:
/// - Shows current ON/OFF state (from MQTT, falling back to Firestore seed)
/// - Fan type   → ON/OFF toggle + 0–100% speed slider
/// - Dimmer type → 0–100% brightness slider
/// - Any other  → simple ON/OFF toggle
/// - Spinning progress indicator while waiting for device echo
/// - Other switches remain fully interactive while one is in-progress
class SwitchTile extends StatefulWidget {
  final String deviceMac; // device MAC address (= deviceId in Firestore)
  final int switchIndex;
  final SwitchModel switchModel; // latest data from Firestore
  final bool compact; // true = small grid tile, false = full-width

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
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mqtt = MqttProvider.of(context);

    // Seed initial Firestore state so UI is correct before any MQTT arrives
    mqtt.seedStates(widget.deviceMac, [widget.switchModel.toMap()]);

    // Pull current state immediately (no wait for stream event)
    _mqttState = mqtt.getState(widget.deviceMac, widget.switchIndex);

    // Subscribe to future changes
    _sub?.cancel();
    _sub = mqtt.stateStream.listen((states) {
      final key = SwitchKey(widget.deviceMac, widget.switchIndex);
      if (states.containsKey(key) && mounted) {
        setState(() => _mqttState = states[key]);
        if (_mqttState!.inProgress) {
          _spinController.repeat();
        } else {
          _spinController.stop();
          _spinController.reset();
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

  // ── State getters — prefer MQTT state, fall back to Firestore ─

  bool get _isOn => _mqttState?.isOn ?? widget.switchModel.isOn;
  double get _value =>
      _mqttState?.value ?? widget.switchModel.value.toDouble();
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
      value: _isFan || _isDimmer ? _value : 0,
      type: _type,
    );
  }

  void _setSlider(MqttService mqtt, double newVal) {
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
    final cs = Theme.of(context).colorScheme;

    if (_hasSlider && !widget.compact) {
      return _buildSliderTile(mqtt, cs);
    }
    return widget.compact
        ? _buildCompactTile(mqtt, cs)
        : _buildFullTile(mqtt, cs);
  }

  // ── Compact 2-col grid tile ────────────────────────────────

  Widget _buildCompactTile(MqttService mqtt, ColorScheme cs) {
    return GestureDetector(
      onTap: () => _toggle(mqtt),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          // Use theme-aware colors — visible in both light and dark mode
          color: _isOn ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isOn ? cs.primary : cs.outlineVariant,
          ),
          boxShadow: _isOn
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.22),
                    blurRadius: 6,
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
                  color: _isOn ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _statusWidget(cs, _isOn ? cs.onPrimary : cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── Full-width list tile ───────────────────────────────────

  Widget _buildFullTile(MqttService mqtt, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _isOn ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: ListTile(
        leading: _iconWidget(cs),
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
            color: (_isOn ? cs.onPrimaryContainer : cs.onSurfaceVariant)
                .withOpacity(0.65),
          ),
        ),
        trailing: _statusWidget(
          cs,
          _isOn ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
        onTap: () => _toggle(mqtt),
      ),
    );
  }

  // ── Slider tile — fan (0-100%) or dimmer (0-100%) ──────────

  Widget _buildSliderTile(MqttService mqtt, ColorScheme cs) {
    // Both fan and dimmer use 0–100 range
    final label = _isFan
        ? 'Speed: ${_value.toInt()}%'
        : 'Brightness: ${_value.toInt()}%';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _isOn ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                _iconWidget(cs),
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
                          color: (_isOn
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant)
                              .withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                // ON/OFF toggle button alongside spinner
                if (_inProgress)
                  _statusWidget(cs,
                      _isOn ? cs.onPrimaryContainer : cs.onSurfaceVariant)
                else
                  IconButton(
                    icon: Icon(
                      _isOn ? Icons.power : Icons.power_off_outlined,
                      color: _isOn ? cs.primary : cs.onSurfaceVariant,
                    ),
                    tooltip: _isOn ? 'Turn off' : 'Turn on',
                    onPressed: () => _toggle(mqtt),
                  ),
              ],
            ),

            // Slider — 0 to 100
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: _value.clamp(0.0, 100.0),
                min: 0,
                max: 100,
                divisions: 20, // 5% steps
                activeColor: cs.primary,
                inactiveColor: cs.outlineVariant,
                label: '${_value.toInt()}%',
                // Disable slider while command is in flight
                onChanged: _inProgress
                    ? null
                    : (v) {
                        // Local preview while dragging
                        setState(() {
                          _mqttState = SwitchState(
                            isOn: v > 0,
                            value: v,
                            inProgress: false,
                          );
                        });
                      },
                onChangeEnd: (v) => _setSlider(mqtt, v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared sub-widgets ─────────────────────────────────────

  /// Spinning indicator when in-progress, toggle icon otherwise.
  Widget _statusWidget(ColorScheme cs, Color color) {
    if (_inProgress) {
      return SizedBox(
        width: 22,
        height: 22,
        child: RotationTransition(
          turns: _spinController,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
        ),
      );
    }
    return Icon(
      _isOn ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
      color: color,
      size: 30,
    );
  }

  Widget _iconWidget(ColorScheme cs) {
    final code = int.tryParse(widget.switchModel.icon) ??
        Icons.lightbulb_outline.codePoint;
    return Icon(
      IconData(code, fontFamily: 'MaterialIcons'),
      color: _isOn ? cs.primary : cs.onSurfaceVariant,
      size: 22,
    );
  }
}