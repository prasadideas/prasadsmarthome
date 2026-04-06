import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../services/firestore_service.dart';
import '../services/mqtt_provider.dart';
import '../widgets/switch_tile.dart';
import 'add_device_screen.dart';

class DevicesScreen extends StatefulWidget {
  final HomeModel home;
  final RoomModel? room;

  const DevicesScreen({super.key, required this.home, this.room});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  // ── Device options ─────────────────────────────────────────

  void _showDeviceOptions(DeviceModel device) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.blue),
              title: const Text('Rename Device'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.toggle_on, color: Colors.purple),
              title: const Text('Edit Switches'),
              onTap: () {
                Navigator.pop(context);
                _showSwitchesEditDialog(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.meeting_room_outlined,
                  color: Colors.orange),
              title: const Text('Assign to Room'),
              onTap: () {
                Navigator.pop(context);
                _showAssignRoomDialog(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Device',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(device);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(DeviceModel device) {
    final nameController = TextEditingController(text: device.deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: 'Device name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await _firestoreService.updateDevice(
                    uid, device.deviceId, nameController.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAssignRoomDialog(DeviceModel device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign to Room'),
        content: StreamBuilder<List<RoomModel>>(
          stream: _firestoreService.streamRooms(uid, widget.home.homeId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final rooms = snapshot.data!;
            return SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.clear, color: Colors.red),
                    title: const Text('No Room (unassign)'),
                    selected: device.linkedRoom == null,
                    onTap: () async {
                      if (device.linkedRoom != null) {
                        await _firestoreService.removeDeviceRefFromRoom(
                            uid, widget.home.homeId, device.linkedRoom!,
                            device.deviceId);
                      }
                      await _firestoreService.assignDeviceToRoom(
                          uid, device.deviceId, null, null);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                  ...rooms.map((room) => ListTile(
                        leading: const Icon(Icons.meeting_room_outlined),
                        title: Text(room.roomName),
                        selected: device.linkedRoom == room.roomId,
                        selectedColor: Colors.blue,
                        onTap: () async {
                          if (device.linkedRoom != null &&
                              device.linkedRoom != room.roomId) {
                            await _firestoreService.removeDeviceRefFromRoom(
                                uid, widget.home.homeId, device.linkedRoom!,
                                device.deviceId);
                          }
                          await _firestoreService.assignDeviceToRoom(
                              uid, device.deviceId, room.roomId,
                              widget.home.homeId);
                          await _firestoreService.addDeviceRefToRoom(
                              uid, widget.home.homeId, room.roomId,
                              device.deviceId);
                          if (context.mounted) Navigator.pop(context);
                        },
                      )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSwitchesEditDialog(DeviceModel device) {
    const commonIcons = [
      Icons.lightbulb_outline,
      Icons.air_outlined,
      Icons.wb_sunny_outlined,
      Icons.brightness_7,
      Icons.power_settings_new,
      Icons.videogame_asset_outlined,
      Icons.tv_outlined,
      Icons.water_drop_outlined,
      Icons.thermostat,
      Icons.door_front_door,
      Icons.door_sliding,
      Icons.blinds_outlined,
      Icons.lock_outline,
      Icons.home_outlined,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Switches'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: device.switches.length,
            itemBuilder: (context, index) {
              final switchModel = device.switches[index];
              return ListTile(
                title: Text(switchModel.label),
                subtitle: Text('Type: ${switchModel.type}'),
                trailing: Icon(
                  IconData(
                    int.tryParse(switchModel.icon) ??
                        Icons.lightbulb_outline.codePoint,
                    fontFamily: 'MaterialIcons',
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditSwitchDialog(device, index, switchModel, commonIcons);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showEditSwitchDialog(DeviceModel device, int switchIndex,
      SwitchModel switchModel, List<IconData> commonIcons) {
    final labelController = TextEditingController(text: switchModel.label);
    int selectedIconCode =
        int.tryParse(switchModel.icon) ?? Icons.lightbulb_outline.codePoint;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Switch'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Switch Label',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Bedroom Light',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Select Icon',
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: commonIcons.map((icon) {
                    final isSelected = icon.codePoint == selectedIconCode;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          selectedIconCode = icon.codePoint;
                        });
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(dialogContext)
                                  .colorScheme
                                  .primaryContainer
                              : Theme.of(dialogContext)
                                  .colorScheme
                                  .surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .primary,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Icon(
                          icon,
                          color: isSelected
                              ? Theme.of(dialogContext).colorScheme.primary
                              : Theme.of(dialogContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                          size: 28,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _firestoreService.updateSwitch(
                    uid,
                    device.deviceId,
                    switchIndex,
                    labelController.text.trim(),
                    selectedIconCode.toString(),
                  );
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Switch updated successfully'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(DeviceModel device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content:
            Text('Delete "${device.deviceName}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (device.linkedRoom != null) {
                await _firestoreService.removeDeviceRefFromRoom(
                    uid, widget.home.homeId, device.linkedRoom!,
                    device.deviceId);
              }
              await _firestoreService.deleteDevice(uid, device.deviceId);
              if (context.mounted) Navigator.pop(context);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.room != null
        ? widget.room!.roomName
        : '${widget.home.homeName} — All Devices';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_device') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddDeviceScreen(
                        home: widget.home, room: widget.room),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_device',
                child: Row(children: [
                  Icon(Icons.add),
                  SizedBox(width: 12),
                  Text('Add Device'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<DeviceModel>>(
        stream: _firestoreService.streamDevices(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allDevices = snapshot.data ?? [];
          final devices = widget.room != null
              ? allDevices
                  .where((d) => d.linkedRoom == widget.room!.roomId)
                  .toList()
              : allDevices;

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices, size: 64,
                      color: cs.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('No devices yet',
                      style: TextStyle(
                          fontSize: 18,
                          color: cs.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  Text('Tap ⋮ to add a device',
                      style: TextStyle(
                          color: cs.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final device = devices[index];
              return _DeviceCard(device: device, cs: cs,
                  onOptions: () => _showDeviceOptions(device));
            },
          );
        },
      ),
    );
  }
}

// ── Device card ────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final DeviceModel device;
  final ColorScheme cs;
  final VoidCallback onOptions;

  const _DeviceCard({
    required this.device,
    required this.cs,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    // Get MQTT provider for device online status
    final mqtt = MqttProvider.of(context);
    final macId = device.macId ?? '';
    final isDeviceOnline = macId.isNotEmpty ? mqtt.isDeviceOnline(macId) : false;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Icon(Icons.developer_board,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    device.deviceName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                // Online status chip - using MQTT online status
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDeviceOnline
                        ? Colors.green.withOpacity(0.12)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDeviceOnline
                              ? Colors.green
                              : cs.onSurface.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDeviceOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDeviceOnline
                              ? Colors.green
                              : cs.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_vert,
                      color: cs.onSurface.withOpacity(0.6)),
                  onPressed: onOptions,
                ),
              ],
            ),
          ),

          const Divider(height: 16, indent: 16, endIndent: 16),

          // Switch tiles
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _buildSwitchGrid(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchGrid(BuildContext context) {
    // Separate slider-type switches from toggle-type
    final sliderSwitches = <int>[];
    final toggleSwitches = <int>[];

    for (int i = 0; i < device.switches.length; i++) {
      final type = device.switches[i].type;
      if (type == 'fan' || type == 'dimmer') {
        sliderSwitches.add(i);
      } else {
        toggleSwitches.add(i);
      }
    }

    // Get MQTT provider for device online status
    final mqtt = MqttProvider.of(context);
    final macId = device.macId ?? '';
    final isDeviceOnline = macId.isNotEmpty ? mqtt.isDeviceOnline(macId) : false;

    return Column(
      children: [
        // Toggle switches in 2-column grid
        if (toggleSwitches.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.8,
            ),
            itemCount: toggleSwitches.length,
            itemBuilder: (context, i) {
              final switchIndex = toggleSwitches[i];
              final macId = device.macId;
              if (macId == null || macId.isEmpty) {
                return const ListTile(
                  title: Text('Device missing MAC ID'),
                  leading: Icon(Icons.error_outline, color: Colors.red),
                );
              }
              return SwitchTile(
                deviceMac: macId,
                switchIndex: switchIndex,
                switchModel: device.switches[switchIndex],
                compact: true,
                isDeviceOnline: isDeviceOnline,
              );
            },
          ),

        // Slider switches (fan/dimmer) full width below
        if (sliderSwitches.isNotEmpty) ...[
          if (toggleSwitches.isNotEmpty) const SizedBox(height: 8),
          ...(() {
            final macId = device.macId;
            if (macId == null || macId.isEmpty) {
              return [const ListTile(
                title: Text('Device missing MAC ID'),
                leading: Icon(Icons.error_outline, color: Colors.red),
              )];
            }
            return sliderSwitches.map((switchIndex) => SwitchTile(
                  deviceMac: macId,
                  switchIndex: switchIndex,
                  switchModel: device.switches[switchIndex],
                  compact: false,
                  isDeviceOnline: isDeviceOnline,
                )).toList();
          })(),
        ],
      ],
    );
  }
}
