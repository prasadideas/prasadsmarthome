# Switch/Device Control Architecture

## Overview
This document maps how users control switches and devices in the Prasad Smart Home Flutter app, including device online status tracking.

---

## 1. Room Card Widget (Displays Devices in Home Tab)

**Location:** [lib/screens/home_tab.dart](lib/screens/home_tab.dart#L246)

**Class:** `_RoomCard`

### Purpose
- Displays a card for each room showing the room name and associated devices/switches
- Shows switch dots/tiles that are clickable
- Includes a "Turn off all" button to control all switches in that room

### Key Code Section
```dart
// ── Attractive Room Card ───────────────────────────────────────
class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final String uid;
  final HomeModel home;
  final FirestoreService firestoreService;

  // Location: lib/screens/home_tab.dart#L244-L330
  // Displays room name, icon, and streams devices in that room
  // Shows individual switch tiles as a grid
  
  @override
  Widget build(BuildContext context) {
    // Header bar with room name and "Turn off all" button
    // Device switch dots (compact grid tiles)
  }
}
```

### Relevant Code Snippets
- **Header with room icon and turn-off-all button:** [lib/screens/home_tab.dart](lib/screens/home_tab.dart#L310-L355)
- **Device list streaming:** [lib/screens/home_tab.dart](lib/screens/home_tab.dart#L360-L400)

---

## 2. Switch Control UI Widgets

### A. Compact Switch Tile (Grid format - Room Cards)

**Location:** [lib/widgets/switch_tile.dart](lib/widgets/switch_tile.dart#L134-L180)

**Class:** `SwitchTile._buildCompactTile()`

**Purpose:** Small toggle button shown in room cards and device list

**Features:**
- ON/OFF state with color indication (green when on, gray when off)
- Touch/tap to toggle
- Shows loading spinner while waiting for device response
- Shows switch label

```dart
Widget _buildCompactTile(
    MqttService mqtt, ThemeData theme, ColorScheme cs) {
  final onColor = cs.primary;
  final offColor = cs.surfaceContainerHighest;
  
  return GestureDetector(
    onTap: () => _toggle(mqtt),  // Publishes MQTT command
    child: AnimatedContainer(
      decoration: BoxDecoration(
        color: _isOn ? onColor : offColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(widget.switchModel.label),
          _buildStatusIndicator(cs, onTextColor, offTextColor),
        ],
      ),
    ),
  );
}
```

### B. Full List Tile (Detail view)

**Location:** [lib/widgets/switch_tile.dart](lib/widgets/switch_tile.dart#L192-L225)

**Class:** `SwitchTile._buildFullTile()`

**Purpose:** Full card format for device detail screen

**Features:**
- Shows icon, label, type (toggle/fan/dimmer)
- Toggle on tap
- Tap-to-control functionality

### C. Slider Tile (For Fan/Dimmer Controls)

**Location:** [lib/widgets/switch_tile.dart](lib/widgets/switch_tile.dart#L227-L280)

**Class:** `SwitchTile._buildSliderTile()`

**Purpose:** Slider control for fan speeds (0-5) or dimmer brightness (0-100)

**Features:**
- Slider with real-time value adjustments
- Shows value label (e.g., "Speed: 3" or "Brightness: 75%")
- On-tap sends MQTT command

---

## 3. Device Card with Switches

**Location:** [lib/screens/devices_screen.dart](lib/screens/devices_screen.dart#L283-L375)

**Class:** `_DeviceCard`

**Purpose:** Shows device info, online status, and all its switches

### Key Features
- **Device name** with icon
- **Online status indicator** (green dot + "Online"/"Offline" text)
- **Switch tiles** displayed in a grid below

### Online Status Display
```dart
// Location: lib/screens/devices_screen.dart#L325-L350
Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: device.isOnline
        ? Colors.green.withOpacity(0.12)
        : cs.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Row(
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: device.isOnline ? Colors.green : cs.onSurface.withOpacity(0.3),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        device.isOnline ? 'Online' : 'Offline',
        style: TextStyle(
          color: device.isOnline ? Colors.green : cs.onSurface.withOpacity(0.4),
        ),
      ),
    ],
  ),
);
```

---

## 4. MQTT Control Message Publishing

**Location:** [lib/services/mqtt_service.dart](lib/services/mqtt_service.dart#L238-L295)

**Method:** `MqttService.publishCommand()`

### Purpose
Sends switch control commands to devices via MQTT

### How Controls Flow:
1. User taps switch in UI
2. `_toggle()` method called in switch_tile.dart
3. Calls `mqtt.publishCommand()` with switch parameters
4. Command published to MQTT topic: `smarthome/{apiKey}/{macAddress}/control`
5. Payload contains: switchIndex, isOn, value, type

### Code Structure
```dart
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

  // Optimistically mark as in-progress (show spinner)
  _states[key] = SwitchState(isOn: isOn, value: value, inProgress: true);
  _stateController.add(Map.from(_states));
  notifyListeners();

  // Set timeout: if no echo received in 10 seconds, revert state
  _timeouts[key] = Timer(timeoutDuration, () {
    if (current != null && current.inProgress) {
      _states[key] = SwitchState(
        isOn: !isOn,  // revert
        value: value,
        inProgress: false,
      );
      _stateController.add(Map.from(_states));
    }
  });

  // Publish to broker
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
```

### Publish Helpers in SwitchTile
```dart
// Location: lib/widgets/switch_tile.dart#L102-L124
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
```

---

## 5. Device Online Status Management

### A. Device Model

**Location:** [lib/models/device_model.dart](lib/models/device_model.dart#L47)

**Properties:**
```dart
class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String type;
  final bool isOnline;  // ← Online status flag
  final DateTime? lastHeartbeat;  // ← Heartbeat timestamp
  final List<SwitchModel> switches;
  // ... other fields
}
```

### B. MQTT Heartbeat Handling

**Location:** [lib/services/mqtt_service.dart](lib/services/mqtt_service.dart#L310-L340)

**Method:** `MqttService._handleHeartbeat()`

**Purpose:** Updates device online/offline status based on heartbeat messages

**Flow:**
1. Device sends periodic heartbeat to: `smarthome/{apiKey}/{macAddress}/heartbeat`
2. App receives heartbeat and calls `_handleHeartbeat()`
3. Sets device to **online** and resets offline timer
4. If no heartbeat received within 60 seconds → device marked **offline**

```dart
void _handleHeartbeat(String macAddress, String raw) {
  try {
    final timestamp = DateTime.now();
    _lastHeartbeats[macAddress] = timestamp;

    // Cancel existing offline timer
    _heartbeatTimeouts[macAddress]?.cancel();

    // Set device as online
    _updateDeviceStatus(macAddress, true);

    // Start offline detection timer (60 second timeout)
    _heartbeatTimeouts[macAddress] = Timer(offlineTimeout, () {
      _updateDeviceStatus(macAddress, false);
      debugPrint('[MQTT] Device $macAddress marked offline (no heartbeat)');
    });

    debugPrint('[MQTT] Heartbeat from $macAddress at $timestamp');
  } catch (e) {
    debugPrint('[MQTT] Failed to handle heartbeat: $e');
  }
}
```

### C. Update Device Status in Firestore

**Location:** [lib/services/mqtt_service.dart](lib/services/mqtt_service.dart#L430-L450)

**Method:** `MqttService._updateDeviceStatus()`

**Purpose:** Syncs device online status to Firestore

```dart
void _updateDeviceStatus(String macAddress, bool isOnline) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    if (isOnline) {
      // Calls Firestore service to mark online
      await _firestoreService.updateDeviceHeartbeatByMac(uid, macAddress);
    } else {
      // Calls Firestore service to mark offline
      await _firestoreService.markDeviceOfflineByMac(uid, macAddress);
    }
    debugPrint('[MQTT] Device $macAddress status updated: ${isOnline ? 'online' : 'offline'}');
  } catch (e) {
    debugPrint('[MQTT] Failed to update device status: $e');
  }
}
```

---

## 6. Switch State Management

**Location:** [lib/widgets/switch_tile.dart](lib/widgets/switch_tile.dart#L30-L75)

**Class:** `_SwitchTileState`

### State Flow:
1. **Initialization:** Seeds Firestore data into MQTT state map
2. **Subscription:** Listens to real-time MQTT state stream
3. **In-Progress:** Shows spinner while waiting for device echo
4. **Completion:** When device responds or timeout occurs, update UI

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  final mqtt = MqttProvider.of(context);

  // Seed initial state from Firestore (UI shows correct values before MQTT)
  mqtt.seedStates(widget.deviceMac, [widget.switchModel.toMap()]);

  // Subscribe to state stream
  _sub?.cancel();
  _sub = mqtt.stateStream.listen((states) {
    final key = SwitchKey(widget.deviceMac, widget.switchIndex);
    if (states.containsKey(key)) {
      if (mounted) {
        setState(() => _mqttState = states[key]);
        if (_mqttState!.inProgress) {
          _spinController.repeat();  // Show spinner
        } else {
          _spinController.stop();
        }
      }
    }
  });
}
```

### Getters for Current State:
```dart
bool get _isOn => _mqttState?.isOn ?? widget.switchModel.isOn;
double get _value => _mqttState?.value ?? widget.switchModel.value.toDouble();
bool get _inProgress => _mqttState?.inProgress ?? false;
```

---

## ⚠️ Current Gaps (Things NOT Yet Implemented)

### Missing: Online Status Check Before Control
**Issue:** When user attempts to control a switch, the app does **NOT** currently check if the device is online first.

**Current Behavior:**
- User can tap switch even if device is offline
- Command is published to MQTT topic
- Device will never respond → timeout after 10 seconds → UI reverts

**Recommended Implementation:**
Add check in `publishCommand()`:
```dart
void publishCommand({...}) {
  if (!_connected || _client == null) {
    debugPrint('[MQTT] Not connected');
    return;
  }

  // ⭐ ADD THIS CHECK:
  // if (!isDeviceOnline(macAddress)) {
  //   showSnackBar('Device is offline');
  //   return;
  // }

  // ... rest of publish logic
}
```

**Where device online status is stored:**
- In Firestore: `devices/{deviceId}/isOnline` (boolean)
- In Device card UI display: [lib/screens/devices_screen.dart](lib/screens/devices_screen.dart#L325-L350)

---

## Summary of File Locations

| Component | File | Lines |
|-----------|------|-------|
| Room card widget | `lib/screens/home_tab.dart` | 244-330 |
| Compact switch tile | `lib/widgets/switch_tile.dart` | 134-180 |
| Full switch tile | `lib/widgets/switch_tile.dart` | 192-225 |
| Slider tile | `lib/widgets/switch_tile.dart` | 227-280 |
| Device card | `lib/screens/devices_screen.dart` | 283-375 |
| Online status display | `lib/screens/devices_screen.dart` | 325-350 |
| MQTT publish command | `lib/services/mqtt_service.dart` | 238-295 |
| Heartbeat handling | `lib/services/mqtt_service.dart` | 310-340 |
| Status update | `lib/services/mqtt_service.dart` | 430-450 |
| Device model | `lib/models/device_model.dart` | 47, 86, 103 |
| Switch state mgmt | `lib/widgets/switch_tile.dart` | 30-75 |

---

## MQTT Topic Structure
```
Control (App → Device):
  smarthome/{apiKey}/{macAddress}/control
  Payload: { "switchIndex": 0, "isOn": true, "value": 0, "type": "toggle" }

Status (Device → App):
  smarthome/{apiKey}/{macAddress}/status
  Payload: { "switchIndex": 0, "isOn": true, "value": 0, "type": "toggle" }

Heartbeat (Device → App):
  smarthome/{apiKey}/{macAddress}/heartbeat
  Payload: timestamp
```
