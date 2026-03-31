import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import '../services/mqtt_provider.dart';

class MqttSettingsScreen extends StatefulWidget {
  const MqttSettingsScreen({super.key});

  @override
  State<MqttSettingsScreen> createState() => _MqttSettingsScreenState();
}

class _MqttSettingsScreenState extends State<MqttSettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _apiKeyController;
  bool _useTls = false;
  bool _connecting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final mqtt = MqttProvider.read(context);
    _hostController = TextEditingController(text: mqtt.brokerHost);
    _portController =
        TextEditingController(text: mqtt.brokerPort.toString());
    _apiKeyController = TextEditingController(text: mqtt.apiKey);
    _useTls = mqtt.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final mqtt = MqttProvider.read(context);

    // Apply settings
    mqtt.brokerHost = _hostController.text.trim();
    mqtt.brokerPort = int.tryParse(_portController.text.trim()) ?? 1883;
    mqtt.apiKey = _apiKeyController.text.trim();
    mqtt.useTls = _useTls;

    setState(() {
      _connecting = true;
      _statusMessage = null;
    });

    final ok = await mqtt.connect();

    if (mounted) {
      setState(() {
        _connecting = false;
        _statusMessage = ok
            ? '✓ Connected to ${mqtt.brokerHost}:${mqtt.brokerPort}'
            : '✗ Failed to connect. Check broker settings.';
      });
    }
  }

  Future<void> _disconnect() async {
    final mqtt = MqttProvider.read(context);
    await mqtt.disconnect();
    if (mounted) {
      setState(() => _statusMessage = 'Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = MqttProvider.of(context); // rebuild on connection change
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('MQTT Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Connection status card
          Card(
            color: mqtt.isConnected
                ? Colors.green.withOpacity(0.12)
                : cs.errorContainer.withOpacity(0.3),
            child: ListTile(
              leading: Icon(
                mqtt.isConnected
                    ? Icons.wifi
                    : Icons.wifi_off,
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

          const SizedBox(height: 24),

          const Text('Broker',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),

          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: 'broker.emqx.io',
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
            onChanged: (v) => setState(() => _useTls = v),
            title: const Text('Use TLS / SSL'),
            subtitle: const Text('Port 8883 for secure connections'),
            secondary: const Icon(Icons.lock_outline),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.outlineVariant)),
          ),

          const SizedBox(height: 24),
          const Text('Security',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),

          TextFormField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'my_secret_api_key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key_outlined),
              helperText:
                  'Used in topic path and as MQTT password for authentication',
            ),
          ),

          const SizedBox(height: 8),
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
                Text('Topic format',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withOpacity(0.5))),
                const SizedBox(height: 4),
                Text(
                  'Control: smarthome/{apiKey}/{macAddress}/control\n'
                  'Status:  smarthome/{apiKey}/{macAddress}/status',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusMessage!.startsWith('✓')
                    ? Colors.green.withOpacity(0.1)
                    : cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusMessage!.startsWith('✓')
                      ? Colors.green
                      : cs.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _connecting ? null : (mqtt.isConnected ? null : _connect),
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi),
                  label: Text(_connecting ? 'Connecting…' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
