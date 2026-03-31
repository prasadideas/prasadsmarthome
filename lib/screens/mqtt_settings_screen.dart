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
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    // Initialize with defaults immediately
    _hostController = TextEditingController(text: 'test.mosquitto.org'); // Reliable public broker
    _portController = TextEditingController(text: '1883');
    _apiKeyController = TextEditingController(text: 'smarthome_default_key');
    
    // Load actual values after first frame to ensure provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final mqtt = MqttProvider.read(context);
        _hostController.text = mqtt.brokerHost;
        _portController.text = mqtt.brokerPort.toString();
        _apiKeyController.text = mqtt.apiKey;
        _useTls = mqtt.useTls;
        setState(() {});
      } catch (e) {
        setState(() {
          _initializationError = e.toString();
        });
        debugPrint('[MQTT Settings] Initialization error: $e');
      }
    });
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
    mqtt.apiKey = _apiKeyController.text.trim().isEmpty ? 'smarthome_default_key' : _apiKeyController.text.trim();
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

  Future<void> _testConnection() async {
    final mqtt = MqttProvider.read(context);

    // Use minimal test settings
    final originalHost = mqtt.brokerHost;
    final originalPort = mqtt.brokerPort;
    final originalApiKey = mqtt.apiKey;
    final originalTls = mqtt.useTls;

    // Test with known working public broker
    mqtt.brokerHost = 'test.mosquitto.org';
    mqtt.brokerPort = 1883;
    mqtt.apiKey = 'test_key';
    mqtt.useTls = false;

    setState(() {
      _connecting = true;
      _statusMessage = 'Testing connection to test.mosquitto.org...';
    });

    final ok = await mqtt.connect();

    // Restore original settings
    mqtt.brokerHost = originalHost;
    mqtt.brokerPort = originalPort;
    mqtt.apiKey = originalApiKey;
    mqtt.useTls = originalTls;

    if (mounted) {
      setState(() {
        _connecting = false;
        _statusMessage = ok
            ? '✓ Test successful! Broker is reachable.'
            : '✗ Test failed. Check network or try different broker.';
      });
    }
  }

  void _showConnectionHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Troubleshooting'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Try these public MQTT brokers:'),
            SizedBox(height: 8),
            Text('• TCP: test.mosquitto.org:1883'),
            Text('• TCP: broker.emqx.io:1883'),
            Text('• WebSocket: broker.emqx.io:8083 (recommended for emulators)'),
            Text('• WebSocket: test.mosquitto.org:8080'),
            SizedBox(height: 12),
            Text('For secure connections:'),
            Text('• TCP TLS: test.mosquitto.org:8883'),
            Text('• WebSocket TLS: broker.emqx.io:8084'),
            SizedBox(height: 12),
            Text('API Key is optional for public brokers.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If initialization error occurred, show error message
    if (_initializationError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('MQTT Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                const Text('Error loading MQTT settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_initializationError ?? 'Unknown error', style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    try {
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
              trailing: mqtt.isConnected ? null : IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showConnectionHelp(context),
                tooltip: 'Connection help',
              ),
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
              labelText: 'API Key (optional for public brokers)',
              hintText: 'smarthome_default_key',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key_outlined),
              helperText:
                  'Used in topic path. Leave empty for public brokers.',
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: _connecting ? null : _testConnection,
                icon: const Icon(Icons.science),
                tooltip: 'Test connection with minimal settings',
                style: IconButton.styleFrom(
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
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
    } catch (e) {
      debugPrint('[MQTT Settings Build Error] $e');
      return Scaffold(
        appBar: AppBar(title: const Text('MQTT Settings')),
        body: Center(
          child: Text('Error: $e'),
        ),
      );
    }
  }
}
