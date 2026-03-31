import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Holds the real-time state of a single switch as seen by the app.
class SwitchState {
  final bool isOn;
  final double value;      // 0–100 for dimmer, 0–5 for fan
  final bool inProgress;   // waiting for device echo

  const SwitchState({
    required this.isOn,
    required this.value,
    this.inProgress = false,
  });

  SwitchState copyWith({bool? isOn, double? value, bool? inProgress}) {
    return SwitchState(
      isOn: isOn ?? this.isOn,
      value: value ?? this.value,
      inProgress: inProgress ?? this.inProgress,
    );
  }
}

/// Key that uniquely identifies one switch across all devices.
class SwitchKey {
  final String deviceId;   // MAC address of the board
  final int switchIndex;

  const SwitchKey(this.deviceId, this.switchIndex);

  @override
  bool operator ==(Object other) =>
      other is SwitchKey &&
      other.deviceId == deviceId &&
      other.switchIndex == switchIndex;

  @override
  int get hashCode => Object.hash(deviceId, switchIndex);
}

/// Payload published to the CONTROL topic.
/// Payload received from the STATUS topic.
///
/// JSON schema:
/// {
///   "switchIndex": 0,
///   "isOn": true,
///   "value": 0.0,      // 0-100 dimmer / 0-5 fan / 0 toggle
///   "type": "toggle"   // toggle | fan | dimmer | curtain | scene
/// }

class MqttService extends ChangeNotifier {
  // ── Configuration (settable from UI) ──────────────────────
  String brokerHost;
  int brokerPort;
  String apiKey;   // used both as MQTT password and in topic path
  bool useTls;

  // ── Internal state ─────────────────────────────────────────
  MqttServerClient? _client;
  bool _connected = false;
  bool get isConnected => _connected;

  // switchKey → current state
  final Map<SwitchKey, SwitchState> _states = {};

  // switchKey → timer that reverts inProgress on timeout
  final Map<SwitchKey, Timer> _timeouts = {};

  // timeout duration (10 seconds by default, configurable)
  Duration timeoutDuration;

  // Stream controller so widgets can react to status updates
  final _stateController =
      StreamController<Map<SwitchKey, SwitchState>>.broadcast();
  Stream<Map<SwitchKey, SwitchState>> get stateStream => _stateController.stream;

  MqttService({
    this.brokerHost = 'broker.hivemq.com', // More reliable public broker
    this.brokerPort = 1883,
    this.apiKey = 'smarthome_default_key',
    this.useTls = false,
    this.timeoutDuration = const Duration(seconds: 10),
  });

  // ── Topic helpers ──────────────────────────────────────────

  /// Control topic: app → device
  /// smarthome/{apiKey}/{macAddress}/control
  String controlTopic(String macAddress) =>
      'smarthome/$apiKey/$macAddress/control';

  /// Status topic: device → app
  /// smarthome/{apiKey}/{macAddress}/status
  String statusTopic(String macAddress) =>
      'smarthome/$apiKey/$macAddress/status';

  /// Wildcard to subscribe all status topics for this API key
  String get allStatusTopicWildcard => 'smarthome/$apiKey/+/status';

  // ── Connection ─────────────────────────────────────────────

  Future<bool> connect() async {
    await disconnect();

    final clientId = 'smarthome_app_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);
    _client!.logging(on: true); // Enable detailed logging
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.connectTimeoutPeriod = 10000; // 10 second timeout
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onAutoReconnect = () => debugPrint('[MQTT] Auto-reconnecting...');

    if (useTls) {
      _client!.secure = true;
    }

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();
    _client!.connectionMessage = connMessage;

    try {
      debugPrint('[MQTT] Attempting to connect to $brokerHost:$brokerPort...');
      await _client!.connect();
      debugPrint('[MQTT] Connection attempt completed');
    } catch (e) {
      debugPrint('[MQTT] Connect error: $e');
      // Provide more specific error messages
      String errorMessage = 'Connection failed';
      if (e.toString().contains('NoConnectionException')) {
        errorMessage = 'Broker not responding. Check host/port or try a different broker.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Network error. Check internet connection.';
      } else if (e.toString().contains('HandshakeException')) {
        errorMessage = 'SSL/TLS error. Check TLS settings.';
      }
      debugPrint('[MQTT] Error message: $errorMessage');
      _connected = false;
      notifyListeners();
      return false;
    }

    if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
      debugPrint('[MQTT] Successfully connected!');
      _subscribeToStatusTopics();
      _client!.updates?.listen(_onMessage);
      return true;
    } else {
      debugPrint('[MQTT] Connection status: ${_client!.connectionStatus?.state}');
      debugPrint('[MQTT] Connection status details: ${_client!.connectionStatus}');
      _connected = false;
      notifyListeners();
      return false;
    }
  }

  void _onConnected() {
    _connected = true;
    debugPrint('[MQTT] Connected to $brokerHost:$brokerPort');
    notifyListeners();
  }

  void _onDisconnected() {
    _connected = false;
    debugPrint('[MQTT] Disconnected');
    notifyListeners();
  }

  void _subscribeToStatusTopics() {
    _client!.subscribe(allStatusTopicWildcard, MqttQos.atLeastOnce);
    debugPrint('[MQTT] Subscribed to $allStatusTopicWildcard');
  }

  Future<void> disconnect() async {
    _client?.disconnect();
    _client = null;
    _connected = false;
  }

  // ── Publish a command ──────────────────────────────────────

  /// Publish a switch command and mark it as inProgress.
  /// [macAddress] is the device's MAC (used as deviceId in models).
  /// [switchIndex] is zero-based index.
  /// [isOn] target on/off state.
  /// [value] slider value (0-100 dimmer, 0-5 fan, 0 for toggle).
  /// [type] 'toggle' | 'fan' | 'dimmer' | 'curtain' | 'scene'
  void publishCommand({
    required String macAddress,
    required int switchIndex,
    required bool isOn,
    double value = 0,
    String type = 'toggle',
  }) {
    if (!_connected || _client == null) {
      debugPrint('[MQTT] Not connected — command dropped');
      return;
    }

    final key = SwitchKey(macAddress, switchIndex);

    // Mark as in-progress optimistically
    _states[key] = SwitchState(isOn: isOn, value: value, inProgress: true);
    _stateController.add(Map.from(_states));
    notifyListeners();

    // Cancel any existing timeout
    _timeouts[key]?.cancel();

    // Start timeout — revert inProgress if no echo arrives
    _timeouts[key] = Timer(timeoutDuration, () {
      final current = _states[key];
      if (current != null && current.inProgress) {
        _states[key] = current.copyWith(inProgress: false);
        _stateController.add(Map.from(_states));
        notifyListeners();
        debugPrint('[MQTT] Timeout for switch $switchIndex on $macAddress');
      }
    });

    final payload = jsonEncode({
      'switchIndex': switchIndex,
      'isOn': isOn,
      'value': value,
      'type': type,
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    _client!.publishMessage(
      controlTopic(macAddress),
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    debugPrint('[MQTT] Published to ${controlTopic(macAddress)}: $payload');
  }

  // ── Receive status messages ────────────────────────────────

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final recMessage = msg.payload as MqttPublishMessage;
      final payloadStr = MqttPublishPayload.bytesToStringAsString(
        recMessage.payload.message,
      );

      debugPrint('[MQTT] Status received on $topic: $payloadStr');

      // Extract MAC address from topic: smarthome/{apiKey}/{mac}/status
      final parts = topic.split('/');
      if (parts.length < 4) continue;
      final macAddress = parts[2];

      try {
        final data = jsonDecode(payloadStr) as Map<String, dynamic>;
        final switchIndex = data['switchIndex'] as int? ?? 0;
        final isOn = data['isOn'] as bool? ?? false;
        final value = (data['value'] as num?)?.toDouble() ?? 0.0;

        final key = SwitchKey(macAddress, switchIndex);

        // Cancel timeout — device responded
        _timeouts[key]?.cancel();
        _timeouts.remove(key);

        // Update state, clear inProgress
        _states[key] = SwitchState(isOn: isOn, value: value, inProgress: false);
        _stateController.add(Map.from(_states));
        notifyListeners();
      } catch (e) {
        debugPrint('[MQTT] Failed to parse status payload: $e');
      }
    }
  }

  // ── State accessors ────────────────────────────────────────

  SwitchState? getState(String macAddress, int switchIndex) {
    return _states[SwitchKey(macAddress, switchIndex)];
  }

  /// Seed initial states from Firestore snapshot (so UI shows correct state
  /// before any MQTT message arrives).
  void seedStates(String macAddress, List<Map<String, dynamic>> switches) {
    for (int i = 0; i < switches.length; i++) {
      final key = SwitchKey(macAddress, i);
      if (!_states.containsKey(key)) {
        _states[key] = SwitchState(
          isOn: switches[i]['isOn'] as bool? ?? false,
          value: (switches[i]['value'] as num?)?.toDouble() ?? 0.0,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final t in _timeouts.values) {
      t.cancel();
    }
    _stateController.close();
    disconnect();
    super.dispose();
  }
}
