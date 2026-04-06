import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/device_model.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../services/firestore_service.dart';
import '../services/mqtt_provider.dart';
import '../screens/devices_screen.dart';
import 'add_device_screen.dart';
import 'homes_screen.dart';
import 'settings_screen.dart';

class RoomsScreen extends StatefulWidget {
  final HomeModel home; // passed from HomesScreen
  final bool isEntryPoint; // true when opened as favourite home
  const RoomsScreen({
    super.key,
    required this.home,
    this.isEntryPoint = false, // default false
  });

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  // Room icons to pick from
  final List<Map<String, dynamic>> _roomIcons = [
    {'label': 'Living Room', 'icon': Icons.weekend},
    {'label': 'Bedroom', 'icon': Icons.bed},
    {'label': 'Kitchen', 'icon': Icons.kitchen},
    {'label': 'Bathroom', 'icon': Icons.bathtub},
    {'label': 'Office', 'icon': Icons.computer},
    {'label': 'Garage', 'icon': Icons.garage},
    {'label': 'Garden', 'icon': Icons.yard},
    {'label': 'Other', 'icon': Icons.room},
  ];

  // ── Add room bottom sheet ──────────────────────────────────

  void _showAddRoomDialog() {
    final nameController = TextEditingController();
    String selectedIcon = 'weekend'; // default icon name
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        // StatefulBuilder so icon selection updates inside the sheet
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Room',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Room name field
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Room name',
                    hintText: 'e.g. Master Bedroom',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter a room name' : null,
                ),
                const SizedBox(height: 20),

                // Icon picker
                const Text(
                  'Room type',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _roomIcons.map((item) {
                    final isSelected = selectedIcon == item['label'];
                    return GestureDetector(
                      onTap: () => setSheetState(
                        () => selectedIcon = item['label'] as String,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        await _firestoreService.addRoom(
                          _uid,
                          widget.home.homeId,
                          RoomModel(
                            roomId: '',
                            roomName: nameController.text.trim(),
                            icon: selectedIcon,
                            deviceRefs: [], // empty on creation
                          ),
                        );
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text('Save Room'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmTurnOffAll(String roomId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off all switches'),
        content: const Text(
          'Are you sure you want to turn off all switches in this room?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn off', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final mqtt = MqttProvider.read(context);
      if (!mqtt.isConnected) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('MQTT is offline. Reconnect and try again.'),
            ),
          );
        }
        return;
      }

      final devices = await _firestoreService
          .streamDevicesInRoom(_uid, roomId)
          .first;
      var sentCommands = 0;

      for (final device in devices) {
        final macId = device.macId;
        if (macId == null || macId.isEmpty) continue;

        mqtt.seedStates(
          macId,
          device.switches.map((sw) => sw.toMap()).toList(),
        );

        for (final entry in device.switches.asMap().entries) {
          mqtt.publishCommand(
            macAddress: macId,
            switchIndex: entry.key,
            isOn: false,
            value: 0,
            type: entry.value.type,
          );
          sentCommands++;
        }
      }

      if (sentCommands == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No controllable devices found in this room.'),
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent OFF command to $sentCommands switches.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to turn off all switches.')),
        );
      }
    }
  }

  // ── Delete confirmation ────────────────────────────────────

  void _confirmDelete(RoomModel room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Delete "${room.roomName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _firestoreService.deleteRoom(
                _uid,
                widget.home.homeId,
                room.roomId,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditRoomDialog(RoomModel room) {
    final nameController = TextEditingController(text: room.roomName);
    String selectedIcon = room.icon; // pre-fill current icon
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Room',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Room name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter a room name' : null,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Room type',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _roomIcons.map((item) {
                    final isSelected = selectedIcon == item['label'];
                    return GestureDetector(
                      onTap: () => setSheetState(
                        () => selectedIcon = item['label'] as String,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              item['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
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
                    onPressed: () async {
                      if (formKey.currentState!.validate()) {
                        await _firestoreService.updateRoom(
                          _uid,
                          widget.home.homeId,
                          room.roomId,
                          nameController.text.trim(),
                          selectedIcon,
                        );
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text('Update Room'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Icon helper ────────────────────────────────────────────

  IconData _getIcon(String iconLabel) {
    return _roomIcons.firstWhere(
          (e) => e['label'] == iconLabel,
          orElse: () => {'icon': Icons.room},
        )['icon']
        as IconData;
  }

  // ── Build ──────────────────────────────────────────────────

  void _showRoomOptions(RoomModel room) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.blue),
              title: const Text('Edit Room'),
              onTap: () {
                Navigator.pop(context);
                _showEditRoomDialog(room);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete Room',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(room);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Show home name as title
        title: Text(widget.home.homeName),

        // Hide back button if this is the favourite (entry point)
        automaticallyImplyLeading: !widget.isEntryPoint,

        actions: [
          // Add device button — always visible inside a home
          IconButton(
            icon: const Icon(Icons.devices),
            tooltip: 'Add Device',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevicesScreen(home: widget.home, room: null),
                ),
              );
            },
          ),

          // More options menu
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'add_room') {
                _showAddRoomDialog();
              } else if (value == 'add_device') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AddDeviceScreen(home: widget.home, room: null),
                  ),
                );
              } else if (value == 'all_homes') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HomesScreen(autoNavigate: false),
                  ),
                );
              } else if (value == 'settings') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'logout') {
                await FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_room',
                child: Row(
                  children: [
                    Icon(Icons.meeting_room_outlined),
                    SizedBox(width: 12),
                    Text('Add Room'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_device',
                child: Row(
                  children: [
                    Icon(Icons.devices_outlined),
                    SizedBox(width: 12),
                    Text('Add Device'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'all_homes',
                child: Row(
                  children: [
                    Icon(Icons.home_outlined),
                    SizedBox(width: 12),
                    Text('All Homes'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 12),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<RoomModel>>(
        stream: _firestoreService.streamRooms(_uid, widget.home.homeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final rooms = snapshot.data ?? [];

          if (rooms.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No rooms yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to add your first room',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 188,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return Card(
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DevicesScreen(home: widget.home, room: room),
                    ),
                  ),
                  onLongPress: () => _showRoomOptions(room),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Room icon + name row
                        Row(
                          children: [
                            Icon(
                              _getIcon(room.icon),
                              size: 28,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                room.roomName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Switch status dots — streamed from devices
                        StreamBuilder<List<DeviceModel>>(
                          stream: _firestoreService.streamDevices(_uid),
                          builder: (context, snap) {
                            if (!snap.hasData) return const SizedBox.shrink();
                            final mqtt = MqttProvider.of(context);

                            // Only devices in this room
                            final roomDevices = snap.data!
                                .where((d) => d.linkedRoom == room.roomId)
                                .toList();
                            final cs = Theme.of(context).colorScheme;

                            if (roomDevices.isEmpty) {
                              return const Text(
                                'No devices',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              );
                            }

                            final switchDots = roomDevices
                                .expand((device) {
                                  final deviceMac = device.macId ?? '';
                                  return device.switches.asMap().entries.map((
                                    entry,
                                  ) {
                                    final switchIndex = entry.key;
                                    final sw = entry.value;
                                    final mqttState = deviceMac.isEmpty
                                        ? null
                                        : mqtt.getState(deviceMac, switchIndex);

                                    return {
                                      'label': sw.label,
                                      'isOn': mqttState?.isOn ?? sw.isOn,
                                    };
                                  });
                                })
                                .toList(growable: false);

                            final totalSwitches = switchDots.length;
                            final activeSwitches = switchDots
                                .where((dot) => dot['isOn'] == true)
                                .length;
                            final visibleDots = switchDots.take(8).toList();
                            final hiddenDots =
                                totalSwitches - visibleDots.length;

                            for (final device in roomDevices) {
                              final macId = device.macId;
                              if (macId == null || macId.isEmpty) continue;
                              mqtt.seedStates(
                                macId,
                                device.switches
                                    .map((sw) => sw.toMap())
                                    .toList(),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '$activeSwitches of $totalSwitches switches on',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    ...visibleDots.map((dot) {
                                      final isOn = dot['isOn'] == true;
                                      return Tooltip(
                                        message: dot['label'] as String,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isOn
                                                ? cs.primary
                                                : cs.surfaceContainerHighest,
                                            border: Border.all(
                                              color: isOn
                                                  ? cs.primary
                                                  : cs.outline,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    if (hiddenDots > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '+$hiddenDots',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.power_settings_new,
                                    size: 16,
                                  ),
                                  label: const Text('Turn off all switches'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(32),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _confirmTurnOffAll(room.roomId),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
