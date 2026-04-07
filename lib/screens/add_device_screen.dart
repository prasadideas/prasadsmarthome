import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/device_template.dart';
import '../models/device_model.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../services/firestore_service.dart';

class AddDeviceScreen extends StatefulWidget {
  final HomeModel home;
  final RoomModel? room;

  const AddDeviceScreen({super.key, required this.home, this.room});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  DeviceTemplate? _selectedTemplate;
  int _step = 1;

  late List<_EditableSwitch> _editableSwitches;
  late List<_EditableSensor> _editableSensors;
  final _deviceNameController = TextEditingController();
  final _macIdController = TextEditingController();
  bool _assignToRoom = false;
  bool _saving = false;
  final List<SensorTemplate> _sensorTemplates =
      SensorTemplateCatalog.generalSensors;

  final List<Map<String, dynamic>> _switchIcons = [
    {'icon': Icons.lightbulb_outline, 'label': 'Light'},
    {'icon': Icons.air, 'label': 'Fan'},
    {'icon': Icons.tv, 'label': 'TV'},
    {'icon': Icons.ac_unit, 'label': 'AC'},
    {'icon': Icons.kitchen, 'label': 'Kitchen'},
    {'icon': Icons.power, 'label': 'Power'},
    {'icon': Icons.wb_sunny_outlined, 'label': 'Lamp'},
    {'icon': Icons.computer, 'label': 'Computer'},
    {'icon': Icons.speaker, 'label': 'Speaker'},
    {'icon': Icons.iron, 'label': 'Iron'},
    {'icon': Icons.hot_tub, 'label': 'Geyser'},
    {'icon': Icons.local_laundry_service, 'label': 'Washer'},
    {'icon': Icons.curtains, 'label': 'Curtain'},
    {'icon': Icons.garage, 'label': 'Garage'},
    {'icon': Icons.outdoor_grill, 'label': 'Outdoor'},
    {'icon': Icons.bathroom, 'label': 'Bathroom'},
  ];

  late final List<Map<String, dynamic>> _sensorIcons = _sensorTemplates
      .map((sensor) => {'icon': sensor.icon, 'label': sensor.label})
      .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_syncTemplates());
  }

  Future<void> _syncTemplates() async {
    try {
      await _firestoreService.syncDeviceTemplates();
    } catch (_) {}
  }

  void _selectTemplate(DeviceTemplate template) {
    setState(() {
      _selectedTemplate = template;
      _deviceNameController.text = template.name;
      _assignToRoom = widget.room != null;
      _editableSwitches = template.switches
          .map(
            (s) => _EditableSwitch(
              switchId: s.switchId,
              label: s.label,
              type: s.type,
              icon: s.icon,
            ),
          )
          .toList();
      _editableSensors = template.sensors
          .map((sensor) => _EditableSensor.fromTemplate(sensor))
          .toList();
      _step = 2;
    });
  }

  Future<void> _saveDevice() async {
    if (_deviceNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name')),
      );
      return;
    }

    if (_macIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MAC ID is required for MQTT communication'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final switches = _editableSwitches
        .map(
          (s) => SwitchModel(
            switchId: s.switchId,
            label: s.label,
            isOn: false,
            type: s.type.name,
            icon: s.icon.codePoint.toString(),
            value: 0,
          ),
        )
        .toList();

    final sensors = _editableSensors
        .map(
          (sensor) => SensorModel(
            sensorId: sensor.sensorId,
            label: sensor.label,
            type: sensor.type,
            unit: sensor.unit,
            icon: sensor.icon.codePoint.toString(),
            value: sensor.defaultValue,
            minValue: sensor.minValue,
            maxValue: sensor.maxValue,
            step: sensor.step,
          ),
        )
        .toList();

    final roomRef = (_assignToRoom && widget.room != null)
        ? widget.room!.roomId
        : null;
    final homeRef = (_assignToRoom && widget.room != null)
        ? widget.home.homeId
        : null;

    final deviceId = await _firestoreService.addDevice(
      uid,
      DeviceModel(
        deviceId: '',
        deviceName: _deviceNameController.text.trim(),
        type: _selectedTemplate!.templateId,
        isOnline: false,
        ownedBy: uid,
        switches: switches,
        sensors: sensors,
        linkedRoom: roomRef,
        linkedHome: homeRef,
        macId: _macIdController.text.trim().isNotEmpty
            ? _macIdController.text.trim()
            : null,
      ),
    );

    if (_assignToRoom && widget.room != null) {
      await _firestoreService.addDeviceRefToRoom(
        uid,
        widget.home.homeId,
        widget.room!.roomId,
        deviceId,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _macIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? 'Select device type' : 'Configure device'),
        leading: _step == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = 1),
              )
            : null,
      ),
      body: _step == 1 ? _buildStep1() : _buildStep2(),
    );
  }

  // ── Step 1: Template picker ────────────────────────────────

  Widget _buildStep1() {
    return StreamBuilder<List<DeviceTemplate>>(
      stream: _firestoreService.streamDeviceTemplates(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading templates: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No device types available',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  'Contact admin to add device templates',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final templates = snapshot.data!;
        final categories = templates.map((t) => t.category).toSet().toList();
        final cs = Theme.of(context).colorScheme;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: categories.map((cat) {
            final catTemplates = templates
                .where((t) => t.category == cat)
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: catTemplates.length,
                  itemBuilder: (context, i) {
                    final t = catTemplates[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selectTemplate(t),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                          color: cs.surface,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(t.icon, size: 28, color: cs.primary),
                            const Spacer(),
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t.switches.length} controls • ${t.sensors.length} sensors',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  // ── Step 2: Configure switches ─────────────────────────────

  Widget _buildStep2() {
    final cs = Theme.of(context).colorScheme;
    final selectedSensorTypes = _editableSensors
        .map((sensor) => sensor.type)
        .toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Device name
        TextFormField(
          controller: _deviceNameController,
          decoration: const InputDecoration(
            labelText: 'Device name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // MAC ID
        TextFormField(
          controller: _macIdController,
          decoration: const InputDecoration(
            labelText: 'MAC ID (e.g., 00:1A:2B:3C:4D:5E)',
            hintText: 'Enter device MAC address',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),

        // Assign to room toggle
        if (widget.room != null)
          Card(
            child: SwitchListTile(
              value: _assignToRoom,
              onChanged: (v) => setState(() => _assignToRoom = v),
              title: Text('Add to ${widget.room!.roomName}'),
              secondary: const Icon(Icons.meeting_room_outlined),
            ),
          ),

        const SizedBox(height: 16),

        const Text(
          'Configure switches',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a toggle/dimmer switch to rename or change icon',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.5)),
        ),
        const SizedBox(height: 12),

        // Render each switch preview
        if (_editableSwitches.isEmpty)
          Card(
            child: ListTile(
              leading: Icon(Icons.toggle_off, color: cs.onSurfaceVariant),
              title: const Text('No switch controls in this template'),
              subtitle: const Text(
                'This device can work as a sensor-only node.',
              ),
            ),
          )
        else
          ..._editableSwitches.asMap().entries.map((entry) {
            final i = entry.key;
            final sw = entry.value;

            final isFan = sw.type == SwitchType.fan;
            final isDimmer = sw.type == SwitchType.dimmer;

            if (isFan) {
              return _FanSwitchPreview(sw: sw, index: i, cs: cs);
            }

            if (isDimmer) {
              return _DimmerSwitchPreview(sw: sw, index: i, cs: cs);
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _switchTypeColor(sw.type).withOpacity(0.15),
                  child: Icon(
                    sw.icon,
                    color: _switchTypeColor(sw.type),
                    size: 20,
                  ),
                ),
                title: Text(
                  sw.label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  sw.type.name[0].toUpperCase() + sw.type.name.substring(1),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
                trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
                onTap: () => _showEditSwitchDialog(i),
              ),
            );
          }),

        const SizedBox(height: 16),

        const Text(
          'Configure sensors',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap sensor chips to add or remove. Tap sensor card to rename or change icon.',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.5)),
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _sensorTemplates.map((sensor) {
            final isSelected = selectedSensorTypes.contains(sensor.type);
            return FilterChip(
              avatar: Icon(
                sensor.icon,
                size: 18,
                color: isSelected ? cs.onPrimaryContainer : cs.primary,
              ),
              label: Text(sensor.label),
              selected: isSelected,
              selectedColor: cs.primaryContainer,
              checkmarkColor: cs.onPrimaryContainer,
              onSelected: (selected) =>
                  _toggleSensorSelection(sensor, selected),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        if (_editableSensors.isEmpty)
          Card(
            child: ListTile(
              leading: Icon(Icons.sensors, color: cs.onSurfaceVariant),
              title: const Text('No sensors selected'),
              subtitle: const Text('Add sensors from chips above.'),
            ),
          )
        else
          ..._editableSensors.asMap().entries.map((entry) {
            final sensor = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(sensor.icon, color: cs.primary, size: 20),
                ),
                title: Text(
                  sensor.label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  sensor.unit.isEmpty
                      ? _sensorTypeLabel(sensor.type)
                      : '${_sensorTypeLabel(sensor.type)} • ${sensor.unit}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
                trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
                onTap: () => _showEditSensorDialog(entry.key),
              ),
            );
          }),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveDevice,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add Device', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  // ── Edit toggle switch dialog ──────────────────────────────

  void _toggleSensorSelection(SensorTemplate template, bool selected) {
    setState(() {
      if (selected) {
        final alreadySelected = _editableSensors.any(
          (sensor) => sensor.type == template.type,
        );
        if (!alreadySelected) {
          _editableSensors.add(_EditableSensor.fromTemplate(template));
        }
        return;
      }

      _editableSensors.removeWhere((sensor) => sensor.type == template.type);
    });
  }

  void _showEditSensorDialog(int index) {
    final sensor = _editableSensors[index];
    final labelController = TextEditingController(text: sensor.label);
    IconData selectedIcon = sensor.icon;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit sensor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Sensor label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _sensorIcons.map((item) {
                  final isSelected = selectedIcon == item['icon'];
                  return GestureDetector(
                    onTap: () =>
                        setSheet(() => selectedIcon = item['icon'] as IconData),
                    child: Container(
                      width: 64,
                      height: 60,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? cs.primary : cs.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 20,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _editableSensors[index].label =
                          labelController.text.trim().isEmpty
                          ? sensor.label
                          : labelController.text.trim();
                      _editableSensors[index].icon = selectedIcon;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditSwitchDialog(int index) {
    final sw = _editableSwitches[index];
    final labelController = TextEditingController(text: sw.label);
    IconData selectedIcon = sw.icon;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit switch',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Switch label',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Icon', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _switchIcons.map((item) {
                  final isSelected = selectedIcon == item['icon'];
                  return GestureDetector(
                    onTap: () =>
                        setSheet(() => selectedIcon = item['icon'] as IconData),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? cs.primary : cs.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 20,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 8,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _editableSwitches[index].label =
                          labelController.text.trim().isEmpty
                          ? sw.label
                          : labelController.text.trim();
                      _editableSwitches[index].icon = selectedIcon;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _switchTypeColor(SwitchType type) {
    switch (type) {
      case SwitchType.fan:
        return Colors.blue;
      case SwitchType.dimmer:
        return Colors.orange;
      case SwitchType.curtain:
        return Colors.teal;
      case SwitchType.scene:
        return Colors.purple;
      default:
        return Colors.green;
    }
  }

  String _sensorTypeLabel(String type) {
    return SensorTemplateCatalog.byType(type).label;
  }
}

// ── Fan switch preview (ON/OFF + 0-5 speed slider) ─────────────

class _FanSwitchPreview extends StatefulWidget {
  final _EditableSwitch sw;
  final int index;
  final ColorScheme cs;

  const _FanSwitchPreview({
    required this.sw,
    required this.index,
    required this.cs,
  });

  @override
  State<_FanSwitchPreview> createState() => _FanSwitchPreviewState();
}

class _FanSwitchPreviewState extends State<_FanSwitchPreview> {
  bool _isOn = false;
  double _speed = 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _isOn
          ? widget.cs.primaryContainer
          : widget.cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.15),
                  child: const Icon(Icons.air, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sw.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Fan — Speed: ${_speed.toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.cs.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                // ON / OFF toggle
                Switch(
                  value: _isOn,
                  onChanged: (v) => setState(() => _isOn = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Speed slider 0-100%
            Row(
              children: [
                Icon(
                  Icons.speed,
                  size: 16,
                  color: widget.cs.onSurface.withOpacity(0.4),
                ),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: 'Speed ${_speed.toInt()}%',
                    onChanged: (v) => setState(() {
                      _speed = v;
                      if (v > 0) _isOn = true;
                    }),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    _speed.toInt().toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.cs.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            Text(
              'Preview only — actual values set when device is used',
              style: TextStyle(
                fontSize: 10,
                color: widget.cs.onSurface.withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dimmer switch preview (0-100% slider) ──────────────────────

class _DimmerSwitchPreview extends StatefulWidget {
  final _EditableSwitch sw;
  final int index;
  final ColorScheme cs;

  const _DimmerSwitchPreview({
    required this.sw,
    required this.index,
    required this.cs,
  });

  @override
  State<_DimmerSwitchPreview> createState() => _DimmerSwitchPreviewState();
}

class _DimmerSwitchPreviewState extends State<_DimmerSwitchPreview> {
  double _brightness = 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _brightness > 0
          ? widget.cs.primaryContainer
          : widget.cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.withOpacity(0.15),
                  child: const Icon(
                    Icons.wb_sunny_outlined,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sw.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Dimmer — ${_brightness.toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.cs.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.brightness_low,
                  size: 16,
                  color: widget.cs.onSurface.withOpacity(0.4),
                ),
                Expanded(
                  child: Slider(
                    value: _brightness,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_brightness.toInt()}%',
                    onChanged: (v) => setState(() => _brightness = v),
                  ),
                ),
                Icon(
                  Icons.brightness_high,
                  size: 16,
                  color: widget.cs.onSurface.withOpacity(0.4),
                ),
              ],
            ),
            Text(
              'Preview only — actual values set when device is used',
              style: TextStyle(
                fontSize: 10,
                color: widget.cs.onSurface.withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local editable switch state ────────────────────────────────

class _EditableSwitch {
  String switchId;
  String label;
  SwitchType type;
  IconData icon;

  _EditableSwitch({
    required this.switchId,
    required this.label,
    required this.type,
    required this.icon,
  });
}

class _EditableSensor {
  String sensorId;
  String label;
  String type;
  String unit;
  IconData icon;
  double defaultValue;
  double minValue;
  double maxValue;
  double step;

  _EditableSensor({
    required this.sensorId,
    required this.label,
    required this.type,
    required this.unit,
    required this.icon,
    required this.defaultValue,
    required this.minValue,
    required this.maxValue,
    required this.step,
  });

  factory _EditableSensor.fromTemplate(SensorTemplate template) {
    return _EditableSensor(
      sensorId: template.sensorId,
      label: template.label,
      type: template.type,
      unit: template.unit,
      icon: template.icon,
      defaultValue: template.defaultValue,
      minValue: template.minValue,
      maxValue: template.maxValue,
      step: template.step,
    );
  }
}
