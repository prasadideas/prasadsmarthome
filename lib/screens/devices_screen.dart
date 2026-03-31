import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../services/firestore_service.dart';
import 'add_device_screen.dart';

class DevicesScreen extends StatefulWidget {
  final HomeModel home;
  final RoomModel? room; // null means "All Devices" view

  const DevicesScreen({super.key, required this.home, this.room});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  // ── Device options (edit / delete / assign room) ───────────

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
              leading: const Icon(
                Icons.meeting_room_outlined,
                color: Colors.orange,
              ),
              title: const Text('Assign to Room'),
              onTap: () {
                Navigator.pop(context);
                _showAssignRoomDialog(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete Device',
                style: TextStyle(color: Colors.red),
              ),
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

  // ── Rename device ──────────────────────────────────────────

  void _showRenameDialog(DeviceModel device) {
    final nameController = TextEditingController(text: device.deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Device name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await _firestoreService.updateDevice(
                  uid,
                  device.deviceId,
                  nameController.text.trim(),
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Assign to room ─────────────────────────────────────────

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
                  // Unassign option
                  ListTile(
                    leading: const Icon(Icons.clear, color: Colors.red),
                    title: const Text('No Room (unassign)'),
                    selected: device.linkedRoom == null,
                    onTap: () async {
                      // Remove from old room if assigned
                      if (device.linkedRoom != null) {
                        await _firestoreService.removeDeviceRefFromRoom(
                          uid,
                          widget.home.homeId,
                          device.linkedRoom!,
                          device.deviceId,
                        );
                      }
                      await _firestoreService.assignDeviceToRoom(
                        uid,
                        device.deviceId,
                        null,
                        null,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                  // Room list
                  ...rooms.map(
                    (room) => ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text(room.roomName),
                      selected: device.linkedRoom == room.roomId,
                      selectedColor: Colors.blue,
                      onTap: () async {
                        // Remove from old room first
                        if (device.linkedRoom != null &&
                            device.linkedRoom != room.roomId) {
                          await _firestoreService.removeDeviceRefFromRoom(
                            uid,
                            widget.home.homeId,
                            device.linkedRoom!,
                            device.deviceId,
                          );
                        }
                        // Assign to new room
                        await _firestoreService.assignDeviceToRoom(
                          uid,
                          device.deviceId,
                          room.roomId,
                          widget.home.homeId,
                        );
                        await _firestoreService.addDeviceRefToRoom(
                          uid,
                          widget.home.homeId,
                          room.roomId,
                          device.deviceId,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Delete confirmation ────────────────────────────────────

  void _confirmDelete(DeviceModel device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Delete "${device.deviceName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Remove from room ref if assigned
              if (device.linkedRoom != null) {
                await _firestoreService.removeDeviceRefFromRoom(
                  uid,
                  widget.home.homeId,
                  device.linkedRoom!,
                  device.deviceId,
                );
              }
              await _firestoreService.deleteDevice(uid, device.deviceId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.room != null
        ? widget.room!.roomName
        : '${widget.home.homeName} — All Devices';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$title — All Devices',
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_device') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AddDeviceScreen(home: widget.home, room: widget.room),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_device',
                child: Row(
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 12),
                    Text('Add Device'),
                  ],
                ),
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

          // If opened from a room, filter to only that room's devices
          final devices = widget.room != null
              ? allDevices
                    .where((d) => d.linkedRoom == widget.room!.roomId)
                    .toList()
              : allDevices;

          if (devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No devices yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to add a device',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Device header
                      Row(
                        children: [
                          const Icon(Icons.devices),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              device.deviceName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          // Online indicator
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: device.isOnline
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              device.isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: device.isOnline
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showDeviceOptions(device),
                          ),
                        ],
                      ),

                      const Divider(height: 20),

                      // Switches grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 2.8,
                            ),
                        itemCount: device.switches.length,
                        itemBuilder: (context, i) {
                          final sw = device.switches[i];
                          return GestureDetector(
                            onTap: () async {
                              await _firestoreService.toggleSwitch(
                                uid,
                                device.deviceId,
                                i,
                                !sw.isOn,
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: sw.isOn
                                    ? Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sw.isOn
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade300,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    sw.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: sw.isOn
                                          ? Theme.of(context).primaryColor
                                          : Colors.black87,
                                    ),
                                  ),
                                  Icon(
                                    sw.isOn
                                        ? Icons.toggle_on
                                        : Icons.toggle_off,
                                    color: sw.isOn
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                    size: 28,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
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
