import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../services/firestore_service.dart';
import 'rooms_screen.dart';
import 'devices_screen.dart';
import 'add_device_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  HomeModel? _activeHome;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveHome();
  }

  Future<void> _loadActiveHome() async {
    final userData = await _firestoreService.getUser(uid);
    final favouriteId = userData?['favouriteHomeId'] ?? '';
    final homes = await _firestoreService.streamHomes(uid).first;

    if (!mounted) return;

    HomeModel? selected;
    if (favouriteId.isNotEmpty) {
      selected = homes.where((h) => h.homeId == favouriteId).firstOrNull;
    }
    selected ??= homes.isNotEmpty ? homes.first : null;

    setState(() {
      _activeHome = selected;
      _loading = false;
    });
  }

  void _showSwitchHomeMenu(List<HomeModel> homes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Switch Home',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...homes.map(
              (home) => ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    home.homeId == _activeHome?.homeId
                        ? Icons.home
                        : Icons.home_outlined,
                  ),
                ),
                title: Text(home.homeName),
                subtitle: Text(home.address),
                trailing: home.homeId == _activeHome?.homeId
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  setState(() => _activeHome = home);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_activeHome == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No homes added yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Go to Me tab to add a home'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<HomeModel>>(
          stream: _firestoreService.streamHomes(uid),
          builder: (context, snapshot) {
            final homes = snapshot.data ?? [];
            return GestureDetector(
              onTap:
                  homes.length > 1 ? () => _showSwitchHomeMenu(homes) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_activeHome!.homeName),
                  if (homes.length > 1) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_room') {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => RoomsScreen(home: _activeHome!)));
              } else if (value == 'add_device') {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AddDeviceScreen(home: _activeHome!)));
              } else if (value == 'all_devices') {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) =>
                        DevicesScreen(home: _activeHome!, room: null)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add_room',
                child: Row(children: [
                  Icon(Icons.meeting_room_outlined),
                  SizedBox(width: 12),
                  Text('Add Room'),
                ]),
              ),
              const PopupMenuItem(
                value: 'add_device',
                child: Row(children: [
                  Icon(Icons.devices_outlined),
                  SizedBox(width: 12),
                  Text('Add Device'),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'all_devices',
                child: Row(children: [
                  Icon(Icons.list_outlined),
                  SizedBox(width: 12),
                  Text('All Devices'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<RoomModel>>(
        stream: _firestoreService.streamRooms(uid, _activeHome!.homeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rooms = snapshot.data ?? [];

          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.meeting_room_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('No rooms yet',
                      style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5))),
                  const SizedBox(height: 8),
                  Text('Tap ⋮ to add your first room',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return _RoomCard(
                room: room,
                uid: uid,
                home: _activeHome!,
                firestoreService: _firestoreService,
              );
            },
          );
        },
      ),
    );
  }
}

// ── Attractive Room Card ───────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final RoomModel room;
  final String uid;
  final HomeModel home;
  final FirestoreService firestoreService;

  const _RoomCard({
    required this.room,
    required this.uid,
    required this.home,
    required this.firestoreService,
  });

  // Map room icon string to actual IconData
  IconData _roomIcon() {
    const iconMap = {
      'Living Room': Icons.weekend,
      'Bedroom': Icons.bed,
      'Kitchen': Icons.kitchen,
      'Bathroom': Icons.bathtub,
      'Office': Icons.computer,
      'Garage': Icons.garage,
      'Garden': Icons.yard,
      'Other': Icons.room,
    };
    return iconMap[room.icon] ?? Icons.meeting_room_outlined;
  }

  Future<void> _confirmTurnOffAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off all switches'),
        content: const Text(
            'Are you sure you want to turn off all switches in this room?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await firestoreService.setRoomAllSwitchesOff(uid, room.roomId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('All switches have been turned off.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Failed to turn off all switches.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DevicesScreen(home: home, room: room)),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header bar ───────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_roomIcon(),
                            color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          room.roomName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      // Turn-off-all button
                      IconButton(
                        icon: const Icon(Icons.power_settings_new,
                            size: 20),
                        color: cs.error,
                        tooltip: 'Turn off all',
                        onPressed: () => _confirmTurnOffAll(context),
                      ),
                      // Arrow
                      Icon(Icons.chevron_right,
                          color: cs.onPrimaryContainer.withOpacity(0.5)),
                    ],
                  ),
                ),

                // ── Device switch dots ───────────────────────
                StreamBuilder<List<DeviceModel>>(
                  stream: firestoreService.streamDevices(uid),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                      );
                    }

                    final devices = snap.data!
                        .where((d) => d.linkedRoom == room.roomId)
                        .toList();

                    if (devices.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Text('No devices yet',
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withOpacity(0.4))),
                      );
                    }

                    // Count ON switches across all devices
                    final allSwitches = devices
                        .expand((d) => d.switches)
                        .toList();
                    final onCount =
                        allSwitches.where((s) => s.isOn).length;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Summary line
                          Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 8,
                                  color: onCount > 0
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.3)),
                              const SizedBox(width: 6),
                              Text(
                                onCount > 0
                                    ? '$onCount of ${allSwitches.length} switches on'
                                    : 'All switches off',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: onCount > 0
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.45),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Per-device grouped dots
                          ...devices.map((device) =>
                              _DeviceDotRow(device: device, cs: cs)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Per-device dot row (change 2: dots grouped per device) ────

class _DeviceDotRow extends StatelessWidget {
  final DeviceModel device;
  final ColorScheme cs;

  const _DeviceDotRow({required this.device, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Device name label
          SizedBox(
            width: 90,
            child: Text(
              device.deviceName,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(0.55),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Dots for each switch in this device
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: device.switches.map((sw) {
              final isOn = sw.isOn;
              return Tooltip(
                message: sw.label,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOn ? cs.primary : Colors.transparent,
                    border: Border.all(
                      color: isOn
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
