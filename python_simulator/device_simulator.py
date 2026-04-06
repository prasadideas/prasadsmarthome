#!/usr/bin/env python3
"""
SmartHome Device Simulator
Simulates IoT devices for testing the Flutter SmartHome app.
Supports MQTT communication with heartbeat and device control simulation.
"""

import json
import time
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import paho.mqtt.client as mqtt
from datetime import datetime
import configparser
import os

class DeviceSimulator:
    def __init__(self, root):
        self.root = root
        self.root.title("SmartHome Device Simulator")
        self.root.geometry("1200x700")

        # MQTT Configuration
        self.broker_host = "test.mosquitto.org"
        self.broker_port = 1883
        self.api_key = "smarthome_default"
        self.client = None
        self.connected = False

        # Heartbeat Configuration
        self.heartbeat_interval = 30  # seconds

        # Device type definitions - all supported device templates
        self.device_types = {
            # Basic switches
            "sw_1": {"name": "1-switch board", "switches": [{"type": "toggle"}]},
            "sw_2": {"name": "2-switch board", "switches": [{"type": "toggle"}, {"type": "toggle"}]},
            "sw_4": {"name": "4-switch board", "switches": [{"type": "toggle"}, {"type": "toggle"}, {"type": "toggle"}, {"type": "toggle"}]},
            "sw_6": {"name": "6-switch board", "switches": [{"type": "toggle"}]*6},
            "sw_8": {"name": "8-switch panel", "switches": [{"type": "toggle"}]*8},
            "sw_12": {"name": "12-switch panel", "switches": [{"type": "toggle"}]*12},
            "sw_16": {"name": "16-switch panel", "switches": [{"type": "toggle"}]*16},
            # Fan controllers (toggle switches + fan speed)
            "sw_2_fan": {"name": "2 switches + fan", "switches": [{"type": "toggle"}, {"type": "toggle"}, {"type": "fan"}]},
            "sw_4_fan": {"name": "4 switches + fan", "switches": [{"type": "toggle"}]*4 + [{"type": "fan"}]},
            # Dimmer controllers (toggle switches + dimmer)
            "sw_2_dim": {"name": "2 switches + dimmer", "switches": [{"type": "toggle"}, {"type": "toggle"}, {"type": "dimmer"}]},
            "sw_4_dim": {"name": "4 switches + dimmer", "switches": [{"type": "toggle"}]*4 + [{"type": "dimmer"}]},
            # Curtain controller
            "curtain": {"name": "Curtain controller", "switches": [{"type": "curtain"}, {"type": "curtain"}, {"type": "curtain"}]},
            # Scene panel
            "scene_8": {"name": "8-button scene panel", "switches": [{"type": "scene"}]*8},
        }

        # Devices storage
        self.devices = {}
        self.current_device_mac = None
        self.updating_ui = False  # Flag to prevent recursive updates
        
        # Track active heartbeat threads per device
        self.heartbeat_threads = {}  # MAC -> thread object
        self.stop_heartbeat_flags = {}  # MAC -> stop flag

        # Load devices first
        self.load_devices()

        # UI Setup
        self.setup_ui()

        # Start MQTT connection
        self.connect_mqtt()

    def setup_ui(self):
        # Main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # MQTT Status
        status_frame = ttk.LabelFrame(main_frame, text="MQTT Status & Settings", padding="5")
        status_frame.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))

        self.status_label = ttk.Label(status_frame, text="Disconnected", foreground="red")
        self.status_label.grid(row=0, column=0, sticky=tk.W)

        ttk.Button(status_frame, text="Reconnect", command=self.connect_mqtt).grid(row=0, column=1, padx=(10, 0))

        # Heartbeat interval control
        ttk.Label(status_frame, text="Heartbeat Interval (sec):").grid(row=0, column=2, padx=(20, 5))
        self.heartbeat_interval_var = tk.IntVar(value=self.heartbeat_interval)
        heartbeat_spinbox = ttk.Spinbox(status_frame, from_=1, to=300, textvariable=self.heartbeat_interval_var, 
                                        width=5, command=self.on_heartbeat_interval_changed)
        heartbeat_spinbox.grid(row=0, column=3, padx=(0, 10))

        # Devices frame
        devices_frame = ttk.LabelFrame(main_frame, text="Devices", padding="5")
        devices_frame.grid(row=1, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(0, 10))

        # Device list
        self.device_tree = ttk.Treeview(devices_frame, columns=("Type", "Online", "MAC"), height=8)
        self.device_tree.heading("#0", text="Device Name")
        self.device_tree.heading("Type", text="Type")
        self.device_tree.heading("Online", text="Online")
        self.device_tree.heading("MAC", text="MAC Address")

        self.device_tree.column("#0", width=150)
        self.device_tree.column("Type", width=100)
        self.device_tree.column("Online", width=80)
        self.device_tree.column("MAC", width=120)

        scrollbar = ttk.Scrollbar(devices_frame, orient=tk.VERTICAL, command=self.device_tree.yview)
        self.device_tree.configure(yscrollcommand=scrollbar.set)

        self.device_tree.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        scrollbar.grid(row=0, column=1, sticky=(tk.N, tk.S))

        # Device controls
        controls_frame = ttk.Frame(devices_frame)
        controls_frame.grid(row=1, column=0, columnspan=2, pady=(10, 0))

        ttk.Button(controls_frame, text="Add Device", command=self.add_device_dialog).grid(row=0, column=0, padx=(0, 5))
        ttk.Button(controls_frame, text="Remove Device", command=self.remove_device).grid(row=0, column=1, padx=(0, 5))
        ttk.Button(controls_frame, text="Toggle Online", command=self.toggle_device_online).grid(row=0, column=2, padx=(0, 5))

        # Device details frame with tabs
        details_frame = ttk.LabelFrame(main_frame, text="Device Controls", padding="5")
        details_frame.grid(row=1, column=1, sticky=(tk.W, tk.E, tk.N, tk.S), padx=(10, 0))

        # Create notebook (tabs)
        self.details_notebook = ttk.Notebook(details_frame)
        self.details_notebook.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # Info tab
        info_tab = ttk.Frame(self.details_notebook)
        self.details_notebook.add(info_tab, text="Info")
        self.details_text = scrolledtext.ScrolledText(info_tab, width=40, height=12)
        self.details_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # Switches tab
        switches_tab = ttk.Frame(self.details_notebook)
        self.details_notebook.add(switches_tab, text="Switches")
        
        switches_scroll = ttk.Scrollbar(switches_tab, orient=tk.VERTICAL)
        self.switches_canvas = tk.Canvas(switches_tab, yscrollcommand=switches_scroll.set, bg="white")
        self.switches_frame = ttk.Frame(self.switches_canvas)
        
        self.switches_frame.bind("<Configure>", lambda e: self.switches_canvas.configure(scrollregion=self.switches_canvas.bbox("all")))
        
        self.switches_canvas.create_window(0, 0, window=self.switches_frame, anchor=tk.NW)
        switches_scroll.config(command=self.switches_canvas.yview)
        
        self.switches_canvas.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        switches_scroll.grid(row=0, column=1, sticky=(tk.N, tk.S))

        # Sensors tab
        sensors_tab = ttk.Frame(self.details_notebook)
        self.details_notebook.add(sensors_tab, text="Sensors")
        
        sensors_scroll = ttk.Scrollbar(sensors_tab, orient=tk.VERTICAL)
        self.sensors_canvas = tk.Canvas(sensors_tab, yscrollcommand=sensors_scroll.set, bg="white")
        self.sensors_frame = ttk.Frame(self.sensors_canvas)
        
        self.sensors_frame.bind("<Configure>", lambda e: self.sensors_canvas.configure(scrollregion=self.sensors_canvas.bbox("all")))
        
        self.sensors_canvas.create_window(0, 0, window=self.sensors_frame, anchor=tk.NW)
        sensors_scroll.config(command=self.sensors_canvas.yview)
        
        self.sensors_canvas.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        sensors_scroll.grid(row=0, column=1, sticky=(tk.N, tk.S))

        # Log frame
        log_frame = ttk.LabelFrame(main_frame, text="Activity Log", padding="5")
        log_frame.grid(row=2, column=0, columnspan=2, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(10, 0))

        self.log_text = scrolledtext.ScrolledText(log_frame, width=80, height=8)
        self.log_text.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))

        # Configure grid weights
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        main_frame.columnconfigure(1, weight=1)
        main_frame.rowconfigure(1, weight=1)
        devices_frame.columnconfigure(0, weight=1)
        devices_frame.rowconfigure(0, weight=1)
        details_frame.columnconfigure(0, weight=1)
        details_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)

        # Bind events
        self.device_tree.bind('<<TreeviewSelect>>', self.on_device_select)

        # Initialize device list
        self.refresh_device_list()

    def test_connection(self):
        """Test MQTT connection manually"""
        self.log_message("Testing MQTT connection...")
        self.status_label.config(text="Testing...", foreground="orange")

        if self.client:
            self.client.disconnect()

        test_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        connection_successful = False

        def on_test_connect(client, userdata, flags, rc, properties=None):
            nonlocal connection_successful
            if rc == 0:
                connection_successful = True
                self.root.after(0, lambda: self.status_label.config(text="Test Passed", foreground="green"))
                self.log_message("✓ MQTT connection test successful")
            else:
                self.root.after(0, lambda: self.status_label.config(text="Test Failed", foreground="red"))
                self.log_message(f"✗ MQTT connection failed with code: {rc}")

        def on_test_disconnect(client, userdata, rc):
            if not connection_successful:
                self.root.after(0, lambda: self.status_label.config(text="Test Failed", foreground="red"))
                self.log_message("✗ MQTT connection test failed - disconnected")

        test_client.on_connect = on_test_connect
        test_client.on_disconnect = on_test_disconnect

        try:
            test_client.connect(self.broker_host, self.broker_port, 10)
            test_client.loop_start()
            time.sleep(3)
            test_client.disconnect()
            test_client.loop_stop()

        except Exception as e:
            self.log_message(f"✗ MQTT connection test error: {e}")
            self.status_label.config(text="Test Failed", foreground="red")

        # Reset to current status after test
        self.root.after(2000, self._reset_status_label)

    def _reset_status_label(self):
        """Reset status label to current connection state"""
        if self.connected:
            self.status_label.config(text="Connected", foreground="green")
        else:
            self.status_label.config(text="Disconnected", foreground="red")

    def log_message(self, message):
        """Log a message to the UI and console"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {message}")  # Always print to console

        # Only update UI if it's initialized
        if hasattr(self, 'log_text') and self.log_text:
            try:
                self.log_text.insert(tk.END, f"[{timestamp}] {message}\n")
                self.log_text.see(tk.END)
            except:
                pass  # UI might not be ready yet

    def connect_mqtt(self):
        if self.client:
            self.client.disconnect()

        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        self.client.on_connect = self.on_mqtt_connect
        self.client.on_disconnect = self.on_mqtt_disconnect
        self.client.on_message = self.on_mqtt_message

        # Set connection timeout
        self.client.connect_timeout = 10  # 10 seconds

        try:
            self.log_message(f"Attempting to connect to MQTT broker: {self.broker_host}:{self.broker_port}")
            self.status_label.config(text="Connecting...", foreground="orange")
            self.client.connect(self.broker_host, self.broker_port, 60)
            self.client.loop_start()
        except Exception as e:
            self.log_message(f"✗ MQTT connection failed: {e}")
            self.status_label.config(text="Connection Failed", foreground="red")

    def on_mqtt_connect(self, client, userdata, flags, rc, properties=None):
        connection_messages = {
            0: "Connection successful",
            1: "Connection refused - incorrect protocol version",
            2: "Connection refused - invalid client identifier",
            3: "Connection refused - server unavailable",
            4: "Connection refused - bad username or password",
            5: "Connection refused - not authorised"
        }

        if rc == 0:
            self.connected = True
            self.root.after(0, lambda: self.status_label.config(text="Connected", foreground="green"))
            self.log_message("✓ MQTT connected successfully")

            # Subscribe to control topics for all devices
            for mac, device in self.devices.items():
                control_topic = f"smarthome/{self.api_key}/{mac}/control"
                status_topic = f"smarthome/{self.api_key}/{mac}/status"
                self.client.subscribe(control_topic)
                self.client.subscribe(status_topic)
                self.log_message(f"Subscribed to topics for device {mac}")

            # Start heartbeat threads for online devices
            for mac, device in self.devices.items():
                if device.get('online', False):
                    self.stop_heartbeat_flags[mac] = False
                    thread = threading.Thread(target=self.heartbeat_loop, args=(mac,), daemon=True)
                    self.heartbeat_threads[mac] = thread
                    thread.start()

        else:
            self.connected = False
            error_msg = connection_messages.get(rc, f"Connection failed with code: {rc}")
            self.root.after(0, lambda: self.status_label.config(text="Connection Failed", foreground="red"))
            self.log_message(f"✗ MQTT {error_msg}")

    def on_mqtt_disconnect(self, client, userdata, rc):
        self.connected = False
        self.root.after(0, lambda: self.status_label.config(text="Disconnected", foreground="red"))
        self.log_message("MQTT disconnected")

    def on_heartbeat_interval_changed(self):
        """Handle changes to heartbeat interval"""
        self.heartbeat_interval = self.heartbeat_interval_var.get()
        self.log_message(f"Heartbeat interval changed to {self.heartbeat_interval} seconds")
        # Save to config
        self.save_config()

    def on_mqtt_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            topic_parts = msg.topic.split('/')
            mac_address = topic_parts[2]
            message_type = topic_parts[3]

            if message_type == 'control' and mac_address in self.devices:
                self.handle_control_message(mac_address, payload)
            elif message_type == 'status':
                self.log_message(f"Status from {mac_address}: {payload}")

        except Exception as e:
            self.log_message(f"Error processing MQTT message: {e}")

    def handle_control_message(self, mac_address, payload):
        device = self.devices[mac_address]
        switch_index = payload.get('switchIndex', 0)
        is_on = payload.get('isOn', False)
        value = payload.get('value', 0)
        switch_type = payload.get('type', 'toggle')

        # Update device state
        if 'switches' not in device:
            device['switches'] = []

        while len(device['switches']) <= switch_index:
            device['switches'].append({'isOn': False, 'value': 0})

        device['switches'][switch_index]['isOn'] = is_on
        device['switches'][switch_index]['value'] = value

        # Send status response
        status_topic = f"smarthome/{self.api_key}/{mac_address}/status"
        status_payload = {
            'switchIndex': switch_index,
            'isOn': is_on,
            'value': value,
            'type': switch_type
        }

        self.client.publish(status_topic, json.dumps(status_payload))
        self.log_message(f"Device {mac_address} switch {switch_index} set to {'ON' if is_on else 'OFF'}")
        self.save_devices()
        self.refresh_device_list()

    def heartbeat_loop(self, mac_address):
        # Initialize stop flag if needed
        if mac_address not in self.stop_heartbeat_flags:
            self.stop_heartbeat_flags[mac_address] = False
        
        while not self.stop_heartbeat_flags.get(mac_address, False) and \
              self.devices.get(mac_address, {}).get('online', False) and \
              self.connected:
            heartbeat_topic = f"smarthome/{self.api_key}/{mac_address}/heartbeat"
            heartbeat_payload = {
                'timestamp': datetime.now().isoformat(),
                'device_type': self.devices[mac_address].get('type', 'unknown')
            }

            self.client.publish(heartbeat_topic, json.dumps(heartbeat_payload))
            self.log_message(f"Heartbeat sent for {mac_address}")
            time.sleep(self.heartbeat_interval)  # Send heartbeat at configured interval
        
        # Cleanup when heartbeat stops
        self.log_message(f"Heartbeat stopped for {mac_address}")

    def load_devices(self):
        config_file = 'devices.json'
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    data = json.load(f)
                
                # Load config if present
                if isinstance(data, dict) and '_config' in data:
                    config = data['_config']
                    self.heartbeat_interval = config.get('heartbeat_interval', 30)
                    self.devices = {k: v for k, v in data.items() if k != '_config'}
                else:
                    # Old format - all items are devices
                    self.devices = data
                
                # Ensure all devices have proper structure
                for mac, device in self.devices.items():
                    # Add sensors field if missing
                    if 'sensors' not in device:
                        device['sensors'] = []
                    
                    # Migrate old switch format to new format with types
                    if 'switches' in device:
                        switches = device['switches']
                        for switch in switches:
                            if 'type' not in switch:
                                # Infer type from device type or default to toggle
                                device_type = device.get('type', 'sw_1')
                                if 'fan' in device_type:
                                    switch['type'] = 'fan'
                                elif 'dim' in device_type:
                                    switch['type'] = 'dimmer'
                                elif 'curtain' in device_type:
                                    switch['type'] = 'curtain'
                                elif 'scene' in device_type:
                                    switch['type'] = 'scene'
                                else:
                                    switch['type'] = 'toggle'
                
                self.save_devices()
                self.log_message(f"Loaded {len(self.devices)} devices from {config_file}")
            except Exception as e:
                self.log_message(f"Error loading devices: {e}")
                self.devices = {}
        else:
            # Create default devices
            self.create_default_devices()

    def create_default_devices(self):
        """Create default devices with all supported types as examples"""
        default_devices = {
            # Basic switches
            "AA:BB:CC:DD:EE:01": {
                "name": "Living Room Switch",
                "type": "sw_1",
                "online": True,
                "switches": [{"isOn": False, "value": 0, "type": "toggle"}],
                "sensors": []
            },
            "AA:BB:CC:DD:EE:02": {
                "name": "Bedroom Switches",
                "type": "sw_2",
                "online": True,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"}
                ],
                "sensors": []
            },
            "AA:BB:CC:DD:EE:03": {
                "name": "Kitchen Panel",
                "type": "sw_4",
                "online": False,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"}
                ],
                "sensors": []
            },
            # Fan controller
            "AA:BB:CC:DD:EE:04": {
                "name": "Master Bedroom Fan",
                "type": "sw_2_fan",
                "online": True,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 2, "type": "fan"}
                ],
                "sensors": [
                    {"type": "temperature", "value": 22.5, "unit": "°C"},
                    {"type": "humidity", "value": 45, "unit": "%"}
                ]
            },
            # Dimmer
            "AA:BB:CC:DD:EE:05": {
                "name": "Living Room Dimmer",
                "type": "sw_2_dim",
                "online": True,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 50, "type": "dimmer"}
                ],
                "sensors": [
                    {"type": "light-level", "value": 100, "unit": "lux"},
                    {"type": "motion", "value": 0, "unit": "detected"}
                ]
            },
            # Curtain controller
            "AA:BB:CC:DD:EE:06": {
                "name": "Bedroom Curtains",
                "type": "curtain",
                "online": True,
                "switches": [
                    {"isOn": False, "value": 0, "type": "curtain"},
                    {"isOn": False, "value": 0, "type": "curtain"},
                    {"isOn": False, "value": 0, "type": "curtain"}
                ],
                "sensors": []
            },
            # Scene panel
            "AA:BB:CC:DD:EE:07": {
                "name": "Scene Controller",
                "type": "scene_8",
                "online": True,
                "switches": [{"isOn": False, "value": 0, "type": "scene"}]*8,
                "sensors": []
            },
            # 6-switch panel
            "AA:BB:CC:DD:EE:08": {
                "name": "Study Room Panel",
                "type": "sw_6",
                "online": True,
                "switches": [{"isOn": False, "value": 0, "type": "toggle"}]*6,
                "sensors": []
            },
            # 4 switches + fan
            "AA:BB:CC:DD:EE:09": {
                "name": "Hall with Ceiling Fan",
                "type": "sw_4_fan",
                "online": False,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "fan"}
                ],
                "sensors": []
            },
            # 4 switches + dimmer
            "AA:BB:CC:DD:EE:0A": {
                "name": "Garage with Dimmers",
                "type": "sw_4_dim",
                "online": True,
                "switches": [
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 0, "type": "toggle"},
                    {"isOn": False, "value": 75, "type": "dimmer"}
                ],
                "sensors": []
            },
        }
        self.devices = default_devices
        self.save_devices()
        self.log_message("Created default devices with all supported types")

    def save_devices(self):
        try:
            data = {
                '_config': {
                    'heartbeat_interval': self.heartbeat_interval
                }
            }
            data.update(self.devices)
            with open('devices.json', 'w') as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            self.log_message(f"Error saving devices: {e}")

    def save_config(self):
        """Save configuration to devices.json"""
        self.save_devices()

    def refresh_device_list(self):
        # Clear existing items
        for item in self.device_tree.get_children():
            self.device_tree.delete(item)

        # Add devices
        for mac, device in self.devices.items():
            online_status = "Yes" if device.get('online', False) else "No"
            self.device_tree.insert("", tk.END, text=device.get('name', 'Unknown'),
                                  values=(device.get('type', 'unknown'), online_status, mac))

    def add_device_dialog(self):
        dialog = tk.Toplevel(self.root)
        dialog.title("Add Device")
        dialog.geometry("500x350")

        ttk.Label(dialog, text="Device Name:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        name_entry = ttk.Entry(dialog, width=35)
        name_entry.grid(row=0, column=1, padx=5, pady=5)

        ttk.Label(dialog, text="MAC Address:").grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        mac_entry = ttk.Entry(dialog, width=35)
        mac_entry.grid(row=1, column=1, padx=5, pady=5)

        ttk.Label(dialog, text="Device Type:").grid(row=2, column=0, padx=5, pady=5, sticky=tk.NW)
        
        # Create device type list with categories
        type_values = [
            "-- Basic Switches --",
            "sw_1 - 1-switch board",
            "sw_2 - 2-switch board",
            "sw_4 - 4-switch board",
            "sw_6 - 6-switch board",
            "sw_8 - 8-switch panel",
            "sw_12 - 12-switch panel",
            "sw_16 - 16-switch panel",
            "-- Fan Controllers --",
            "sw_2_fan - 2 switches + fan",
            "sw_4_fan - 4 switches + fan",
            "-- Dimmer Controllers --",
            "sw_2_dim - 2 switches + dimmer",
            "sw_4_dim - 4 switches + dimmer",
            "-- Curtain Controller --",
            "curtain - Curtain controller",
            "-- Scene Panel --",
            "scene_8 - 8-button scene panel",
        ]
        
        type_combo = ttk.Combobox(dialog, values=type_values, state="readonly", width=40)
        type_combo.current(1)  # Default to 1-switch
        type_combo.grid(row=2, column=1, padx=5, pady=5)

        ttk.Label(dialog, text="Online:").grid(row=3, column=0, padx=5, pady=5, sticky=tk.W)
        online_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(dialog, variable=online_var).grid(row=3, column=1, padx=5, pady=5, sticky=tk.W)

        def add_device():
            name = name_entry.get().strip()
            mac = mac_entry.get().strip().upper()
            selected_type = type_combo.get().strip()
            online = online_var.get()

            if not name or not mac:
                messagebox.showerror("Error", "Please fill in all fields")
                return

            # Extract device type ID from combobox selection
            if " - " in selected_type:
                device_type_id = selected_type.split(" - ")[0]
            else:
                messagebox.showerror("Error", "Please select a valid device type")
                return

            if device_type_id not in self.device_types:
                messagebox.showerror("Error", "Invalid device type selected")
                return

            # Validate MAC format (simple check)
            if len(mac.replace(':', '')) != 12:
                messagebox.showerror("Error", "Invalid MAC address format")
                return

            if mac in self.devices:
                messagebox.showerror("Error", "Device with this MAC already exists")
                return

            # Create device based on type
            device = {
                "name": name,
                "type": device_type_id,
                "online": online,
                "switches": [],
                "sensors": []
            }

            # Initialize switches based on device template
            switch_template = self.device_types[device_type_id]["switches"]
            for switch_config in switch_template:
                switch_type = switch_config["type"]
                if switch_type == "toggle":
                    device["switches"].append({"isOn": False, "value": 0, "type": "toggle"})
                elif switch_type == "fan":
                    device["switches"].append({"isOn": False, "value": 0, "type": "fan"})
                elif switch_type == "dimmer":
                    device["switches"].append({"isOn": False, "value": 0, "type": "dimmer"})
                elif switch_type == "curtain":
                    device["switches"].append({"isOn": False, "value": 0, "type": "curtain"})
                elif switch_type == "scene":
                    device["switches"].append({"isOn": False, "value": 0, "type": "scene"})

            self.devices[mac] = device
            self.save_devices()
            self.refresh_device_list()

            # Subscribe to new device topics if connected
            if self.connected:
                control_topic = f"smarthome/{self.api_key}/{mac}/control"
                status_topic = f"smarthome/{self.api_key}/{mac}/status"
                self.client.subscribe(control_topic)
                self.client.subscribe(status_topic)

                if online:
                    threading.Thread(target=self.heartbeat_loop, args=(mac,), daemon=True).start()

            self.log_message(f"Added device: {name} ({mac}) - Type: {device_type_id}")
            dialog.destroy()

        ttk.Button(dialog, text="Add Device", command=add_device).grid(row=4, column=0, columnspan=2, pady=15)

    def remove_device(self):
        selected = self.device_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "Please select a device to remove")
            return

        item = self.device_tree.item(selected[0])
        mac = item['values'][2]

        if messagebox.askyesno("Confirm", f"Remove device {item['text']}?"):
            if mac in self.devices:
                del self.devices[mac]
                self.save_devices()
                self.refresh_device_list()
                self.log_message(f"Removed device: {mac}")

    def toggle_device_online(self):
        selected = self.device_tree.selection()
        if not selected:
            messagebox.showwarning("Warning", "Please select a device")
            return

        item = self.device_tree.item(selected[0])
        mac = item['values'][2]

        if mac in self.devices:
            device = self.devices[mac]
            device['online'] = not device.get('online', False)

            if device['online'] and self.connected:
                # Start heartbeat
                self.stop_heartbeat_flags[mac] = False
                thread = threading.Thread(target=self.heartbeat_loop, args=(mac,), daemon=True)
                self.heartbeat_threads[mac] = thread
                thread.start()
                self.log_message(f"Started heartbeat for {mac}")
            else:
                # Stop heartbeat immediately
                self.stop_heartbeat_flags[mac] = True
                self.log_message(f"Stopped heartbeat for {mac}")

            self.save_devices()
            self.refresh_device_list()
            self.log_message(f"Device {mac} {'online' if device['online'] else 'offline'}")

    def on_device_select(self, event):
        selected = self.device_tree.selection()
        if not selected:
            return

        item = self.device_tree.item(selected[0])
        mac = item['values'][2]
        self.current_device_mac = mac

        if mac in self.devices:
            device = self.devices[mac]
            
            # Update Info tab
            details = f"Name: {device.get('name', 'Unknown')}\n"
            details += f"MAC: {mac}\n"
            details += f"Type: {device.get('type', 'unknown')}\n"
            details += f"Online: {device.get('online', False)}\n"
            
            self.details_text.delete(1.0, tk.END)
            self.details_text.insert(tk.END, details)

            # Update Switches tab
            self.update_switches_controls(device, mac)

            # Update Sensors tab
            self.update_sensors_controls(device, mac)

    def update_switches_controls(self, device, mac):
        """Update switch control buttons with proper UI for each switch type"""
        # Clear existing widgets
        for widget in self.switches_frame.winfo_children():
            widget.destroy()

        switches = device.get('switches', [])
        if not switches:
            ttk.Label(self.switches_frame, text="No switches available").pack()
            return

        is_offline = not device.get('online', False)
        offline_text = " (OFFLINE - Controls Disabled)" if is_offline else ""
        ttk.Label(self.switches_frame, text=f"Switches ({len(switches)}): {offline_text}", 
                 font=("", 10, "bold")).pack(anchor=tk.W, pady=(0, 10))

        for i, switch in enumerate(switches):
            frame = ttk.Frame(self.switches_frame)
            frame.pack(fill=tk.X, pady=5)

            switch_type = switch.get('type', 'toggle')
            is_on = switch.get('isOn', False)
            value = switch.get('value', 0)

            # Label with status
            if switch_type == 'toggle':
                state_text = "ON" if is_on else "OFF"
                label = ttk.Label(frame, text=f"Switch {i} ({switch_type}): {state_text}", font=("", 9))
            elif switch_type == 'fan':
                label = ttk.Label(frame, text=f"Switch {i} ({switch_type}): Speed {int(value)}", font=("", 9))
            elif switch_type == 'dimmer':
                label = ttk.Label(frame, text=f"Switch {i} ({switch_type}): {int(value)}%", font=("", 9))
            elif switch_type == 'curtain':
                positions = {0: "Closed", 1: "Opening", 2: "Open"}
                pos_text = positions.get(int(value), "Unknown")
                label = ttk.Label(frame, text=f"Switch {i} ({switch_type}): {pos_text}", font=("", 9))
            elif switch_type == 'scene':
                label = ttk.Label(frame, text=f"Scene {i}: Trigger", font=("", 9))
            else:
                label = ttk.Label(frame, text=f"Switch {i}: Unknown", font=("", 9))

            label.pack(side=tk.LEFT, padx=(0, 10))

            # Controls based on switch type
            if switch_type == 'toggle':
                toggle_btn = ttk.Button(frame, text="Toggle", state=tk.DISABLED if is_offline else tk.NORMAL,
                                       command=lambda m=mac, s=i: self.toggle_switch(m, s))
                toggle_btn.pack(side=tk.LEFT, padx=5)

            elif switch_type == 'fan':
                # Fan speed selector (0-5)
                for speed in range(6):
                    btn = ttk.Button(frame, text=f"Speed {speed}", 
                                    state=tk.DISABLED if is_offline else tk.NORMAL,
                                    command=lambda m=mac, s=i, v=speed: self.update_switch_value(m, s, v))
                    btn.pack(side=tk.LEFT, padx=2)

            elif switch_type == 'dimmer':
                # Dimmer slider (0-100)
                slider = ttk.Scale(frame, from_=0, to=100, orient=tk.HORIZONTAL, state=tk.DISABLED if is_offline else tk.NORMAL,
                                  command=lambda v, m=mac, s=i: self.update_switch_value(m, s, int(float(v))))
                slider.set(value)
                slider.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
                
                value_label = ttk.Label(frame, text=f"{int(value)}%", width=4)
                value_label.pack(side=tk.LEFT, padx=5)

            elif switch_type == 'curtain':
                # Curtain controls: Open, Stop, Close
                open_btn = ttk.Button(frame, text="Open", state=tk.DISABLED if is_offline else tk.NORMAL,
                                     command=lambda m=mac, s=i: self.update_switch_value(m, s, 2))
                open_btn.pack(side=tk.LEFT, padx=2)
                
                stop_btn = ttk.Button(frame, text="Stop", state=tk.DISABLED if is_offline else tk.NORMAL,
                                     command=lambda m=mac, s=i: self.update_switch_value(m, s, 1))
                stop_btn.pack(side=tk.LEFT, padx=2)
                
                close_btn = ttk.Button(frame, text="Close", state=tk.DISABLED if is_offline else tk.NORMAL,
                                      command=lambda m=mac, s=i: self.update_switch_value(m, s, 0))
                close_btn.pack(side=tk.LEFT, padx=2)

            elif switch_type == 'scene':
                # Scene trigger button
                trigger_btn = ttk.Button(frame, text="Trigger Scene", state=tk.DISABLED if is_offline else tk.NORMAL,
                                        command=lambda m=mac, s=i: self.update_switch_value(m, s, 1))
                trigger_btn.pack(side=tk.LEFT, padx=5)

    def update_sensors_controls(self, device, mac):
        """Update sensor control sliders"""
        # Clear existing widgets
        for widget in self.sensors_frame.winfo_children():
            widget.destroy()

        sensors = device.get('sensors', [])
        if not sensors:
            ttk.Label(self.sensors_frame, text="No sensors available").pack()
            return

        ttk.Label(self.sensors_frame, text=f"Sensors ({len(sensors)}):", font=("", 10, "bold")).pack(anchor=tk.W, pady=(0, 10))

        for i, sensor in enumerate(sensors):
            sensor_type = sensor.get('type', 'unknown')
            value = sensor.get('value', 0)
            unit = sensor.get('unit', '')

            frame = ttk.Frame(self.sensors_frame)
            frame.pack(fill=tk.X, pady=8)

            # Sensor label
            label = ttk.Label(frame, text=f"{sensor_type}: {value}{unit}", font=("", 9), width=20)
            label.pack(side=tk.LEFT, padx=(0, 10))

            # Determine range based on sensor type
            if sensor_type == 'temperature':
                min_val, max_val = 10, 40
            elif sensor_type == 'humidity':
                min_val, max_val = 0, 100
            elif sensor_type == 'light-level':
                min_val, max_val = 0, 1000
            elif sensor_type == 'motion':
                min_val, max_val = 0, 1
            else:
                min_val, max_val = 0, 100

            # Slider
            slider = ttk.Scale(frame, from_=min_val, to=max_val, orient=tk.HORIZONTAL,
                              command=lambda v, m=mac, s=i, l=label: self.update_sensor_value(m, s, float(v), l, unit))
            slider.set(value)
            slider.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)

    def toggle_switch(self, mac, switch_index):
        """Toggle a switch on/off"""
        if self.updating_ui or mac not in self.devices:
            return

        device = self.devices[mac]
        
        # Check if device is offline
        if not device.get('online', False):
            messagebox.showwarning("Warning", "Cannot control offline device")
            return
        
        switches = device.get('switches', [])
        
        if switch_index >= len(switches):
            return

        # Toggle the switch
        switches[switch_index]['isOn'] = not switches[switch_index].get('isOn', False)
        
        # Update UI
        self.updating_ui = True
        self.update_switches_controls(device, mac)
        self.updating_ui = False
        
        # Publish MQTT message
        if self.connected:
            control_topic = f"smarthome/{self.api_key}/{mac}/control"
            payload = {
                'switchIndex': switch_index,
                'isOn': switches[switch_index]['isOn'],
                'value': switches[switch_index].get('value', 0),
                'type': switches[switch_index].get('type', 'toggle')
            }
            self.client.publish(control_topic, json.dumps(payload))
            self.log_message(f"Toggled {mac} switch {switch_index} to {'ON' if switches[switch_index]['isOn'] else 'OFF'}")
        
        # Save changes
        self.save_devices()

    def update_switch_value(self, mac, switch_index, value):
        """Update switch value (for dimmers, fans, curtains, scenes)"""
        if self.updating_ui or mac not in self.devices:
            return

        device = self.devices[mac]
        
        # Check if device is offline
        if not device.get('online', False):
            messagebox.showwarning("Warning", "Cannot control offline device")
            return
        
        switches = device.get('switches', [])
        
        if switch_index >= len(switches):
            return

        switches[switch_index]['value'] = value
        
        # Update UI to show new value
        self.updating_ui = True
        self.update_switches_controls(device, mac)
        self.updating_ui = False
        
        # Publish MQTT message immediately
        if self.connected:
            control_topic = f"smarthome/{self.api_key}/{mac}/control"
            switch_type = switches[switch_index].get('type', 'dimmer')
            payload = {
                'switchIndex': switch_index,
                'isOn': switches[switch_index].get('isOn', False),
                'value': int(value),
                'type': switch_type
            }
            self.client.publish(control_topic, json.dumps(payload))
            self.log_message(f"Updated {mac} switch {switch_index} ({switch_type}) to value {value}")
        
        # Save changes
        self.save_devices()

    def update_sensor_value(self, mac, sensor_index, value, label, unit):
        """Update sensor value"""
        if self.updating_ui or mac not in self.devices:
            return

        device = self.devices[mac]
        sensors = device.get('sensors', [])
        
        if sensor_index >= len(sensors):
            return

        sensors[sensor_index]['value'] = float(value)
        
        # Update label
        sensor_type = sensors[sensor_index].get('type', 'unknown')
        display_value = int(float(value)) if float(value) == int(float(value)) else float(value)
        label.config(text=f"{sensor_type}: {display_value}{unit}")
        
        # Publish MQTT message immediately (no UI update loop)
        if self.connected:
            sensor_topic = f"smarthome/{self.api_key}/{mac}/sensor"
            payload = {
                'sensorIndex': sensor_index,
                'type': sensor_type,
                'value': float(value),
                'unit': unit
            }
            self.client.publish(sensor_topic, json.dumps(payload))
        
        # Save changes
        self.save_devices()

def main():
    root = tk.Tk()
    app = DeviceSimulator(root)
    root.mainloop()

if __name__ == "__main__":
    main()