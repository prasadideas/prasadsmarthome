import 'package:flutter/material.dart';
import '../services/mqtt_provider.dart';
import '../services/mqtt_service.dart';
import '../widgets/firestore_metrics_card.dart';

class MqttSettingsScreen extends StatefulWidget {
  const MqttSettingsScreen({super.key});

  @override
  State<MqttSettingsScreen> createState() => _MqttSettingsScreenState();
}

class _MqttSettingsScreenState extends State<MqttSettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _apiKeyController;
  late TextEditingController _heartbeatIntervalController;
  late TextEditingController _offlineTimeoutController;
  bool _useTls = false;
  bool _connecting = false;
  String? _statusMessage;
  bool _statusOk = false;

  // Quick-pick presets for common public brokers
  static const _presets = [
    {'label': 'Mosquitto (test)', 'host': 'test.mosquitto.org', 'port': '1883'},
    {'label': 'EMQX (public)', 'host': 'broker.emqx.io', 'port': '1883'},
    {'label': 'HiveMQ (public)', 'host': 'broker.hivemq.com', 'port': '1883'},
  ];

  @override
  void initState() {
    super.initState();
    // Initialize controllers with default values first
    _hostController = TextEditingController();
    _portController = TextEditingController();
    _apiKeyController = TextEditingController();
    _heartbeatIntervalController = TextEditingController();
    _offlineTimeoutController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mqtt = MqttProvider.read(context);
    final prefs = await MqttService.loadHeartbeatSettings();

    if (!mounted) return;

    _hostController.text = mqtt.brokerHost;
    _portController.text = mqtt.brokerPort.toString();
    _apiKeyController.text = mqtt.apiKey;
    _heartbeatIntervalController.text = prefs['interval'].toString();
    _offlineTimeoutController.text = prefs['timeout'].toString();
    _useTls = mqtt.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    _heartbeatIntervalController.dispose();
    _offlineTimeoutController.dispose();
    super.dispose();
  }

  void _applyPreset(Map<String, String> preset) {
    setState(() {
      _hostController.text = preset['host']!;
      _portController.text = preset['port']!;
      _useTls = false;
    });
  }

  Future<void> _connect() async {
    final mqtt = MqttProvider.read(context);

    // Write settings into service before connecting
    mqtt.brokerHost = _hostController.text.trim();
    mqtt.brokerPort = int.tryParse(_portController.text.trim()) ?? 1883;
    mqtt.apiKey = _apiKeyController.text.trim();
    mqtt.useTls = _useTls;
    mqtt.heartbeatInterval = Duration(
      seconds: int.tryParse(_heartbeatIntervalController.text.trim()) ?? 30,
    );
    mqtt.offlineTimeout = Duration(
      seconds: int.tryParse(_offlineTimeoutController.text.trim()) ?? 60,
    );

    setState(() {
      _connecting = true;
      _statusMessage = null;
    });

    final ok = await mqtt.connect();

    // Save ALL settings to persistent storage if connection successful
    if (ok) {
      await mqtt.saveHeartbeatSettings();
      await mqtt.saveBrokerSettings();
    }

    if (mounted) {
      setState(() {
        _connecting = false;
        _statusOk = ok;
        _statusMessage = ok
            ? '✓ Connected to ${mqtt.brokerHost}:${mqtt.brokerPort}'
            : '✗ ${mqtt.lastError ?? "Connection failed — check broker host and port"}';
      });
    }
  }

  Future<void> _disconnect() async {
    final mqtt = MqttProvider.read(context);
    await mqtt.disconnect();
    if (mounted) {
      setState(() {
        _statusOk = false;
        _statusMessage = 'Disconnected';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = MqttProvider.of(context); // rebuild on isConnected change
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('MQTT Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Status card ──────────────────────────────────────
          Card(
            color: mqtt.isConnected
                ? Colors.green.withOpacity(0.12)
                : cs.errorContainer.withOpacity(0.25),
            child: ListTile(
              leading: Icon(
                mqtt.isConnected ? Icons.wifi : Icons.wifi_off,
                color: mqtt.isConnected ? Colors.green : cs.error,
              ),
              title: Text(
                mqtt.isConnected ? 'Connected' : 'Disconnected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: mqtt.isConnected ? Colors.green : cs.error,
                ),
              ),
              subtitle: mqtt.isConnected
                  ? Text('${mqtt.brokerHost}:${mqtt.brokerPort}')
                  : const Text('Not connected to any broker'),
            ),
          ),

          const SizedBox(height: 16),

          const FirestoreMetricsCard(screenLabel: 'MQTT Settings'),

          const SizedBox(height: 24),

          // ── Broker presets ───────────────────────────────────
          Text(
            'Quick select broker',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _presets.map((preset) {
              final active = _hostController.text == preset['host'];
              return ChoiceChip(
                label: Text(preset['label']!),
                selected: active,
                onSelected: (_) => _applyPreset(preset.cast<String, String>()),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Host / Port ──────────────────────────────────────
          Text(
            'Broker',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: 'test.mosquitto.org',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '1883',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.settings_ethernet),
            ),
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            value: _useTls,
            onChanged: (v) {
              setState(() {
                _useTls = v;
                if (v && _portController.text == '1883') {
                  _portController.text = '8883';
                } else if (!v && _portController.text == '8883') {
                  _portController.text = '1883';
                }
              });
            },
            title: const Text('Use TLS / SSL'),
            subtitle: const Text('Switches port to 8883'),
            secondary: const Icon(Icons.lock_outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.outlineVariant),
            ),
          ),

          const SizedBox(height: 24),

          // ── API key ──────────────────────────────────────────
          Text(
            'Security',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'my_secret_key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key_outlined),
              helperText: 'Embedded in topic path for namespacing',
            ),
          ),

          const SizedBox(height: 10),

          // Topic preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Topic format',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface.withOpacity(0.45),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Control: smarthome/{apiKey}/{mac}/control\n'
                  'Status:  smarthome/{apiKey}/{mac}/status',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Heartbeat & Timeout ──────────────────────────────
          Text(
            'Heartbeat Detection',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _heartbeatIntervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Heartbeat Interval (seconds)',
              hintText: '30',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.favorite),
              helperText: 'How often devices send heartbeat signals',
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _offlineTimeoutController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Offline Timeout (seconds)',
              hintText: '60',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.timer_off),
              helperText:
                  'Mark device offline if no heartbeat after this duration',
            ),
          ),

          const SizedBox(height: 28),

          // ── Status / error message ───────────────────────────
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusOk
                    ? Colors.green.withOpacity(0.1)
                    : cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusOk ? Colors.green : cs.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Connect / Disconnect buttons ─────────────────────
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_connecting || mqtt.isConnected)
                      ? null
                      : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi),
                  label: Text(_connecting ? 'Connecting…' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (mqtt.isConnected) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.wifi_off),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
