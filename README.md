# Prasad Smart Home

Flutter smart-home app.

Firestore stores structure.
MQTT drives live control/state.

## Current Model

Firestore hierarchy:

- `users/{uid}`
- `users/{uid}/homes/{homeId}`
- `users/{uid}/homes/{homeId}/rooms/{roomId}`
- `users/{uid}/devices/{deviceId}`

Device fields:

- `deviceName`
- `type`
- `macId`
- `linkedHome`
- `linkedRoom`
- `ownedBy`
- `isOnline`
- `lastHeartbeat`
- `switches[]`

Switch fields:

- `switchId`
- `label`
- `isOn`
- `type`
- `icon`
- `value`

## Runtime Rules

Firestore is structure source.
MQTT is live-state source.
Do not trust Firestore switch status for live UI.
App keeps temporary switch cache in `MqttService`.
Cache key is `(macId, switchIndex)`.

MQTT topics:

```text
smarthome/{apiKey}/{macId}/control
smarthome/{apiKey}/{macId}/status
smarthome/{apiKey}/{macId}/heartbeat
```

## Important Files

- `lib/services/mqtt_service.dart`: MQTT client, state cache, heartbeat handling, online status
- `lib/services/firestore_service.dart`: Firestore CRUD for homes, rooms, devices, scenes
- `lib/widgets/switch_tile.dart`: live switch UI backed by MQTT cache
- `lib/screens/home_tab.dart`: active-home room cards and room summaries
- `lib/screens/rooms_screen.dart`: room grid and per-room dots
- `lib/screens/devices_screen.dart`: device cards and switch tiles
- `python_simulator/device_simulator.py`: desktop MQTT simulator
- `MQTT_AND_FIRESTORE_ARCHITECTURE.md`: path/topic notes
- `SWITCH_CONTROL_ARCHITECTURE.md`: UI/control notes

## Startup Flow

1. `main.dart` creates singleton `MqttService`.
2. `HomeTab` loads saved broker settings.
3. `HomeTab` auto-connects MQTT.
4. `MqttService` subscribes:
	- `smarthome/{apiKey}/+/status`
	- `smarthome/{apiKey}/+/heartbeat`
5. Switch widgets seed cache from stored switch definitions.
6. MQTT status packets replace seeded values.

## Live-State Notes

- Heartbeat updates local online state immediately.
- Device online chips rebuild from `MqttProvider` notifier.
- Switch tiles restore cached state when revisiting screens.
- Room-card dots prefer MQTT cache, then fallback to seeded value.
- Room-wide OFF actions publish MQTT commands instead of mutating Firestore switch state.

## Simulator

Path: `python_simulator/`

Defaults:

- Broker: `test.mosquitto.org`
- Port: `1883`
- API key: `smarthome_default`

Sample MACs in `python_simulator/devices.json`:

- `AA:BB:CC:DD:EE:01`
- `AA:BB:CC:DD:EE:02`
- `AA:BB:CC:DD:EE:03`

Run simulator:

```bash
cd python_simulator
pip install -r requirements.txt
python device_simulator.py
```

## Verified In This Session

- Heartbeat now triggers local online-status rebuilds.
- Revisiting device screen restores cached switch states.
- Room-card dots use MQTT/local cache instead of false fallback.
- Home-tab room summaries use MQTT/local cache instead of Firestore-only values.
- Room-card OFF actions publish MQTT commands.

## Remaining Risks

- `FirestoreService.setRoomAllSwitchesOff()` still exists as legacy helper.
- `lib/screens/switch_tile.dart` looks like unused duplicate of widget tile.
- MAC IDs are case-sensitive in MQTT topics.

## Next AI Session

Check these first:

1. `lib/services/mqtt_service.dart`
2. `lib/widgets/switch_tile.dart`
3. `lib/screens/home_tab.dart`
4. `lib/screens/rooms_screen.dart`
5. `python_simulator/device_simulator.py`

Useful commands:

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Live-state debug order:

1. Confirm MQTT connected.
2. Confirm API key matches simulator.
3. Confirm `macId` matches topic MAC exactly.
4. Watch heartbeat before testing controls.
5. Trust MQTT cache over Firestore `switches[].isOn`.
