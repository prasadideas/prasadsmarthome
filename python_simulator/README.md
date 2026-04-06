# SmartHome Device Simulator

A Python GUI application that simulates IoT devices for testing the Flutter SmartHome app. It connects to an MQTT broker and emulates various smart home devices with realistic behavior.

## Features

- **MQTT Integration**: Connects to MQTT brokers (tested with test.mosquitto.org)
- **Device Simulation**: Supports multiple device types:
  - Switches (1, 2, 4, 6, 8 switches)
  - Fan controllers with speed control
  - Dimmers with brightness control
  - Curtain controllers
  - Scene buttons
- **Heartbeat System**: Sends periodic heartbeats to indicate device online status
- **Real-time Control**: Responds to control messages and sends status updates
- **Device Management**: Add, remove, and configure virtual devices
- **Online/Offline Simulation**: Toggle device online status
- **Activity Logging**: Real-time log of all MQTT communications

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Run the simulator:
```bash
python device_simulator.py
```

## Usage

1. **Launch the Application**: Run `python device_simulator.py`
2. **Check MQTT Connection**: The status should show "Connected" in green
3. **Add Devices**: Click "Add Device" to create virtual devices with different MAC addresses
4. **Configure Devices**: Set device type, name, and online status
5. **Monitor Activity**: Watch the log for MQTT messages and device interactions
6. **Test with Flutter App**: Use the same MQTT broker settings in your Flutter app

## Device Configuration

Devices are stored in `devices.json` with the following structure:

```json
{
  "AA:BB:CC:DD:EE:01": {
    "name": "Living Room Switch",
    "type": "1-switch",
    "online": true,
    "switches": [
      {"isOn": false, "value": 0}
    ]
  }
}
```

## MQTT Topics

- **Control**: `smarthome/{api_key}/{mac_address}/control`
- **Status**: `smarthome/{api_key}/{mac_address}/status`
- **Heartbeat**: `smarthome/{api_key}/{mac_address}/heartbeat`

## Default Settings

- **Broker**: test.mosquitto.org:1883
- **API Key**: smarthome_default
- **Heartbeat Interval**: 30 seconds

## Requirements

- Python 3.6+
- tkinter (usually included with Python)
- paho-mqtt library

## Troubleshooting

1. **MQTT Connection Issues**: Check firewall settings and broker availability
2. **No Messages**: Ensure API key matches between simulator and Flutter app
3. **Device Not Responding**: Verify MAC address format and device online status

## Integration with Flutter App

Make sure the Flutter app uses the same MQTT broker settings:
- Host: test.mosquitto.org
- Port: 1883
- API Key: smarthome_default

The simulator will automatically respond to control messages and send heartbeats for online devices.