# SmartHome App - MQTT & Firestore Architecture

## MQTT Topic Structure

All MQTT communication uses the following hierarchical topic structure:

```
smarthome/<API_KEY>/<MAC_ID>/<MESSAGE_TYPE>
```

### Topics

| Direction | Topic | Example |
|-----------|-------|---------|
| App → Device (Commands) | `smarthome/<API>/<MAC>/control` | `smarthome/smarthome_default/AA:BB:CC:DD:EE:01/control` |
| Device → App (Status) | `smarthome/<API>/<MAC>/status` | `smarthome/smarthome_default/AA:BB:CC:DD:EE:01/status` |
| Device → App (Heartbeat) | `smarthome/<API>/<MAC>/heartbeat` | `smarthome/smarthome_default/AA:BB:CC:DD:EE:01/heartbeat` |

### Wildcard Subscriptions

The app subscribes to these wildcards:
- `smarthome/<API>/+/status` - Receives status from ALL devices under this API
- `smarthome/<API>/+/heartbeat` - Receives heartbeats from ALL devices under this API

**Why `+`?** The `+` is an MQTT wildcard that matches exactly one level. So it will match any MAC ID.

## Firestore Structure

Devices are now organized under each user's collection for proper security:

```
users/
  {uid}/
    devices/
      {deviceId}/
        deviceName: "Living Room Switch"
        macId: "AA:BB:CC:DD:EE:01"
        type: "1-switch"
        isOnline: true
        lastHeartbeat: <timestamp>
        linkedRoom: "roomId"
        linkedHome: "homeId"
        ownedBy: "{uid}"
        switches: [...]
```

### Key Changes from Previous Structure

**BEFORE:** Devices were stored in a global top-level collection:
```
devices/{deviceId}
```
❌ Issues:
- Kept searching by `ownedBy` field (inefficient)
- Permission errors when trying to write
- Devices weren't truly isolated by user

**NOW:** Devices are organized per-user:
```
users/{uid}/devices/{deviceId}
```
✅ Benefits:
- Natural security isolation per user
- Firestore security rules can be simple
- Efficient querying (no need for where clause)
- Better permission control

## How It Works

### Adding a Device

1. **User enters device details:**
   - Device Name: "Living Room Light"
   - MAC ID: `AA:BB:CC:DD:EE:01` (from hardware)
   - Type: "1-switch"

2. **App saves to Firestore:**
   ```
   users/{current_uid}/devices/{newId}
   {
     macId: "AA:BB:CC:DD:EE:01",
     deviceName: "Living Room Light",
     ...
   }
   ```

3. **Device connects via MQTT:**
   - Device publishes heartbeat to: `smarthome/smarthome_default/AA:BB:CC:DD:EE:01/heartbeat`
   - App receives it and updates Firestore: `isOnline: true`

### Controlling a Device

1. **User taps switch in app**
2. **App publishes command:**
   ```
   Topic: smarthome/smarthome_default/AA:BB:CC:DD:EE:01/control
   Payload: { switchIndex: 0, isOn: true, type: "toggle" }
   ```
3. **Device receives and executes**
4. **Device sends status confirmation:**
   ```
   Topic: smarthome/smarthome_default/AA:BB:CC:DD:EE:01/status
   Payload: { switchIndex: 0, isOn: true }
   ```
5. **App receives and updates UI immediately**

### Heartbeat & Online Status

- **Heartbeat interval:** Device sends every 30 seconds
- **Topic:** `smarthome/smarthome_default/{MAC}/heartbeat`
- **Timeout:** If no heartbeat for 60 seconds, device marked offline
- **Firestore updated:** `isOnline` field toggle + `lastHeartbeat` timestamp

## Scenes with MQTT

When executing a scene, all actions use MAC IDs for MQTT:

```dart
SceneAction {
  macId: "AA:BB:CC:DD:EE:01",  // ← Uses MAC ID (not deviceId)
  switchIndex: 0,
  targetState: true
}
```

This publishes MQTT commands for each action using the MAC-based topic.

## Simulator Testing

### Requirements

**App Settings:**
- API Key: `smarthome_default` (can be changed)
- Broker: `test.mosquitto.org`
- Port: `1883`

**Simulator Settings:**
- API Key: **MUST match app** - `smarthome_default`
- Device MAC ID: **MUST match app** - e.g., `AA:BB:CC:DD:EE:01`
- Broker: Same as app

### Testing Flow

1. **App:** Add device with MAC `AA:BB:CC:DD:EE:01`
2. **Simulator:** Add device with MAC `AA:BB:CC:DD:EE:01`
3. **Both connect** to same MQTT broker with same API key
4. **They communicate** via matching topics automatically

## Security Considerations

1. **API Key in Topic Path:** Provides basic topic-level security
2. **Firestore Security Rules:** Must allow users to read/write only their own devices
3. **MAC ID as Identifier:** Prevents unauthorized device impersonation
4. **User Isolation:** Devices live under user collection - cannot access other users' devices

### Recommended Firebase Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own devices
    match /users/{uid}/devices/{deviceId=**} {
      allow read, write: if request.auth.uid == uid;
    }
  }
}
```

## Troubleshooting

### App shows "Device missing MAC ID"
- The device was added before MAC ID field was implemented
- Delete and re-add the device with a MAC ID

### Permission errors in console
- User not logged in when MQTT message arrives
- Device doesn't exist in user's Firestore collection yet
- Check Firestore security rules

### App receives heartbeats but doesn't update online status
- MAC ID in simulator doesn't match device in Firestore
- API key doesn't match between app and simulator
- Device may not exist yet - add it first in app before simulator connects

### Can't send commands to device
- Device MAC ID must match exactly (case-sensitive)
- API key must match
- Device must have received at least one heartbeat (must be online)
