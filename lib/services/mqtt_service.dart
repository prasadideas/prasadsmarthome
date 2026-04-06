import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';

/// Holds the real-time state of a single switch as seen by the app.
class SwitchState {
  final bool isOn;
  final double value; // 0–100 for dimmer OR fan speed
  final bool inProgress; // waiting for device echo

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
  final String deviceId; // MAC address of the board
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

/// MQTT payload schema (both control and status topics):
/// {
///   "switchIndex": 0,
///   "isOn": true,
///   "value": 75.0,   // 0-100 for fan speed % or dimmer %; 0 for toggle
///   "type": "toggle" // toggle | fan | dimmer | curtain | scene
/// }
///
/// Topic format (API key in path — no password auth):
///   Control : smarthome/{apiKey}/{macAddress}/control
///   Status  : smarthome/{apiKey}/{macAddress}/status

class MqttService extends ChangeNotifier {
  // ── Configuration (settable from settings UI) ──────────────
  String brokerHost;
  int brokerPort;
  String apiKey; // embedded in topic path for security
  bool useTls;
  final bool persistDeviceStatusToFirestore;
  Duration timeoutDuration;
  Duration heartbeatInterval;
  Duration offlineTimeout;

  final FirestoreService _firestoreService;

  // ── Internal ───────────────────────────────────────────────
  MqttServerClient? _client;
  bool _connected = false;
  bool get isConnected => _connected;

  String? _lastError;
  String? get lastError => _lastError;

  // switchKey → current state
  final Map<SwitchKey, SwitchState> _states = {};

  // switchKey → timeout timer
  final Map<SwitchKey, Timer> _timeouts = {};

  // deviceId → last heartbeat timestamp
  final Map<String, DateTime> _lastHeartbeats = {};

  // deviceId → offline detection timer
  final Map<String, Timer> _heartbeatTimeouts = {};

  // deviceId → last status written to Firestore when persistence is enabled
  final Map<String, bool> _persistedDeviceStatuses = {};

  // Broadcast stream so multiple widgets can listen
  final _stateController =
      StreamController<Map<SwitchKey, SwitchState>>.broadcast();
  Stream<Map<SwitchKey, SwitchState>> get stateStream =>
      _stateController.stream;

  // Device online/offline status stream
  final _deviceStatusController =
      StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get deviceStatusStream =>
      _deviceStatusController.stream;

  MqttService({
    this.brokerHost = 'test.mosquitto.org',
    this.brokerPort = 1883,
    this.apiKey = 'smarthome_default',
    this.useTls = false,
    this.persistDeviceStatusToFirestore = false,
    this.timeoutDuration = const Duration(seconds: 10),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.offlineTimeout = const Duration(seconds: 60),
    required FirestoreService firestoreService,
  }) : _firestoreService = firestoreService;

  // ── Topic helpers ──────────────────────────────────────────

  /// App → device
  String controlTopic(String macAddress) =>
      'smarthome/$apiKey/$macAddress/control';

  /// Device → app
  String statusTopic(String macAddress) =>
      'smarthome/$apiKey/$macAddress/status';

  /// Wildcard subscription for all devices under this API key
  String get _allStatusWildcard => 'smarthome/$apiKey/+/status';

  /// Heartbeat topic for device status
  String heartbeatTopic(String macAddress) =>
      'smarthome/$apiKey/$macAddress/heartbeat';

  /// Wildcard subscription for all heartbeat topics
  String get _allHeartbeatWildcard => 'smarthome/$apiKey/+/heartbeat';

  // ── Connect ────────────────────────────────────────────────

  Future<bool> connect() async {
    await disconnect(); // clean slate
    _lastError = null;
    Object? zoneError;
    StackTrace? zoneStackTrace;

    // Unique client ID prevents "client already connected" rejections
    final clientId =
        'smarthome_${DateTime.now().millisecondsSinceEpoch % 100000}';

    _client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);
    _client!.logging(on: kDebugMode);
    _client!.keepAlivePeriod = 60;
    _client!.connectTimeoutPeriod = 10000; // 10 s — avoids silent hangs
    _client!.autoReconnect = false; // we manage reconnection manually

    // Callbacks
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = (topic) => debugPrint('[MQTT] Subscribed: $topic');
    _client!.onSubscribeFail = (topic) =>
        debugPrint('[MQTT] Subscribe FAILED: $topic');

    if (useTls) {
      _client!.secure = true;
      // For public brokers that use self-signed certs you may need:
      // _client!.securityContext = SecurityContext.defaultContext;
    }

    // ── Connection message ─────────────────────────────────
    // IMPORTANT: Do NOT call .authenticateAs() for public brokers that
    // don't require auth — it causes CONNACK code 4 (bad credentials).
    // Do NOT chain .withWillQos() — it breaks the connect message builder
    // on several broker implementations.
    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _client!.connectionMessage = connMessage;

    try {
      await runZonedGuarded<Future<void>>(
        () async {
          await _client!.connect();
        },
        (error, stackTrace) {
          zoneError ??= error;
          zoneStackTrace ??= stackTrace;
        },
      );
    } on NoConnectionException catch (e) {
      _lastError = 'NoConnectionException: $e';
      debugPrint('[MQTT] $_lastError');
      _cleanup();
      return false;
    } on SocketException catch (e) {
      _lastError = 'SocketException: $e';
      debugPrint('[MQTT] $_lastError');
      _cleanup();
      return false;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[MQTT] Connect error: $e');
      _cleanup();
      return false;
    }

    if (zoneError != null) {
      _lastError = zoneError.toString();
      debugPrint('[MQTT] Connect zone error: $zoneError');
      if (zoneStackTrace != null) {
        debugPrint(zoneStackTrace.toString());
      }
      _cleanup();
      return false;
    }

    final state = _client!.connectionStatus?.state;
    final returnCode = _client!.connectionStatus?.returnCode;
    debugPrint('[MQTT] Connection state: $state  returnCode: $returnCode');

    if (state != MqttConnectionState.connected) {
      _lastError = 'Connection refused. Return code: $returnCode';
      _cleanup();
      return false;
    }

    // Listen for incoming messages
    _client!.updates?.listen(_onMessage);

    // Subscribe to all status topics for this API key
    _client!.subscribe(_allStatusWildcard, MqttQos.atLeastOnce);

    // Subscribe to all heartbeat topics
    _client!.subscribe(_allHeartbeatWildcard, MqttQos.atLeastOnce);

    return true;
  }

  void _onConnected() {
    _connected = true;
    _lastError = null;
    debugPrint('[MQTT] Connected to $brokerHost:$brokerPort');
    notifyListeners();
  }

  void _onDisconnected() {
    _connected = false;
    debugPrint('[MQTT] Disconnected');
    _publishDeviceStatusSnapshot();
    notifyListeners();
  }

  void _cleanup() {
    _connected = false;
    _client?.disconnect();
    _client = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _cleanup();
  }

  // ── Publish a command ──────────────────────────────────────

  /// Publishes a switch command and marks it as in-progress.
  /// [macAddress] — device MAC (used as deviceId in Firestore models).
  /// [value]      — 0-100 for fan/dimmer; 0 for toggles.
  /// [type]       — 'toggle' | 'fan' | 'dimmer' | 'curtain' | 'scene'
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

    // Optimistically mark as in-progress
    _states[key] = SwitchState(isOn: isOn, value: value, inProgress: true);
    _stateController.add(Map.from(_states));
    notifyListeners();

    // Cancel any existing timeout for this switch
    _timeouts[key]?.cancel();

    // Revert inProgress if device doesn't echo within timeout
    _timeouts[key] = Timer(timeoutDuration, () {
      final current = _states[key];
      if (current != null && current.inProgress) {
        // Revert to previous state (opposite of what we sent)
        _states[key] = SwitchState(
          isOn: !isOn, // revert
          value: value,
          inProgress: false,
        );
        _stateController.add(Map.from(_states));
        notifyListeners();
        debugPrint(
          '[MQTT] Timeout — reverting switch $switchIndex on $macAddress',
        );
      }
    });

    final payload = jsonEncode({
      'switchIndex': switchIndex,
      'isOn': isOn,
      'value': value,
      'type': type,
    });

    final builder = MqttClientPayloadBuilder()..addString(payload);
    _client!.publishMessage(
      controlTopic(macAddress),
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    debugPrint('[MQTT] → ${controlTopic(macAddress)} : $payload');
  }

  // ── Receive status updates ─────────────────────────────────

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final pub = msg.payload as MqttPublishMessage;
      final raw = MqttPublishPayload.bytesToStringAsString(pub.payload.message);

      debugPrint('[MQTT] ← $topic : $raw');

      // Extract MAC from: smarthome/{apiKey}/{mac}/status or smarthome/{apiKey}/{mac}/heartbeat
      final parts = topic.split('/');
      if (parts.length < 4) continue;
      final macAddress = parts[2];
      final messageType = parts[3]; // 'status' or 'heartbeat'

      if (messageType == 'heartbeat') {
        _handleHeartbeat(macAddress, raw);
      } else if (messageType == 'status') {
        _handleStatus(macAddress, raw);
      }
    }
  }

  // ── Handle heartbeat messages ──────────────────────────────

  void _handleHeartbeat(String macAddress, String raw) {
    try {
      // Heartbeat payload is just a timestamp
      final timestamp = DateTime.now();
      _lastHeartbeats[macAddress] = timestamp;

      // Cancel existing offline timer
      _heartbeatTimeouts[macAddress]?.cancel();

      // Set device as online
      _updateDeviceStatus(macAddress, true);
      _publishDeviceStatusSnapshot();
      notifyListeners();

      // Start offline detection timer
      _heartbeatTimeouts[macAddress] = Timer(offlineTimeout, () {
        _updateDeviceStatus(macAddress, false);
        _publishDeviceStatusSnapshot();
        notifyListeners();
        debugPrint('[MQTT] Device $macAddress marked offline (no heartbeat)');
      });

      debugPrint('[MQTT] Heartbeat from $macAddress at $timestamp');
    } catch (e) {
      debugPrint('[MQTT] Failed to handle heartbeat: $e  raw=$raw');
    }
  }

  // ── Handle status messages ──────────────────────────────────

  void _handleStatus(String macAddress, String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final switchIndex = (data['switchIndex'] as num?)?.toInt() ?? 0;
      final isOn = data['isOn'] as bool? ?? false;
      final value = (data['value'] as num?)?.toDouble() ?? 0.0;

      final key = SwitchKey(macAddress, switchIndex);

      // Device echoed — cancel timeout
      _timeouts[key]?.cancel();
      _timeouts.remove(key);

      // Update state, clear inProgress
      _states[key] = SwitchState(isOn: isOn, value: value, inProgress: false);
      _stateController.add(Map.from(_states));
      notifyListeners();

      // Mark device as online when we receive status message
      _lastHeartbeats[macAddress] = DateTime.now();
      _updateDeviceStatus(macAddress, true);
      _publishDeviceStatusSnapshot();
      debugPrint(
        '[MQTT] Status from $macAddress switch $switchIndex: ${isOn ? 'ON' : 'OFF'}',
      );
    } catch (e) {
      debugPrint('[MQTT] Failed to parse status: $e  raw=$raw');
    }
  }

  // ── Send heartbeat (typically called by devices, but useful for testing) ──

  void sendHeartbeat(String macAddress) {
    if (!_connected || _client == null) return;

    final payload = jsonEncode({'timestamp': DateTime.now().toIso8601String()});

    final builder = MqttClientPayloadBuilder()..addString(payload);
    _client!.publishMessage(
      heartbeatTopic(macAddress),
      MqttQos.atLeastOnce,
      builder.payload!,
    );

    debugPrint('[MQTT] → ${heartbeatTopic(macAddress)} : $payload');
  }

  // ── Device status accessors ────────────────────────────────

  bool isDeviceOnline(String deviceId) {
    final lastHeartbeat = _lastHeartbeats[deviceId];
    if (lastHeartbeat == null) return false;
    return DateTime.now().difference(lastHeartbeat) < offlineTimeout;
  }

  DateTime? getLastHeartbeat(String deviceId) => _lastHeartbeats[deviceId];

  SwitchState? getState(String macAddress, int switchIndex) =>
      _states[SwitchKey(macAddress, switchIndex)];

  /// Seed initial Firestore state into MQTT state map so the UI shows the
  /// correct values before any MQTT message arrives.
  /// Call this every time the Firestore snapshot updates.
  void seedStates(
    String macAddress,
    List<Map<String, dynamic>> switches, {
    int startIndex = 0,
  }) {
    bool changed = false;
    for (int i = 0; i < switches.length; i++) {
      final key = SwitchKey(macAddress, startIndex + i);
      // Only seed if not already in map (don't overwrite live MQTT state)
      if (!_states.containsKey(key)) {
        _states[key] = SwitchState(
          isOn: switches[i]['isOn'] as bool? ?? false,
          value: (switches[i]['value'] as num?)?.toDouble() ?? 0.0,
        );
        changed = true;
      }
    }
    if (changed) {
      _stateController.add(Map.from(_states));
    }
  }

  // Device status management

  void _publishDeviceStatusSnapshot() {
    if (_deviceStatusController.isClosed) return;

    final now = DateTime.now();
    _deviceStatusController.add({
      for (final entry in _lastHeartbeats.entries)
        entry.key: now.difference(entry.value) < offlineTimeout,
    });
  }

  void _updateDeviceStatus(String macAddress, bool isOnline) async {
    try {
      if (!persistDeviceStatusToFirestore) {
        return;
      }

      final previousStatus = _persistedDeviceStatuses[macAddress];
      if (previousStatus == isOnline) {
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint(
          '[MQTT] No user logged in - skipping device status update for $macAddress',
        );
        return;
      }

      if (isOnline) {
        // Look up device by MAC address and update
        await _firestoreService.updateDeviceHeartbeatByMac(uid, macAddress);
      } else {
        // Mark device offline by MAC address
        await _firestoreService.markDeviceOfflineByMac(uid, macAddress);
      }
      _persistedDeviceStatuses[macAddress] = isOnline;
      debugPrint(
        '[MQTT] Device $macAddress status updated: ${isOnline ? 'online' : 'offline'}',
      );
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint(
          '[MQTT] Permission denied updating device $macAddress - device may not exist yet',
        );
      } else {
        debugPrint('[MQTT] Failed to update device status: $e');
      }
    }
  }

  // ── Save/Load preferences ──────────────────────────────────

  static const String _heartbeatIntervalKey = 'mqtt_heartbeat_interval';
  static const String _offlineTimeoutKey = 'mqtt_offline_timeout';

  /// Save broker settings to SharedPreferences
  Future<void> saveBrokerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_broker_host', brokerHost);
      await prefs.setInt('mqtt_broker_port', brokerPort);
      await prefs.setString('mqtt_api_key', apiKey);
      await prefs.setBool('mqtt_use_tls', useTls);
      debugPrint('[MQTT] Broker settings saved to preferences');
    } catch (e) {
      debugPrint('[MQTT] Failed to save broker settings: $e');
    }
  }

  /// Save heartbeat settings to SharedPreferences
  Future<void> saveHeartbeatSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_heartbeatIntervalKey, heartbeatInterval.inSeconds);
      await prefs.setInt(_offlineTimeoutKey, offlineTimeout.inSeconds);
      debugPrint('[MQTT] Heartbeat settings saved to preferences');
    } catch (e) {
      debugPrint('[MQTT] Failed to save heartbeat settings: $e');
    }
  }

  /// Load heartbeat settings from SharedPreferences
  static Future<Map<String, int>> loadHeartbeatSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final interval = prefs.getInt(_heartbeatIntervalKey) ?? 30;
      final timeout = prefs.getInt(_offlineTimeoutKey) ?? 60;
      debugPrint(
        '[MQTT] Loaded heartbeat settings: interval=$interval, timeout=$timeout',
      );
      return {'interval': interval, 'timeout': timeout};
    } catch (e) {
      debugPrint('[MQTT] Failed to load heartbeat settings: $e');
      return {'interval': 30, 'timeout': 60};
    }
  }

  /// Load broker and heartbeat settings from SharedPreferences
  /// Returns a Map with keys: host, port, apiKey, useT ls, interval, timeout
  static Future<Map<String, dynamic>> loadAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = {
        'host': prefs.getString('mqtt_broker_host') ?? 'test.mosquitto.org',
        'port': prefs.getInt('mqtt_broker_port') ?? 1883,
        'apiKey': prefs.getString('mqtt_api_key') ?? 'smarthome_default',
        'useTls': prefs.getBool('mqtt_use_tls') ?? false,
        'interval': prefs.getInt(_heartbeatIntervalKey) ?? 30,
        'timeout': prefs.getInt(_offlineTimeoutKey) ?? 60,
      };
      debugPrint('[MQTT] Loaded all settings: $settings');
      return settings;
    } catch (e) {
      debugPrint('[MQTT] Failed to load settings: $e');
      return {
        'host': 'test.mosquitto.org',
        'port': 1883,
        'apiKey': 'smarthome_default',
        'useTls': false,
        'interval': 30,
        'timeout': 60,
      };
    }
  }

  @override
  void dispose() {
    for (final t in _timeouts.values) {
      t.cancel();
    }
    for (final t in _heartbeatTimeouts.values) {
      t.cancel();
    }
    _stateController.close();
    _deviceStatusController.close();
    disconnect();
    super.dispose();
  }
}
