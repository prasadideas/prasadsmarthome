#!/usr/bin/env python3
"""
SmartHome Device Simulator.

Generic desktop simulator for MQTT-controlled smart-home devices.
"""

from __future__ import annotations

import json
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, scrolledtext, ttk

import paho.mqtt.client as mqtt


BASE_DIR = Path(__file__).resolve().parent
DEVICES_FILE = BASE_DIR / "devices.json"


COLORS = {
    "bg": "#EAF0F6",
    "panel": "#F4F7FB",
    "surface": "#FFFFFF",
    "surface_alt": "#EEF3F8",
    "border": "#D5DFEA",
    "text": "#1F2A37",
    "muted": "#64748B",
    "accent": "#176B87",
    "accent_hover": "#145A72",
    "accent_soft": "#D9EEF5",
    "success": "#15803D",
    "success_soft": "#DCFCE7",
    "danger": "#B42318",
    "danger_soft": "#FEE4E2",
    "warning": "#B54708",
    "warning_soft": "#FEF0C7",
    "log_bg": "#0F172A",
    "log_fg": "#E2E8F0",
}


LEGACY_DEVICE_TYPES = {
    "1-switch": "sw_1",
    "2-switch": "sw_2",
    "4-switch": "sw_4",
    "6-switch": "sw_6",
    "8-switch": "sw_8",
    "12-switch": "sw_12",
    "16-switch": "sw_16",
}


SENSOR_CATALOG = {
    "temperature": {
        "label": "Temperature",
        "unit": "°C",
        "min": 10.0,
        "max": 45.0,
        "step": 0.5,
        "default": 24.0,
        "mode": "scale",
        "presets": [18.0, 24.0, 30.0],
    },
    "humidity": {
        "label": "Humidity",
        "unit": "%",
        "min": 0.0,
        "max": 100.0,
        "step": 1.0,
        "default": 45.0,
        "mode": "scale",
        "presets": [30.0, 50.0, 70.0],
    },
    "light-level": {
        "label": "Light Level",
        "unit": "lux",
        "min": 0.0,
        "max": 1000.0,
        "step": 10.0,
        "default": 320.0,
        "mode": "scale",
        "presets": [80.0, 400.0, 850.0],
    },
    "motion": {
        "label": "Motion",
        "unit": "",
        "min": 0.0,
        "max": 1.0,
        "step": 1.0,
        "default": 0.0,
        "mode": "binary",
        "states": {0: "Clear", 1: "Detected"},
    },
    "contact": {
        "label": "Contact",
        "unit": "",
        "min": 0.0,
        "max": 1.0,
        "step": 1.0,
        "default": 0.0,
        "mode": "binary",
        "states": {0: "Closed", 1: "Open"},
    },
    "power": {
        "label": "Power",
        "unit": "W",
        "min": 0.0,
        "max": 5000.0,
        "step": 10.0,
        "default": 120.0,
        "mode": "scale",
        "presets": [60.0, 500.0, 1500.0],
    },
    "voltage": {
        "label": "Voltage",
        "unit": "V",
        "min": 0.0,
        "max": 260.0,
        "step": 1.0,
        "default": 230.0,
        "mode": "scale",
        "presets": [210.0, 230.0, 245.0],
    },
    "current": {
        "label": "Current",
        "unit": "A",
        "min": 0.0,
        "max": 32.0,
        "step": 0.5,
        "default": 2.5,
        "mode": "scale",
        "presets": [1.0, 5.0, 10.0],
    },
    "air-quality": {
        "label": "Air Quality",
        "unit": "AQI",
        "min": 0.0,
        "max": 500.0,
        "step": 1.0,
        "default": 80.0,
        "mode": "scale",
        "presets": [50.0, 100.0, 180.0],
    },
    "water-level": {
        "label": "Water Level",
        "unit": "%",
        "min": 0.0,
        "max": 100.0,
        "step": 1.0,
        "default": 55.0,
        "mode": "scale",
        "presets": [20.0, 60.0, 90.0],
    },
    "smoke": {
        "label": "Smoke",
        "unit": "",
        "min": 0.0,
        "max": 1.0,
        "step": 1.0,
        "default": 0.0,
        "mode": "binary",
        "states": {0: "Normal", 1: "Alarm"},
    },
}


def toggle_specs(count: int) -> list[dict[str, str]]:
    return [
        {"type": "toggle", "label": f"Switch {index + 1}"}
        for index in range(count)
    ]


def scene_specs(count: int) -> list[dict[str, str]]:
    return [
        {"type": "scene", "label": f"Scene {index + 1}"}
        for index in range(count)
    ]


def device_template(
    name: str,
    switch_specs: list[dict[str, str]],
    default_sensors: list[str] | None = None,
) -> dict[str, object]:
    return {
        "name": name,
        "switches": switch_specs,
        "default_sensors": default_sensors or [],
    }


DEVICE_CATALOG = {
    "sw_1": device_template("1-switch board", toggle_specs(1)),
    "sw_2": device_template("2-switch board", toggle_specs(2)),
    "sw_4": device_template("4-switch board", toggle_specs(4), ["power"]),
    "sw_6": device_template("6-switch board", toggle_specs(6), ["power", "voltage"]),
    "sw_8": device_template("8-switch panel", toggle_specs(8), ["power", "voltage", "current"]),
    "sw_12": device_template("12-switch panel", toggle_specs(12), ["power", "voltage", "current"]),
    "sw_16": device_template("16-switch panel", toggle_specs(16), ["power", "voltage", "current"]),
    "sw_2_fan": device_template(
        "2 switches + fan",
        toggle_specs(2) + [{"type": "fan", "label": "Fan"}],
        ["temperature", "humidity"],
    ),
    "sw_4_fan": device_template(
        "4 switches + fan",
        toggle_specs(4) + [{"type": "fan", "label": "Fan"}],
        ["temperature", "humidity", "power"],
    ),
    "sw_2_dim": device_template(
        "2 switches + dimmer",
        toggle_specs(2) + [{"type": "dimmer", "label": "Dimmer"}],
        ["light-level", "motion"],
    ),
    "sw_4_dim": device_template(
        "4 switches + dimmer",
        toggle_specs(4) + [{"type": "dimmer", "label": "Dimmer"}],
        ["light-level", "motion", "power"],
    ),
    "curtain": device_template(
        "Curtain controller",
        [
            {"type": "curtain", "label": "Curtain 1"},
            {"type": "curtain", "label": "Curtain 2"},
            {"type": "curtain", "label": "Curtain 3"},
        ],
        ["light-level", "contact"],
    ),
    "scene_8": device_template("8-button scene panel", scene_specs(8)),
}


CURTAIN_LABELS = {0: "Closed", 1: "Paused", 2: "Open"}
SCENE_RESET_DELAY_MS = 350


def clear_children(widget: tk.Misc) -> None:
    for child in widget.winfo_children():
        child.destroy()


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def step_value(value: float, step: float) -> float:
    if step <= 0:
        return value
    stepped = round(value / step) * step
    if step >= 1:
        return float(int(round(stepped)))
    return round(stepped, 2)


def normalize_mac(mac: str) -> str:
    compact = mac.replace(":", "").replace("-", "").upper()
    if len(compact) != 12:
        return mac.strip().upper()
    return ":".join(compact[index:index + 2] for index in range(0, 12, 2))


def is_valid_mac(mac: str) -> bool:
    compact = mac.replace(":", "").replace("-", "").upper()
    return len(compact) == 12 and all(char in "0123456789ABCDEF" for char in compact)


def reason_code_success(reason_code: object) -> bool:
    try:
        return int(reason_code) == 0
    except Exception:
        return str(reason_code).strip().lower() == "success"


def humanize(value: str) -> str:
    return value.replace("-", " ").replace("_", " ").title()


class DeviceSimulator:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("SmartHome Device Simulator")
        self.root.geometry("1480x920")
        self.root.minsize(1280, 820)
        self.root.configure(bg=COLORS["bg"])
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

        self.broker_host = "test.mosquitto.org"
        self.broker_port = 1883
        self.api_key = "smarthome_default"
        self.heartbeat_interval = 30

        self.client: mqtt.Client | None = None
        self.connected = False
        self._has_connected_once = False
        self._manual_disconnect = False
        self._shutting_down = False
        self._disconnect_log_gate = 0.0

        self.devices: dict[str, dict[str, object]] = {}
        self.current_device_mac: str | None = None
        self.updating_ui = False
        self.heartbeat_threads: dict[str, threading.Thread] = {}
        self.stop_heartbeat_flags: dict[str, bool] = {}

        self.search_var = tk.StringVar()
        self.host_var = tk.StringVar()
        self.port_var = tk.StringVar()
        self.api_key_var = tk.StringVar()
        self.heartbeat_var = tk.StringVar()
        self.summary_var = tk.StringVar(value="No devices loaded")
        self.detail_title_var = tk.StringVar(value="No device selected")
        self.connection_status_var = tk.StringVar(value="Disconnected")
        self.connection_note_var = tk.StringVar(value="Broker idle")

        self.info_value_labels: dict[str, tk.Label] = {}
        self.feature_chips_frame: tk.Frame | None = None
        self.device_tree: ttk.Treeview | None = None
        self.log_text: scrolledtext.ScrolledText | None = None
        self.details_notebook: ttk.Notebook | None = None
        self.overview_frame: tk.Frame | None = None
        self.switches_frame: tk.Frame | None = None
        self.sensors_frame: tk.Frame | None = None
        self.connection_badge: tk.Label | None = None

        self.load_devices()
        self.configure_styles()
        self.setup_ui()
        self.refresh_device_list()
        self.connect_mqtt()

    def configure_styles(self) -> None:
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("App.TFrame", background=COLORS["bg"])
        style.configure(
            "Panel.TLabelframe",
            background=COLORS["panel"],
            bordercolor=COLORS["border"],
            relief="solid",
            borderwidth=1,
        )
        style.configure(
            "Panel.TLabelframe.Label",
            background=COLORS["panel"],
            foreground=COLORS["text"],
            font=("Segoe UI", 11, "bold"),
        )
        style.configure(
            "Treeview",
            background=COLORS["surface"],
            fieldbackground=COLORS["surface"],
            foreground=COLORS["text"],
            bordercolor=COLORS["border"],
            rowheight=30,
            font=("Segoe UI", 10),
        )
        style.configure(
            "Treeview.Heading",
            background=COLORS["surface_alt"],
            foreground=COLORS["text"],
            font=("Segoe UI", 10, "bold"),
            relief="flat",
        )
        style.map(
            "Treeview",
            background=[("selected", COLORS["accent_soft"])],
            foreground=[("selected", COLORS["text"])],
        )
        style.configure("TNotebook", background=COLORS["panel"], borderwidth=0)
        style.configure("TNotebook.Tab", padding=(14, 8), font=("Segoe UI", 10, "bold"))

    def setup_ui(self) -> None:
        header = tk.Frame(self.root, bg=COLORS["bg"], padx=18, pady=18)
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        header.columnconfigure(1, weight=1)

        title_frame = tk.Frame(header, bg=COLORS["bg"])
        title_frame.grid(row=0, column=0, sticky="w")

        tk.Label(
            title_frame,
            text="SmartHome Device Simulator",
            bg=COLORS["bg"],
            fg=COLORS["text"],
            font=("Segoe UI", 22, "bold"),
        ).pack(anchor="w")
        tk.Label(
            title_frame,
            text="Generic MQTT simulator with real device-style controls.",
            bg=COLORS["bg"],
            fg=COLORS["muted"],
            font=("Segoe UI", 11),
        ).pack(anchor="w", pady=(4, 0))

        connection_frame = tk.Frame(
            header,
            bg=COLORS["surface"],
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            padx=16,
            pady=12,
        )
        connection_frame.grid(row=0, column=1, sticky="ew")
        connection_frame.columnconfigure(1, weight=1)
        connection_frame.columnconfigure(3, weight=1)

        self.connection_badge = tk.Label(
            connection_frame,
            textvariable=self.connection_status_var,
            bg=COLORS["danger_soft"],
            fg=COLORS["danger"],
            font=("Segoe UI", 10, "bold"),
            padx=12,
            pady=6,
        )
        self.connection_badge.grid(row=0, column=0, padx=(0, 12), pady=(0, 10), sticky="w")

        tk.Label(
            connection_frame,
            textvariable=self.connection_note_var,
            bg=COLORS["surface"],
            fg=COLORS["muted"],
            font=("Segoe UI", 10),
        ).grid(row=0, column=1, columnspan=5, sticky="w", pady=(0, 10))

        self.host_var.set(self.broker_host)
        self.port_var.set(str(self.broker_port))
        self.api_key_var.set(self.api_key)
        self.heartbeat_var.set(str(self.heartbeat_interval))

        self._build_header_entry(connection_frame, 1, 0, "Broker", self.host_var, width=26)
        self._build_header_entry(connection_frame, 1, 2, "Port", self.port_var, width=8)
        self._build_header_entry(connection_frame, 1, 4, "API Key", self.api_key_var, width=18)
        self._build_header_entry(connection_frame, 2, 0, "Heartbeat", self.heartbeat_var, width=8)

        button_row = tk.Frame(connection_frame, bg=COLORS["surface"])
        button_row.grid(row=2, column=2, columnspan=4, sticky="e")

        self._make_button(button_row, "Connect", self.connect_mqtt, variant="accent").pack(side="left", padx=4)
        self._make_button(button_row, "Disconnect", self.disconnect_mqtt, variant="secondary").pack(side="left", padx=4)
        self._make_button(button_row, "Test", self.test_connection, variant="secondary").pack(side="left", padx=4)
        self._make_button(button_row, "Load Demos", self.load_demo_devices, variant="secondary").pack(side="left", padx=4)

        body = tk.Frame(self.root, bg=COLORS["bg"])
        body.grid(row=1, column=0, sticky="nsew", padx=18, pady=(0, 18))
        body.columnconfigure(0, weight=0)
        body.columnconfigure(1, weight=1)
        body.rowconfigure(0, weight=1)
        body.rowconfigure(1, weight=0)

        list_panel = ttk.LabelFrame(body, text="Devices", style="Panel.TLabelframe")
        list_panel.grid(row=0, column=0, sticky="ns", padx=(0, 14))

        list_inner = tk.Frame(list_panel, bg=COLORS["panel"], padx=12, pady=12)
        list_inner.pack(fill="both", expand=True)
        list_inner.rowconfigure(2, weight=1)

        search_entry = tk.Entry(
            list_inner,
            textvariable=self.search_var,
            bg=COLORS["surface"],
            fg=COLORS["text"],
            relief="flat",
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            font=("Segoe UI", 10),
        )
        search_entry.grid(row=0, column=0, sticky="ew")
        search_entry.insert(0, "")

        tk.Label(
            list_inner,
            textvariable=self.summary_var,
            bg=COLORS["panel"],
            fg=COLORS["muted"],
            font=("Segoe UI", 10),
        ).grid(row=1, column=0, sticky="w", pady=(8, 12))

        tree_frame = tk.Frame(list_inner, bg=COLORS["panel"])
        tree_frame.grid(row=2, column=0, sticky="nsew")
        tree_frame.rowconfigure(0, weight=1)
        tree_frame.columnconfigure(0, weight=1)

        self.device_tree = ttk.Treeview(
            tree_frame,
            columns=("template", "switches", "sensors", "status", "mac"),
            selectmode="browse",
            height=18,
        )
        self.device_tree.heading("#0", text="Device")
        self.device_tree.heading("template", text="Template")
        self.device_tree.heading("switches", text="Ctrl")
        self.device_tree.heading("sensors", text="Sensors")
        self.device_tree.heading("status", text="State")
        self.device_tree.heading("mac", text="MAC")
        self.device_tree.column("#0", width=180, stretch=True)
        self.device_tree.column("template", width=140, stretch=False)
        self.device_tree.column("switches", width=56, stretch=False, anchor="center")
        self.device_tree.column("sensors", width=64, stretch=False, anchor="center")
        self.device_tree.column("status", width=84, stretch=False, anchor="center")
        self.device_tree.column("mac", width=160, stretch=False)
        self.device_tree.grid(row=0, column=0, sticky="nsew")

        tree_scroll = ttk.Scrollbar(tree_frame, orient="vertical", command=self.device_tree.yview)
        tree_scroll.grid(row=0, column=1, sticky="ns")
        self.device_tree.configure(yscrollcommand=tree_scroll.set)
        self.device_tree.bind("<<TreeviewSelect>>", self.on_device_select)

        button_grid = tk.Frame(list_inner, bg=COLORS["panel"])
        button_grid.grid(row=3, column=0, sticky="ew", pady=(12, 0))
        button_grid.columnconfigure((0, 1), weight=1)

        self._make_button(button_grid, "Add Device", self.open_device_dialog, variant="accent", width=16).grid(row=0, column=0, padx=4, pady=4, sticky="ew")
        self._make_button(button_grid, "Toggle Online", self.toggle_device_online, variant="secondary", width=16).grid(row=0, column=1, padx=4, pady=4, sticky="ew")
        self._make_button(button_grid, "Add Sensor", self.open_sensor_dialog, variant="secondary", width=16).grid(row=1, column=0, padx=4, pady=4, sticky="ew")
        self._make_button(button_grid, "Remove Device", self.remove_device, variant="danger", width=16).grid(row=1, column=1, padx=4, pady=4, sticky="ew")

        detail_panel = ttk.LabelFrame(body, text="Device Details", style="Panel.TLabelframe")
        detail_panel.grid(row=0, column=1, sticky="nsew")

        detail_inner = tk.Frame(detail_panel, bg=COLORS["panel"], padx=12, pady=12)
        detail_inner.pack(fill="both", expand=True)
        detail_inner.rowconfigure(1, weight=1)
        detail_inner.columnconfigure(0, weight=1)

        tk.Label(
            detail_inner,
            textvariable=self.detail_title_var,
            bg=COLORS["panel"],
            fg=COLORS["text"],
            font=("Segoe UI", 16, "bold"),
        ).grid(row=0, column=0, sticky="w", pady=(0, 10))

        self.details_notebook = ttk.Notebook(detail_inner)
        self.details_notebook.grid(row=1, column=0, sticky="nsew")

        overview_tab = tk.Frame(self.details_notebook, bg=COLORS["panel"])
        controls_tab = tk.Frame(self.details_notebook, bg=COLORS["panel"])
        sensors_tab = tk.Frame(self.details_notebook, bg=COLORS["panel"])

        self.details_notebook.add(overview_tab, text="Overview")
        self.details_notebook.add(controls_tab, text="Controls")
        self.details_notebook.add(sensors_tab, text="Sensors")

        self.overview_frame = tk.Frame(overview_tab, bg=COLORS["panel"], padx=14, pady=14)
        self.overview_frame.pack(fill="both", expand=True)
        self._build_overview_tab(self.overview_frame)

        _, self.switches_frame = self._build_scrollable_panel(controls_tab)
        _, self.sensors_frame = self._build_scrollable_panel(sensors_tab)

        log_panel = ttk.LabelFrame(body, text="Activity Log", style="Panel.TLabelframe")
        log_panel.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(14, 0))

        log_inner = tk.Frame(log_panel, bg=COLORS["panel"], padx=12, pady=12)
        log_inner.pack(fill="both", expand=True)
        log_inner.columnconfigure(0, weight=1)

        log_actions = tk.Frame(log_inner, bg=COLORS["panel"])
        log_actions.grid(row=0, column=0, sticky="e", pady=(0, 8))
        self._make_button(log_actions, "Clear Log", self.clear_logs, variant="secondary", width=12).pack(side="left")

        self.log_text = scrolledtext.ScrolledText(
            log_inner,
            height=11,
            bg=COLORS["log_bg"],
            fg=COLORS["log_fg"],
            insertbackground=COLORS["log_fg"],
            relief="flat",
            font=("Consolas", 10),
        )
        self.log_text.grid(row=1, column=0, sticky="ew")

        self.search_var.trace_add("write", lambda *_: self.refresh_device_list())

    def _build_header_entry(
        self,
        parent: tk.Widget,
        row: int,
        column: int,
        label: str,
        variable: tk.StringVar,
        width: int,
    ) -> None:
        tk.Label(
            parent,
            text=label,
            bg=COLORS["surface"],
            fg=COLORS["muted"],
            font=("Segoe UI", 9, "bold"),
        ).grid(row=row, column=column, sticky="w", pady=4)
        entry = tk.Entry(
            parent,
            textvariable=variable,
            width=width,
            bg=COLORS["surface_alt"],
            fg=COLORS["text"],
            relief="flat",
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            font=("Segoe UI", 10),
        )
        entry.grid(row=row, column=column + 1, sticky="ew", padx=(8, 16), pady=4)

    def _build_overview_tab(self, parent: tk.Frame) -> None:
        summary_card = tk.Frame(
            parent,
            bg=COLORS["surface"],
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            padx=18,
            pady=18,
        )
        summary_card.pack(fill="x")
        summary_card.columnconfigure(1, weight=1)
        summary_card.columnconfigure(3, weight=1)

        fields = [
            (0, 0, "Template"),
            (0, 2, "MAC"),
            (1, 0, "Online"),
            (1, 2, "Switches"),
            (2, 0, "Sensors"),
            (2, 2, "Topic Base"),
        ]
        for row, column, title in fields:
            tk.Label(
                summary_card,
                text=title,
                bg=COLORS["surface"],
                fg=COLORS["muted"],
                font=("Segoe UI", 9, "bold"),
            ).grid(row=row * 2, column=column, sticky="w", pady=(0, 4))
            value_label = tk.Label(
                summary_card,
                text="-",
                bg=COLORS["surface"],
                fg=COLORS["text"],
                font=("Segoe UI", 11, "bold"),
            )
            value_label.grid(row=row * 2 + 1, column=column, columnspan=2, sticky="w", pady=(0, 10))
            self.info_value_labels[title] = value_label

        actions_card = tk.Frame(
            parent,
            bg=COLORS["surface"],
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            padx=18,
            pady=16,
        )
        actions_card.pack(fill="x", pady=(14, 0))

        tk.Label(
            actions_card,
            text="Quick Actions",
            bg=COLORS["surface"],
            fg=COLORS["text"],
            font=("Segoe UI", 12, "bold"),
        ).pack(anchor="w")

        action_row = tk.Frame(actions_card, bg=COLORS["surface"])
        action_row.pack(anchor="w", pady=(12, 0))

        self._make_button(
            action_row,
            "Send All Status",
            lambda: self.publish_all_switch_statuses(self.current_device_mac),
            variant="accent",
            width=14,
        ).pack(side="left", padx=(0, 8))
        self._make_button(
            action_row,
            "Toggle Online",
            self.toggle_device_online,
            variant="secondary",
            width=14,
        ).pack(side="left", padx=(0, 8))
        self._make_button(
            action_row,
            "Add Sensor",
            self.open_sensor_dialog,
            variant="secondary",
            width=14,
        ).pack(side="left")

        features_card = tk.Frame(
            parent,
            bg=COLORS["surface"],
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            padx=18,
            pady=16,
        )
        features_card.pack(fill="both", expand=True, pady=(14, 0))

        tk.Label(
            features_card,
            text="Device Features",
            bg=COLORS["surface"],
            fg=COLORS["text"],
            font=("Segoe UI", 12, "bold"),
        ).pack(anchor="w")

        self.feature_chips_frame = tk.Frame(features_card, bg=COLORS["surface"])
        self.feature_chips_frame.pack(fill="both", expand=True, pady=(12, 0))

    def _build_scrollable_panel(self, parent: tk.Frame) -> tuple[tk.Frame, tk.Frame]:
        outer = tk.Frame(parent, bg=COLORS["panel"])
        outer.pack(fill="both", expand=True)
        outer.rowconfigure(0, weight=1)
        outer.columnconfigure(0, weight=1)

        canvas = tk.Canvas(
            outer,
            bg=COLORS["panel"],
            highlightthickness=0,
            borderwidth=0,
        )
        canvas.grid(row=0, column=0, sticky="nsew")

        scrollbar = ttk.Scrollbar(outer, orient="vertical", command=canvas.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        canvas.configure(yscrollcommand=scrollbar.set)

        content = tk.Frame(canvas, bg=COLORS["panel"], padx=12, pady=12)
        window_id = canvas.create_window((0, 0), window=content, anchor="nw")

        content.bind(
            "<Configure>",
            lambda event: canvas.configure(scrollregion=canvas.bbox("all")),
        )
        canvas.bind(
            "<Configure>",
            lambda event: canvas.itemconfigure(window_id, width=event.width),
        )

        return outer, content

    def _make_button(
        self,
        parent: tk.Widget,
        text: str,
        command,
        *,
        variant: str = "secondary",
        width: int = 12,
        state: str = tk.NORMAL,
    ) -> tk.Button:
        palettes = {
            "accent": (COLORS["accent"], "#FFFFFF", COLORS["accent_hover"]),
            "secondary": (COLORS["surface_alt"], COLORS["text"], "#DDE7F0"),
            "danger": (COLORS["danger_soft"], COLORS["danger"], "#FECACA"),
            "success": (COLORS["success_soft"], COLORS["success"], "#BBF7D0"),
        }
        bg, fg, active_bg = palettes[variant]
        if state == tk.DISABLED:
            bg = COLORS["surface_alt"]
            fg = COLORS["muted"]
            active_bg = bg
        return tk.Button(
            parent,
            text=text,
            command=command,
            width=width,
            state=state,
            bg=bg,
            fg=fg,
            activebackground=active_bg,
            activeforeground=fg,
            relief="flat",
            bd=0,
            padx=10,
            pady=7,
            font=("Segoe UI", 10, "bold"),
            cursor="hand2" if state != tk.DISABLED else "arrow",
        )

    def _make_option_button(
        self,
        parent: tk.Widget,
        text: str,
        command,
        *,
        selected: bool = False,
        disabled: bool = False,
        width: int = 10,
    ) -> tk.Button:
        if disabled:
            bg = COLORS["surface_alt"]
            fg = COLORS["muted"]
            active_bg = bg
        elif selected:
            bg = COLORS["accent"]
            fg = "#FFFFFF"
            active_bg = COLORS["accent_hover"]
        else:
            bg = COLORS["surface_alt"]
            fg = COLORS["text"]
            active_bg = "#DDE7F0"

        return tk.Button(
            parent,
            text=text,
            command=command,
            width=width,
            state=tk.DISABLED if disabled else tk.NORMAL,
            bg=bg,
            fg=fg,
            activebackground=active_bg,
            activeforeground=fg,
            relief="flat",
            bd=0,
            padx=8,
            pady=6,
            font=("Segoe UI", 9, "bold"),
            cursor="hand2" if not disabled else "arrow",
        )

    def _set_connection_state(self, title: str, note: str, tone: str) -> None:
        self.connection_status_var.set(title)
        self.connection_note_var.set(note)

        if self.connection_badge is None:
            return

        palettes = {
            "success": (COLORS["success_soft"], COLORS["success"]),
            "warning": (COLORS["warning_soft"], COLORS["warning"]),
            "danger": (COLORS["danger_soft"], COLORS["danger"]),
        }
        bg, fg = palettes[tone]
        self.connection_badge.configure(bg=bg, fg=fg)

    def _apply_connection_settings(self) -> bool:
        host = self.host_var.get().strip()
        api_key = self.api_key_var.get().strip()

        try:
            port = int(self.port_var.get().strip())
            heartbeat = int(self.heartbeat_var.get().strip())
        except ValueError:
            messagebox.showerror("Invalid settings", "Port and heartbeat must be numeric.")
            return False

        if not host:
            messagebox.showerror("Invalid settings", "Broker host is required.")
            return False
        if port <= 0:
            messagebox.showerror("Invalid settings", "Broker port must be positive.")
            return False
        if heartbeat <= 0:
            messagebox.showerror("Invalid settings", "Heartbeat must be positive.")
            return False
        if not api_key:
            messagebox.showerror("Invalid settings", "API key is required.")
            return False

        self.broker_host = host
        self.broker_port = port
        self.api_key = api_key
        self.heartbeat_interval = heartbeat
        self.save_devices()
        return True

    def test_connection(self) -> None:
        if not self._apply_connection_settings():
            return

        tester = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        tester_connected = False

        def on_connect(client, userdata, flags, reason_code, properties=None):
            nonlocal tester_connected
            tester_connected = reason_code_success(reason_code)
            if tester_connected:
                self.log_message(f"Broker test passed: {self.broker_host}:{self.broker_port}")
            else:
                self.log_message(f"Broker test failed: {reason_code}")

        def on_disconnect(client, userdata, flags, reason_code, properties=None):
            if not tester_connected:
                self.log_message(f"Broker test disconnect: {reason_code}")

        tester.on_connect = on_connect
        tester.on_disconnect = on_disconnect

        try:
            tester.connect(self.broker_host, self.broker_port, 10)
            tester.loop_start()
            time.sleep(2)
        except Exception as error:
            self.log_message(f"Broker test error: {error}")
        finally:
            try:
                tester.disconnect()
            except Exception:
                pass
            try:
                tester.loop_stop()
            except Exception:
                pass

    def log_message(self, message: str) -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        line = f"[{timestamp}] {message}"
        print(line)

        if self.log_text is None:
            return

        def append() -> None:
            try:
                self.log_text.insert(tk.END, line + "\n")
                self.log_text.see(tk.END)
            except tk.TclError:
                pass

        if threading.current_thread() is threading.main_thread():
            append()
            return

        self.root.after(0, append)

    def connect_mqtt(self) -> None:
        if not self._apply_connection_settings():
            return

        self.disconnect_mqtt(log=False)
        self._has_connected_once = False
        self._manual_disconnect = False

        client_id = f"smarthome-sim-{int(time.time() * 1000) % 100000}"
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id)
        self.client.on_connect = self.on_mqtt_connect
        self.client.on_disconnect = self.on_mqtt_disconnect
        self.client.on_message = self.on_mqtt_message
        self.client.on_connect_fail = self.on_mqtt_connect_fail
        self.client.reconnect_delay_set(min_delay=2, max_delay=12)
        self.client.connect_timeout = 10

        self._set_connection_state(
            "Connecting",
            f"Connecting to {self.broker_host}:{self.broker_port}",
            "warning",
        )
        self.log_message(f"Connecting to broker: {self.broker_host}:{self.broker_port}")

        try:
            self.client.connect_async(self.broker_host, self.broker_port, 60)
            self.client.loop_start()
        except Exception as error:
            self._set_connection_state("Disconnected", str(error), "danger")
            self.log_message(f"MQTT connection error: {error}")

    def disconnect_mqtt(self, log: bool = True) -> None:
        client = self.client
        self.client = None
        self.connected = False
        self._has_connected_once = False
        self._manual_disconnect = True

        if client is not None:
            try:
                client.loop_stop()
            except Exception:
                pass
            try:
                client.disconnect()
            except Exception:
                pass

        self._set_connection_state("Disconnected", "Broker idle", "danger")
        if log:
            self.log_message("MQTT connection closed")

    def on_mqtt_connect_fail(self, client, userdata) -> None:
        self.root.after(
            0,
            lambda: self._set_connection_state(
                "Retrying",
                f"Waiting for {self.broker_host}:{self.broker_port}",
                "warning",
            ),
        )

    def on_mqtt_connect(self, client, userdata, flags, reason_code, properties=None) -> None:
        self.root.after(0, lambda: self._handle_connected(reason_code))

    def _handle_connected(self, reason_code) -> None:
        if not reason_code_success(reason_code):
            self.connected = False
            self._set_connection_state("Failed", f"Broker refused: {reason_code}", "danger")
            self.log_message(f"MQTT connect refused: {reason_code}")
            return

        self.connected = True
        self._has_connected_once = True
        self._set_connection_state(
            "Connected",
            f"Live on {self.broker_host}:{self.broker_port}",
            "success",
        )
        self.log_message("MQTT connected successfully")

        for mac, device in self.devices.items():
            self.register_device_topics(mac)
            if bool(device.get("online", False)):
                self.start_heartbeat(mac)

        self.root.after(250, lambda: self.publish_all_switch_statuses())

    def on_mqtt_disconnect(self, client, userdata, flags, reason_code, properties=None) -> None:
        self.root.after(0, lambda: self._handle_disconnected(reason_code))

    def _handle_disconnected(self, reason_code) -> None:
        self.connected = False
        if self._manual_disconnect or self._shutting_down:
            self._manual_disconnect = False
            self._set_connection_state("Disconnected", "Broker idle", "danger")
            return

        if not self._has_connected_once:
            self._set_connection_state(
                "Connecting",
                f"Retrying {self.broker_host}:{self.broker_port}",
                "warning",
            )
            return

        self._set_connection_state(
            "Retrying",
            f"Broker retry: {reason_code}",
            "warning",
        )
        now = time.monotonic()
        if now - self._disconnect_log_gate > 3:
            self._disconnect_log_gate = now
            self.log_message(f"MQTT disconnected: {reason_code}")

    def register_device_topics(self, mac: str) -> None:
        if not self.client:
            return
        self.client.subscribe(f"smarthome/{self.api_key}/{mac}/control")
        self.client.subscribe(f"smarthome/{self.api_key}/{mac}/status")
        self.client.subscribe(f"smarthome/{self.api_key}/{mac}/sensor")

    def on_mqtt_message(self, client, userdata, msg) -> None:
        try:
            payload = json.loads(msg.payload.decode())
        except Exception as error:
            self.log_message(f"Bad MQTT payload: {error}")
            return

        self.root.after(0, lambda topic=msg.topic, data=payload: self._process_mqtt_message(topic, data))

    def _process_mqtt_message(self, topic: str, payload: dict[str, object]) -> None:
        parts = topic.split("/")
        if len(parts) < 4:
            return

        mac = parts[2]
        message_type = parts[3]

        if message_type == "control" and mac in self.devices:
            self.handle_control_message(mac, payload)
            return

        if message_type == "status":
            self.log_message(f"Status echo from {mac}: {payload}")
            return

        if message_type == "sensor":
            self.log_message(f"Sensor echo from {mac}: {payload}")

    def handle_control_message(self, mac: str, payload: dict[str, object]) -> None:
        device = self.devices.get(mac)
        if device is None:
            return

        switches = device.get("switches", [])
        if not isinstance(switches, list):
            return

        try:
            switch_index = int(payload.get("switchIndex", 0))
        except Exception:
            return

        if switch_index < 0 or switch_index >= len(switches):
            return

        switch = switches[switch_index]
        if not isinstance(switch, dict):
            return

        switch_type = str(switch.get("type", payload.get("type", "toggle")))
        requested_on = bool(payload.get("isOn", False))
        requested_value = float(payload.get("value", switch.get("value", 0)))

        if switch_type == "toggle":
            switch["isOn"] = requested_on
            switch["value"] = 0.0
        elif switch_type == "fan":
            switch["value"] = clamp(step_value(requested_value, 1.0), 0.0, 5.0)
            switch["isOn"] = switch["value"] > 0
        elif switch_type == "dimmer":
            switch["value"] = clamp(step_value(requested_value, 1.0), 0.0, 100.0)
            switch["isOn"] = switch["value"] > 0
        elif switch_type == "curtain":
            switch["value"] = clamp(step_value(requested_value, 1.0), 0.0, 2.0)
            switch["isOn"] = int(switch["value"]) != 0
        elif switch_type == "scene":
            switch["value"] = 1.0
            switch["isOn"] = True
        else:
            switch["isOn"] = requested_on
            switch["value"] = requested_value

        self.refresh_device_list(selected_mac=mac)
        self.render_selected_device()
        self.publish_switch_status(mac, switch_index, source="MQTT")
        self.save_devices()

        if switch_type == "scene":
            self.root.after(SCENE_RESET_DELAY_MS, lambda: self._reset_scene(mac, switch_index, source="MQTT"))

    def start_heartbeat(self, mac: str) -> None:
        if mac in self.heartbeat_threads and self.heartbeat_threads[mac].is_alive():
            return

        self.stop_heartbeat_flags[mac] = False
        thread = threading.Thread(target=self.heartbeat_loop, args=(mac,), daemon=True)
        self.heartbeat_threads[mac] = thread
        thread.start()

    def stop_heartbeat(self, mac: str) -> None:
        self.stop_heartbeat_flags[mac] = True

    def heartbeat_loop(self, mac: str) -> None:
        while (
            not self.stop_heartbeat_flags.get(mac, False)
            and not self._shutting_down
        ):
            device = self.devices.get(mac)
            if not device or not bool(device.get("online", False)):
                break

            if self.connected and self.client is not None:
                payload = {
                    "timestamp": datetime.now().isoformat(),
                    "device_type": device.get("type", "unknown"),
                }
                topic = f"smarthome/{self.api_key}/{mac}/heartbeat"
                self.client.publish(topic, json.dumps(payload))
                self.log_message(f"Heartbeat sent: {mac}")

            time.sleep(self.heartbeat_interval)

    def _default_switch_value(self, switch_type: str) -> float:
        if switch_type == "fan":
            return 0.0
        if switch_type == "dimmer":
            return 0.0
        if switch_type == "curtain":
            return 0.0
        return 0.0

    def _normalize_switch(self, spec: dict[str, str], existing: dict[str, object] | None) -> dict[str, object]:
        switch_type = spec["type"]
        value = self._default_switch_value(switch_type)
        is_on = False

        if existing:
            try:
                value = float(existing.get("value", value))
            except Exception:
                value = self._default_switch_value(switch_type)
            is_on = bool(existing.get("isOn", False))

        if switch_type == "fan":
            value = clamp(step_value(value, 1.0), 0.0, 5.0)
            is_on = value > 0 if existing else False
        elif switch_type == "dimmer":
            value = clamp(step_value(value, 1.0), 0.0, 100.0)
            is_on = value > 0 if existing else False
        elif switch_type == "curtain":
            value = clamp(step_value(value, 1.0), 0.0, 2.0)
            is_on = int(value) != 0 if existing else False
        elif switch_type == "scene":
            value = 0.0
            is_on = False
        else:
            value = 0.0

        return {
            "label": str((existing or {}).get("label", spec["label"])),
            "type": switch_type,
            "isOn": is_on,
            "value": value,
        }

    def _make_sensor(self, sensor_type: str, existing: dict[str, object] | None = None) -> dict[str, object]:
        profile = SENSOR_CATALOG.get(sensor_type, {
            "label": humanize(sensor_type),
            "unit": "",
            "min": 0.0,
            "max": 100.0,
            "step": 1.0,
            "default": 0.0,
            "mode": "scale",
            "presets": [0.0, 50.0, 100.0],
        })

        raw_value = (existing or {}).get("value", profile["default"])
        try:
            value = float(raw_value)
        except Exception:
            value = float(profile["default"])

        minimum = float((existing or {}).get("min", profile["min"]))
        maximum = float((existing or {}).get("max", profile["max"]))
        step = float((existing or {}).get("step", profile["step"]))
        value = clamp(step_value(value, step), minimum, maximum)

        return {
            "type": sensor_type,
            "label": str((existing or {}).get("label", profile["label"])),
            "value": value,
            "unit": str((existing or {}).get("unit", profile["unit"])),
            "min": minimum,
            "max": maximum,
            "step": step,
        }

    def build_device(
        self,
        template_id: str,
        name: str,
        online: bool,
        sensor_types: list[str] | None = None,
    ) -> dict[str, object]:
        template = DEVICE_CATALOG[template_id]
        sensors = sensor_types if sensor_types is not None else list(template["default_sensors"])
        return {
            "name": name,
            "type": template_id,
            "online": online,
            "switches": [self._normalize_switch(spec, None) for spec in template["switches"]],
            "sensors": [self._make_sensor(sensor_type) for sensor_type in sensors],
        }

    def normalize_device(self, device: dict[str, object]) -> dict[str, object]:
        raw_type = str(device.get("type", "sw_1"))
        template_id = LEGACY_DEVICE_TYPES.get(raw_type, raw_type)
        if template_id not in DEVICE_CATALOG:
            template_id = "sw_1"

        template = DEVICE_CATALOG[template_id]
        raw_switches = device.get("switches", [])
        if not isinstance(raw_switches, list):
            raw_switches = []

        normalized_switches = []
        for index, spec in enumerate(template["switches"]):
            existing = raw_switches[index] if index < len(raw_switches) and isinstance(raw_switches[index], dict) else None
            normalized_switches.append(self._normalize_switch(spec, existing))

        raw_sensors = device.get("sensors", [])
        if not isinstance(raw_sensors, list):
            raw_sensors = []

        normalized_sensors = [
            self._make_sensor(str(sensor.get("type", "temperature")), sensor)
            for sensor in raw_sensors
            if isinstance(sensor, dict)
        ]

        return {
            "name": str(device.get("name", template["name"])),
            "type": template_id,
            "online": bool(device.get("online", False)),
            "switches": normalized_switches,
            "sensors": normalized_sensors,
        }

    def load_devices(self) -> None:
        if not DEVICES_FILE.exists():
            self.create_default_devices()
            return

        try:
            with DEVICES_FILE.open("r", encoding="utf-8") as file:
                data = json.load(file)
        except Exception as error:
            self.log_message(f"Failed to read devices.json: {error}")
            self.create_default_devices()
            return

        config = data.get("_config", {}) if isinstance(data, dict) else {}
        self.broker_host = str(config.get("broker_host", self.broker_host))
        self.broker_port = int(config.get("broker_port", self.broker_port))
        self.api_key = str(config.get("api_key", self.api_key))
        self.heartbeat_interval = int(config.get("heartbeat_interval", self.heartbeat_interval))

        loaded_devices: dict[str, dict[str, object]] = {}
        if isinstance(data, dict):
            for raw_mac, raw_device in data.items():
                if raw_mac == "_config" or not isinstance(raw_device, dict):
                    continue
                loaded_devices[normalize_mac(raw_mac)] = self.normalize_device(raw_device)

        self.devices = loaded_devices
        if not self.devices:
            self.create_default_devices()
            return

        self.save_devices()
        self.log_message(f"Loaded {len(self.devices)} devices from devices.json")

    def create_default_devices(self) -> None:
        demo_specs = [
            ("AA:BB:CC:DD:EE:01", "sw_1", "Entry Switch", True, []),
            ("AA:BB:CC:DD:EE:02", "sw_2", "Bedroom Switches", True, []),
            ("AA:BB:CC:DD:EE:03", "sw_4", "Kitchen Panel", True, ["power"]),
            ("AA:BB:CC:DD:EE:04", "sw_2_fan", "Master Bedroom Fan", True, ["temperature", "humidity"]),
            ("AA:BB:CC:DD:EE:05", "sw_4_fan", "Hall Fan Panel", False, ["temperature", "humidity", "power"]),
            ("AA:BB:CC:DD:EE:06", "sw_2_dim", "Living Room Dimmer", True, ["light-level", "motion"]),
            ("AA:BB:CC:DD:EE:07", "sw_4_dim", "Dining Dimmer Panel", True, ["light-level", "motion", "power"]),
            ("AA:BB:CC:DD:EE:08", "sw_6", "Study Panel", True, ["power", "voltage"]),
            ("AA:BB:CC:DD:EE:09", "curtain", "Curtain Controller", True, ["light-level", "contact"]),
            ("AA:BB:CC:DD:EE:0A", "scene_8", "Scene Panel", True, []),
        ]

        self.devices = {
            mac: self.build_device(template_id, name, online, sensors)
            for mac, template_id, name, online, sensors in demo_specs
        }
        self.save_devices()

    def save_devices(self) -> None:
        try:
            payload = {
                "_config": {
                    "broker_host": self.broker_host,
                    "broker_port": self.broker_port,
                    "api_key": self.api_key,
                    "heartbeat_interval": self.heartbeat_interval,
                }
            }
            payload.update(self.devices)
            with DEVICES_FILE.open("w", encoding="utf-8") as file:
                json.dump(payload, file, indent=2)
        except Exception as error:
            self.log_message(f"Failed to save devices: {error}")

    def refresh_device_list(self, selected_mac: str | None = None) -> None:
        if self.device_tree is None:
            return

        filter_value = self.search_var.get().strip().lower()
        current_selection = selected_mac or self.current_device_mac

        for item in self.device_tree.get_children():
            self.device_tree.delete(item)

        online_count = 0
        visible_devices: list[str] = []

        for mac, device in sorted(self.devices.items(), key=lambda item: str(item[1].get("name", item[0])).lower()):
            template_id = str(device.get("type", "sw_1"))
            template = DEVICE_CATALOG.get(template_id, DEVICE_CATALOG["sw_1"])
            name = str(device.get("name", mac))
            online = bool(device.get("online", False))
            switches = device.get("switches", [])
            sensors = device.get("sensors", [])

            haystack = f"{name} {template['name']} {mac}".lower()
            if filter_value and filter_value not in haystack:
                continue

            visible_devices.append(mac)
            if online:
                online_count += 1

            self.device_tree.insert(
                "",
                tk.END,
                iid=mac,
                text=name,
                values=(
                    template["name"],
                    len(switches) if isinstance(switches, list) else 0,
                    len(sensors) if isinstance(sensors, list) else 0,
                    "Online" if online else "Offline",
                    mac,
                ),
            )

        self.summary_var.set(f"{len(visible_devices)} shown. {online_count} online.")

        if not visible_devices:
            self.current_device_mac = None
            self.render_selected_device()
            return

        target = current_selection if current_selection in visible_devices else visible_devices[0]
        self.device_tree.selection_set(target)
        self.device_tree.focus(target)
        self.device_tree.see(target)
        self.current_device_mac = target
        self.render_selected_device()

    def load_demo_devices(self) -> None:
        if not messagebox.askyesno("Load demo devices", "Replace current simulator devices with full demo catalog?"):
            return

        self.create_default_devices()
        self.refresh_device_list()
        self.log_message("Loaded full demo device catalog")

        if self.connected:
            for mac in self.devices:
                self.register_device_topics(mac)
            self.publish_all_switch_statuses()

    def open_device_dialog(self) -> None:
        dialog = tk.Toplevel(self.root)
        dialog.title("Add Device")
        dialog.configure(bg=COLORS["panel"])
        dialog.geometry("640x560")
        dialog.transient(self.root)
        dialog.grab_set()

        container = tk.Frame(dialog, bg=COLORS["panel"], padx=18, pady=18)
        container.pack(fill="both", expand=True)
        container.columnconfigure(1, weight=1)
        container.rowconfigure(6, weight=1)

        name_var = tk.StringVar()
        mac_var = tk.StringVar()
        online_var = tk.BooleanVar(value=True)

        template_options = [f"{template_id} | {template['name']}" for template_id, template in DEVICE_CATALOG.items()]
        template_var = tk.StringVar(value=template_options[0])

        def current_template_id() -> str:
            return template_var.get().split(" | ", 1)[0]

        def add_row(row: int, label: str, widget: tk.Widget) -> None:
            tk.Label(
                container,
                text=label,
                bg=COLORS["panel"],
                fg=COLORS["muted"],
                font=("Segoe UI", 10, "bold"),
            ).grid(row=row, column=0, sticky="nw", padx=(0, 12), pady=8)
            widget.grid(row=row, column=1, sticky="ew", pady=8)

        add_row(
            0,
            "Device Name",
            tk.Entry(
                container,
                textvariable=name_var,
                bg=COLORS["surface"],
                fg=COLORS["text"],
                relief="flat",
                highlightbackground=COLORS["border"],
                highlightthickness=1,
                font=("Segoe UI", 10),
            ),
        )
        add_row(
            1,
            "MAC Address",
            tk.Entry(
                container,
                textvariable=mac_var,
                bg=COLORS["surface"],
                fg=COLORS["text"],
                relief="flat",
                highlightbackground=COLORS["border"],
                highlightthickness=1,
                font=("Segoe UI", 10),
            ),
        )

        template_combo = ttk.Combobox(container, textvariable=template_var, values=template_options, state="readonly")
        add_row(2, "Template", template_combo)

        online_wrap = tk.Frame(container, bg=COLORS["panel"])
        tk.Checkbutton(
            online_wrap,
            text="Start online",
            variable=online_var,
            bg=COLORS["panel"],
            fg=COLORS["text"],
            activebackground=COLORS["panel"],
            font=("Segoe UI", 10),
        ).pack(anchor="w")
        add_row(3, "Status", online_wrap)

        sensor_list = tk.Listbox(
            container,
            selectmode=tk.MULTIPLE,
            exportselection=False,
            bg=COLORS["surface"],
            fg=COLORS["text"],
            relief="flat",
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            height=8,
            font=("Segoe UI", 10),
        )
        sensor_types = list(SENSOR_CATALOG.keys())
        for sensor_type in sensor_types:
            sensor_list.insert(tk.END, f"{sensor_type} | {SENSOR_CATALOG[sensor_type]['label']}")
        add_row(4, "Sensors", sensor_list)

        preview_card = tk.Frame(
            container,
            bg=COLORS["surface"],
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            padx=14,
            pady=14,
        )
        preview_card.grid(row=5, column=0, columnspan=2, sticky="ew", pady=(10, 0))

        tk.Label(
            preview_card,
            text="Template Preview",
            bg=COLORS["surface"],
            fg=COLORS["text"],
            font=("Segoe UI", 11, "bold"),
        ).pack(anchor="w")
        preview_text = tk.Label(
            preview_card,
            bg=COLORS["surface"],
            fg=COLORS["muted"],
            justify="left",
            anchor="w",
            font=("Segoe UI", 10),
        )
        preview_text.pack(anchor="w", pady=(8, 0))

        button_row = tk.Frame(container, bg=COLORS["panel"])
        button_row.grid(row=7, column=0, columnspan=2, sticky="e", pady=(16, 0))

        def apply_default_sensor_selection() -> None:
            sensor_list.selection_clear(0, tk.END)
            defaults = DEVICE_CATALOG[current_template_id()]["default_sensors"]
            for index, sensor_type in enumerate(sensor_types):
                if sensor_type in defaults:
                    sensor_list.selection_set(index)

        def update_preview(*_) -> None:
            template = DEVICE_CATALOG[current_template_id()]
            controls = ", ".join(spec["label"] for spec in template["switches"])
            sensors = ", ".join(template["default_sensors"]) or "None"
            preview_text.configure(
                text=(
                    f"Controls: {len(template['switches'])}\n"
                    f"Names: {controls}\n"
                    f"Default sensors: {sensors}"
                )
            )

        def create_device() -> None:
            name = name_var.get().strip()
            mac = normalize_mac(mac_var.get().strip())
            template_id = current_template_id()

            if not name:
                messagebox.showerror("Invalid device", "Device name is required.")
                return
            if not is_valid_mac(mac):
                messagebox.showerror("Invalid device", "MAC address is invalid.")
                return
            if mac in self.devices:
                messagebox.showerror("Invalid device", "Device MAC already exists.")
                return

            selected_sensor_types = [sensor_types[index] for index in sensor_list.curselection()]
            self.devices[mac] = self.build_device(template_id, name, online_var.get(), selected_sensor_types)
            self.save_devices()
            self.refresh_device_list(selected_mac=mac)
            self.log_message(f"Added device: {name} ({template_id})")

            if self.connected:
                self.register_device_topics(mac)
                if online_var.get():
                    self.start_heartbeat(mac)
                    self.publish_all_switch_statuses(mac)

            dialog.destroy()

        self._make_button(button_row, "Cancel", dialog.destroy, variant="secondary", width=12).pack(side="left", padx=6)
        self._make_button(button_row, "Add Device", create_device, variant="accent", width=12).pack(side="left")

        template_combo.bind("<<ComboboxSelected>>", lambda event: (apply_default_sensor_selection(), update_preview()))
        apply_default_sensor_selection()
        update_preview()

    def open_sensor_dialog(self) -> None:
        mac = self.current_device_mac
        if mac is None or mac not in self.devices:
            messagebox.showwarning("Select device", "Select a device first.")
            return

        dialog = tk.Toplevel(self.root)
        dialog.title("Add Sensor")
        dialog.configure(bg=COLORS["panel"])
        dialog.geometry("460x260")
        dialog.transient(self.root)
        dialog.grab_set()

        container = tk.Frame(dialog, bg=COLORS["panel"], padx=18, pady=18)
        container.pack(fill="both", expand=True)
        container.columnconfigure(1, weight=1)

        sensor_options = [f"{sensor_type} | {profile['label']}" for sensor_type, profile in SENSOR_CATALOG.items()]
        sensor_var = tk.StringVar(value=sensor_options[0])
        label_var = tk.StringVar()

        tk.Label(container, text="Sensor Type", bg=COLORS["panel"], fg=COLORS["muted"], font=("Segoe UI", 10, "bold")).grid(row=0, column=0, sticky="w", pady=8)
        ttk.Combobox(container, textvariable=sensor_var, values=sensor_options, state="readonly").grid(row=0, column=1, sticky="ew", pady=8)

        tk.Label(container, text="Custom Label", bg=COLORS["panel"], fg=COLORS["muted"], font=("Segoe UI", 10, "bold")).grid(row=1, column=0, sticky="w", pady=8)
        tk.Entry(
            container,
            textvariable=label_var,
            bg=COLORS["surface"],
            fg=COLORS["text"],
            relief="flat",
            highlightbackground=COLORS["border"],
            highlightthickness=1,
            font=("Segoe UI", 10),
        ).grid(row=1, column=1, sticky="ew", pady=8)

        def add_sensor() -> None:
            sensor_type = sensor_var.get().split(" | ", 1)[0]
            sensor = self._make_sensor(sensor_type)
            if label_var.get().strip():
                sensor["label"] = label_var.get().strip()
            self.devices[mac].setdefault("sensors", []).append(sensor)
            self.save_devices()
            self.refresh_device_list(selected_mac=mac)
            self.render_selected_device()
            self.publish_sensor_state(mac, len(self.devices[mac]["sensors"]) - 1)
            self.log_message(f"Added sensor {sensor['label']} to {mac}")
            dialog.destroy()

        button_row = tk.Frame(container, bg=COLORS["panel"])
        button_row.grid(row=2, column=0, columnspan=2, sticky="e", pady=(16, 0))
        self._make_button(button_row, "Cancel", dialog.destroy, variant="secondary", width=12).pack(side="left", padx=6)
        self._make_button(button_row, "Add Sensor", add_sensor, variant="accent", width=12).pack(side="left")

    def remove_device(self) -> None:
        mac = self.current_device_mac
        if mac is None or mac not in self.devices:
            messagebox.showwarning("Select device", "Select a device first.")
            return

        name = self.devices[mac].get("name", mac)
        if not messagebox.askyesno("Remove device", f"Remove {name}?"):
            return

        self.stop_heartbeat(mac)
        del self.devices[mac]
        self.save_devices()
        self.refresh_device_list()
        self.log_message(f"Removed device: {mac}")

    def toggle_device_online(self) -> None:
        mac = self.current_device_mac
        if mac is None or mac not in self.devices:
            messagebox.showwarning("Select device", "Select a device first.")
            return

        device = self.devices[mac]
        device["online"] = not bool(device.get("online", False))

        if bool(device["online"]):
            self.start_heartbeat(mac)
            self.log_message(f"Device online: {mac}")
            if self.connected:
                self.publish_all_switch_statuses(mac)
        else:
            self.stop_heartbeat(mac)
            self.log_message(f"Device offline: {mac}")

        self.save_devices()
        self.refresh_device_list(selected_mac=mac)

    def on_device_select(self, event=None) -> None:
        if self.device_tree is None:
            return
        selection = self.device_tree.selection()
        if not selection:
            return
        self.current_device_mac = selection[0]
        self.render_selected_device()

    def render_selected_device(self) -> None:
        mac = self.current_device_mac
        if mac is None or mac not in self.devices:
            self.detail_title_var.set("No device selected")
            for label in self.info_value_labels.values():
                label.configure(text="-")
            if self.feature_chips_frame is not None:
                clear_children(self.feature_chips_frame)
            if self.switches_frame is not None:
                clear_children(self.switches_frame)
            if self.sensors_frame is not None:
                clear_children(self.sensors_frame)
            return

        device = self.devices[mac]
        self.detail_title_var.set(str(device.get("name", mac)))
        self.update_overview(device, mac)
        self.update_switches_controls(device, mac)
        self.update_sensors_controls(device, mac)

    def update_overview(self, device: dict[str, object], mac: str) -> None:
        template_id = str(device.get("type", "sw_1"))
        template = DEVICE_CATALOG.get(template_id, DEVICE_CATALOG["sw_1"])
        sensors = device.get("sensors", [])
        switches = device.get("switches", [])
        topic_base = f"smarthome/{self.api_key}/{mac}"

        values = {
            "Template": template["name"],
            "MAC": mac,
            "Online": "Online" if bool(device.get("online", False)) else "Offline",
            "Switches": str(len(switches) if isinstance(switches, list) else 0),
            "Sensors": str(len(sensors) if isinstance(sensors, list) else 0),
            "Topic Base": topic_base,
        }
        for key, value in values.items():
            self.info_value_labels[key].configure(text=value)

        if self.feature_chips_frame is None:
            return

        clear_children(self.feature_chips_frame)
        feature_values = []
        if isinstance(switches, list):
            feature_values.extend({humanize(str(switch.get("type", "toggle"))) for switch in switches if isinstance(switch, dict)})
        if isinstance(sensors, list):
            feature_values.extend({humanize(str(sensor.get("type", "sensor"))) for sensor in sensors if isinstance(sensor, dict)})

        if not feature_values:
            tk.Label(
                self.feature_chips_frame,
                text="No extra features",
                bg=COLORS["surface"],
                fg=COLORS["muted"],
                font=("Segoe UI", 10),
            ).pack(anchor="w")
            return

        for index, feature in enumerate(sorted(set(feature_values))):
            chip = tk.Label(
                self.feature_chips_frame,
                text=feature,
                bg=COLORS["accent_soft"],
                fg=COLORS["accent"],
                font=("Segoe UI", 10, "bold"),
                padx=10,
                pady=6,
            )
            chip.grid(row=index // 4, column=index % 4, padx=4, pady=4, sticky="w")

    def update_switches_controls(self, device: dict[str, object], mac: str) -> None:
        if self.switches_frame is None:
            return

        clear_children(self.switches_frame)
        switches = device.get("switches", [])
        if not isinstance(switches, list) or not switches:
            tk.Label(
                self.switches_frame,
                text="No controls available.",
                bg=COLORS["panel"],
                fg=COLORS["muted"],
                font=("Segoe UI", 11),
            ).pack(anchor="w")
            return

        header = tk.Frame(self.switches_frame, bg=COLORS["panel"])
        header.pack(fill="x", pady=(0, 10))

        status_text = "Live controls" if bool(device.get("online", False)) else "Offline device"
        tk.Label(
            header,
            text=f"{len(switches)} control channels",
            bg=COLORS["panel"],
            fg=COLORS["text"],
            font=("Segoe UI", 12, "bold"),
        ).pack(side="left")
        tk.Label(
            header,
            text=status_text,
            bg=COLORS["panel"],
            fg=COLORS["success"] if bool(device.get("online", False)) else COLORS["danger"],
            font=("Segoe UI", 10, "bold"),
        ).pack(side="left", padx=(10, 0))

        self._make_button(
            header,
            "Broadcast States",
            lambda: self.publish_all_switch_statuses(mac),
            variant="secondary",
            width=14,
        ).pack(side="right")

        grid = tk.Frame(self.switches_frame, bg=COLORS["panel"])
        grid.pack(fill="both", expand=True)
        grid.columnconfigure(0, weight=1)
        grid.columnconfigure(1, weight=1)

        for index, switch in enumerate(switches):
            card = tk.Frame(
                grid,
                bg=COLORS["surface"],
                highlightbackground=COLORS["border"],
                highlightthickness=1,
                padx=16,
                pady=16,
            )
            card.grid(row=index // 2, column=index % 2, sticky="nsew", padx=6, pady=6)
            self._render_switch_card(card, mac, index, switch, bool(device.get("online", False)))

    def _render_switch_card(
        self,
        card: tk.Frame,
        mac: str,
        switch_index: int,
        switch: dict[str, object],
        is_online: bool,
    ) -> None:
        switch_type = str(switch.get("type", "toggle"))
        label = str(switch.get("label", f"Switch {switch_index + 1}"))
        is_on = bool(switch.get("isOn", False))
        value = float(switch.get("value", 0.0))

        tk.Label(card, text=label, bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 12, "bold")).pack(anchor="w")
        tk.Label(card, text=humanize(switch_type), bg=COLORS["surface"], fg=COLORS["muted"], font=("Segoe UI", 9, "bold")).pack(anchor="w", pady=(2, 10))

        if switch_type == "toggle":
            state_text = "ON" if is_on else "OFF"
            tk.Label(card, text=f"State: {state_text}", bg=COLORS["surface"], fg=COLORS["success"] if is_on else COLORS["muted"], font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 8))
            button_row = tk.Frame(card, bg=COLORS["surface"])
            button_row.pack(anchor="w")
            self._make_option_button(button_row, "OFF", lambda: self.set_switch_state(mac, switch_index, is_on=False, value=0.0), selected=not is_on, disabled=not is_online, width=8).pack(side="left", padx=(0, 6))
            self._make_option_button(button_row, "ON", lambda: self.set_switch_state(mac, switch_index, is_on=True, value=0.0), selected=is_on, disabled=not is_online, width=8).pack(side="left")
            return

        if switch_type == "fan":
            tk.Label(card, text=f"Speed: {int(value)}", bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 8))
            button_row = tk.Frame(card, bg=COLORS["surface"])
            button_row.pack(anchor="w")
            for speed in range(6):
                self._make_option_button(
                    button_row,
                    str(speed),
                    lambda new_speed=speed: self.set_switch_state(mac, switch_index, value=float(new_speed)),
                    selected=int(value) == speed,
                    disabled=not is_online,
                    width=4,
                ).pack(side="left", padx=3)
            return

        if switch_type == "dimmer":
            value_var = tk.StringVar(value=f"Brightness: {int(value)}%")
            tk.Label(card, textvariable=value_var, bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 8))

            slider = tk.Scale(
                card,
                from_=0,
                to=100,
                orient="horizontal",
                resolution=1,
                bg=COLORS["surface"],
                fg=COLORS["text"],
                troughcolor=COLORS["surface_alt"],
                activebackground=COLORS["accent"],
                highlightthickness=0,
                length=260,
                state=tk.NORMAL if is_online else tk.DISABLED,
            )
            slider.set(value)
            slider.configure(command=lambda raw: value_var.set(f"Brightness: {int(float(raw))}%"))
            slider.pack(anchor="w")
            slider.bind(
                "<ButtonRelease-1>",
                lambda event: self.set_switch_state(mac, switch_index, value=float(slider.get())),
            )

            preset_row = tk.Frame(card, bg=COLORS["surface"])
            preset_row.pack(anchor="w", pady=(10, 0))
            for preset in [0, 25, 50, 75, 100]:
                self._make_option_button(
                    preset_row,
                    f"{preset}%",
                    lambda level=preset: self.set_switch_state(mac, switch_index, value=float(level)),
                    selected=int(value) == preset,
                    disabled=not is_online,
                    width=6,
                ).pack(side="left", padx=3)
            return

        if switch_type == "curtain":
            tk.Label(card, text=f"Position: {CURTAIN_LABELS.get(int(value), 'Unknown')}", bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 8))
            button_row = tk.Frame(card, bg=COLORS["surface"])
            button_row.pack(anchor="w")
            options = [(0, "Close"), (1, "Pause"), (2, "Open")]
            for curtain_value, title in options:
                self._make_option_button(
                    button_row,
                    title,
                    lambda next_value=curtain_value: self.set_switch_state(mac, switch_index, value=float(next_value)),
                    selected=int(value) == curtain_value,
                    disabled=not is_online,
                    width=8,
                ).pack(side="left", padx=3)
            return

        if switch_type == "scene":
            tk.Label(card, text="Momentary scene trigger", bg=COLORS["surface"], fg=COLORS["muted"], font=("Segoe UI", 10)).pack(anchor="w", pady=(0, 8))
            self._make_button(
                card,
                "Trigger Scene",
                lambda: self.trigger_scene(mac, switch_index),
                variant="accent",
                width=14,
                state=tk.NORMAL if is_online else tk.DISABLED,
            ).pack(anchor="w")
            return

        tk.Label(card, text="Unsupported control", bg=COLORS["surface"], fg=COLORS["danger"], font=("Segoe UI", 10, "bold")).pack(anchor="w")

    def update_sensors_controls(self, device: dict[str, object], mac: str) -> None:
        if self.sensors_frame is None:
            return

        clear_children(self.sensors_frame)
        sensors = device.get("sensors", [])
        header = tk.Frame(self.sensors_frame, bg=COLORS["panel"])
        header.pack(fill="x", pady=(0, 10))

        tk.Label(
            header,
            text=f"{len(sensors) if isinstance(sensors, list) else 0} sensors",
            bg=COLORS["panel"],
            fg=COLORS["text"],
            font=("Segoe UI", 12, "bold"),
        ).pack(side="left")

        self._make_button(header, "Add Sensor", self.open_sensor_dialog, variant="secondary", width=12).pack(side="right")

        if not isinstance(sensors, list) or not sensors:
            tk.Label(
                self.sensors_frame,
                text="No sensors configured for this device.",
                bg=COLORS["panel"],
                fg=COLORS["muted"],
                font=("Segoe UI", 11),
            ).pack(anchor="w")
            return

        grid = tk.Frame(self.sensors_frame, bg=COLORS["panel"])
        grid.pack(fill="both", expand=True)
        grid.columnconfigure(0, weight=1)
        grid.columnconfigure(1, weight=1)

        for index, sensor in enumerate(sensors):
            card = tk.Frame(
                grid,
                bg=COLORS["surface"],
                highlightbackground=COLORS["border"],
                highlightthickness=1,
                padx=16,
                pady=16,
            )
            card.grid(row=index // 2, column=index % 2, sticky="nsew", padx=6, pady=6)
            self._render_sensor_card(card, mac, index, sensor)

    def _render_sensor_card(self, card: tk.Frame, mac: str, sensor_index: int, sensor: dict[str, object]) -> None:
        sensor_type = str(sensor.get("type", "sensor"))
        profile = SENSOR_CATALOG.get(sensor_type, {"mode": "scale", "states": {0: "Off", 1: "On"}, "presets": []})
        label = str(sensor.get("label", humanize(sensor_type)))
        value = float(sensor.get("value", 0.0))
        unit = str(sensor.get("unit", ""))
        minimum = float(sensor.get("min", 0.0))
        maximum = float(sensor.get("max", 100.0))
        step = float(sensor.get("step", 1.0))
        mode = str(profile.get("mode", "scale"))

        header_row = tk.Frame(card, bg=COLORS["surface"])
        header_row.pack(fill="x")

        tk.Label(header_row, text=label, bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 12, "bold")).pack(side="left")
        self._make_button(header_row, "Remove", lambda: self.remove_sensor(mac, sensor_index), variant="danger", width=8).pack(side="right")

        tk.Label(card, text=humanize(sensor_type), bg=COLORS["surface"], fg=COLORS["muted"], font=("Segoe UI", 9, "bold")).pack(anchor="w", pady=(2, 8))

        if mode == "binary":
            states = profile.get("states", {0: "Off", 1: "On"})
            state_row = tk.Frame(card, bg=COLORS["surface"])
            state_row.pack(anchor="w")
            for raw_state, title in states.items():
                self._make_option_button(
                    state_row,
                    title,
                    lambda next_state=raw_state: self.update_sensor_value(mac, sensor_index, float(next_state)),
                    selected=int(value) == int(raw_state),
                    width=10,
                ).pack(side="left", padx=3)
            return

        value_var = tk.StringVar(value=f"Value: {self._format_numeric(value)}{unit}")
        tk.Label(card, textvariable=value_var, bg=COLORS["surface"], fg=COLORS["text"], font=("Segoe UI", 10, "bold")).pack(anchor="w", pady=(0, 8))

        slider = tk.Scale(
            card,
            from_=minimum,
            to=maximum,
            orient="horizontal",
            resolution=step,
            bg=COLORS["surface"],
            fg=COLORS["text"],
            troughcolor=COLORS["surface_alt"],
            activebackground=COLORS["accent"],
            highlightthickness=0,
            length=260,
        )
        slider.set(value)
        slider.configure(command=lambda raw: value_var.set(f"Value: {self._format_numeric(float(raw))}{unit}"))
        slider.pack(anchor="w")
        slider.bind(
            "<ButtonRelease-1>",
            lambda event: self.update_sensor_value(mac, sensor_index, float(slider.get())),
        )

        preset_row = tk.Frame(card, bg=COLORS["surface"])
        preset_row.pack(anchor="w", pady=(10, 0))
        presets = profile.get("presets", [])
        if not presets:
            presets = [minimum, (minimum + maximum) / 2, maximum]

        for preset in presets:
            display = self._format_numeric(float(preset))
            self._make_option_button(
                preset_row,
                f"{display}{unit}",
                lambda next_value=float(preset): self.update_sensor_value(mac, sensor_index, next_value),
                selected=abs(value - float(preset)) < max(step, 0.5),
                width=8,
            ).pack(side="left", padx=3)

    def _format_numeric(self, value: float) -> str:
        if abs(value - int(value)) < 0.001:
            return str(int(value))
        return f"{value:.1f}".rstrip("0").rstrip(".")

    def set_switch_state(
        self,
        mac: str,
        switch_index: int,
        *,
        is_on: bool | None = None,
        value: float | None = None,
        source: str = "Local",
    ) -> None:
        if mac not in self.devices:
            return

        device = self.devices[mac]
        if not bool(device.get("online", False)):
            messagebox.showwarning("Offline device", "Device is offline.")
            return

        switches = device.get("switches", [])
        if not isinstance(switches, list) or switch_index >= len(switches):
            return

        switch = switches[switch_index]
        if not isinstance(switch, dict):
            return

        switch_type = str(switch.get("type", "toggle"))

        if switch_type == "toggle":
            switch["isOn"] = bool(is_on)
            switch["value"] = 0.0
        elif switch_type == "fan":
            next_value = clamp(step_value(value if value is not None else switch.get("value", 0.0), 1.0), 0.0, 5.0)
            switch["value"] = next_value
            switch["isOn"] = next_value > 0
        elif switch_type == "dimmer":
            next_value = clamp(step_value(value if value is not None else switch.get("value", 0.0), 1.0), 0.0, 100.0)
            switch["value"] = next_value
            switch["isOn"] = next_value > 0
        elif switch_type == "curtain":
            next_value = clamp(step_value(value if value is not None else switch.get("value", 0.0), 1.0), 0.0, 2.0)
            switch["value"] = next_value
            switch["isOn"] = int(next_value) != 0
        elif switch_type == "scene":
            switch["value"] = 1.0
            switch["isOn"] = True
        else:
            switch["isOn"] = bool(is_on)
            if value is not None:
                switch["value"] = value

        self.save_devices()
        self.refresh_device_list(selected_mac=mac)
        self.publish_switch_status(mac, switch_index, source=source)

        if switch_type == "scene":
            self.root.after(SCENE_RESET_DELAY_MS, lambda: self._reset_scene(mac, switch_index, source=source))

    def trigger_scene(self, mac: str, switch_index: int) -> None:
        self.set_switch_state(mac, switch_index, value=1.0, source="Local")

    def _reset_scene(self, mac: str, switch_index: int, source: str) -> None:
        if mac not in self.devices:
            return
        switches = self.devices[mac].get("switches", [])
        if not isinstance(switches, list) or switch_index >= len(switches):
            return
        switch = switches[switch_index]
        if not isinstance(switch, dict):
            return
        switch["isOn"] = False
        switch["value"] = 0.0
        self.save_devices()
        self.refresh_device_list(selected_mac=mac)
        self.publish_switch_status(mac, switch_index, source=source)

    def publish_switch_status(self, mac: str, switch_index: int, source: str = "Local") -> None:
        if not self.connected or self.client is None or mac not in self.devices:
            return

        switches = self.devices[mac].get("switches", [])
        if not isinstance(switches, list) or switch_index >= len(switches):
            return

        switch = switches[switch_index]
        if not isinstance(switch, dict):
            return

        payload = {
            "switchIndex": switch_index,
            "isOn": bool(switch.get("isOn", False)),
            "value": float(switch.get("value", 0.0)),
            "type": str(switch.get("type", "toggle")),
        }
        topic = f"smarthome/{self.api_key}/{mac}/status"
        self.client.publish(topic, json.dumps(payload))
        self.log_message(f"{source} status: {mac} #{switch_index} -> {payload}")

    def publish_all_switch_statuses(self, mac: str | None = None) -> None:
        if not self.connected or self.client is None:
            self.log_message("Status broadcast skipped: broker offline")
            return

        devices = [mac] if mac else list(self.devices.keys())
        sent = 0
        for device_mac in devices:
            device = self.devices.get(device_mac)
            if device is None or not bool(device.get("online", False)):
                continue
            switches = device.get("switches", [])
            if not isinstance(switches, list):
                continue
            for switch_index in range(len(switches)):
                self.publish_switch_status(device_mac, switch_index, source="Snapshot")
                sent += 1
        self.log_message(f"Broadcasted {sent} switch states")

    def update_sensor_value(self, mac: str, sensor_index: int, value: float) -> None:
        if mac not in self.devices:
            return

        sensors = self.devices[mac].get("sensors", [])
        if not isinstance(sensors, list) or sensor_index >= len(sensors):
            return

        sensor = sensors[sensor_index]
        if not isinstance(sensor, dict):
            return

        minimum = float(sensor.get("min", 0.0))
        maximum = float(sensor.get("max", 100.0))
        step = float(sensor.get("step", 1.0))
        sensor["value"] = clamp(step_value(value, step), minimum, maximum)

        self.save_devices()
        self.refresh_device_list(selected_mac=mac)
        self.publish_sensor_state(mac, sensor_index)

    def publish_sensor_state(self, mac: str, sensor_index: int) -> None:
        if not self.connected or self.client is None or mac not in self.devices:
            return

        sensors = self.devices[mac].get("sensors", [])
        if not isinstance(sensors, list) or sensor_index >= len(sensors):
            return

        sensor = sensors[sensor_index]
        if not isinstance(sensor, dict):
            return

        payload = {
            "sensorIndex": sensor_index,
            "type": str(sensor.get("type", "sensor")),
            "label": str(sensor.get("label", humanize(str(sensor.get("type", "sensor"))))),
            "value": float(sensor.get("value", 0.0)),
            "unit": str(sensor.get("unit", "")),
        }
        topic = f"smarthome/{self.api_key}/{mac}/sensor"
        self.client.publish(topic, json.dumps(payload))
        self.log_message(f"Sensor update: {mac} #{sensor_index} -> {payload}")

    def remove_sensor(self, mac: str, sensor_index: int) -> None:
        if mac not in self.devices:
            return

        sensors = self.devices[mac].get("sensors", [])
        if not isinstance(sensors, list) or sensor_index >= len(sensors):
            return

        removed = sensors.pop(sensor_index)
        self.save_devices()
        self.refresh_device_list(selected_mac=mac)
        self.log_message(f"Removed sensor: {removed.get('label', removed.get('type', 'sensor'))}")

    def clear_logs(self) -> None:
        if self.log_text is None:
            return
        self.log_text.delete("1.0", tk.END)

    def on_close(self) -> None:
        self._shutting_down = True
        for mac in list(self.stop_heartbeat_flags.keys()):
            self.stop_heartbeat(mac)
        self.disconnect_mqtt(log=False)
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    DeviceSimulator(root)
    root.mainloop()


if __name__ == "__main__":
    main()