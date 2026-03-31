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
              const Text(
                'No homes added yet',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Switch to Me tab to add a home
                },
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
              onTap: homes.length > 1 ? () => _showSwitchHomeMenu(homes) : null,
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoomsScreen(home: _activeHome!),
                  ),
                );
              } else if (value == 'add_device') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddDeviceScreen(home: _activeHome!),
                  ),
                );
              } else if (value == 'all_devices') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DevicesScreen(home: _activeHome!, room: null),
                  ),
                );
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
                value: 'all_devices',
                child: Row(
                  children: [
                    Icon(Icons.list_outlined),
                    SizedBox(width: 12),
                    Text('All Devices'),
                  ],
                ),
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
                  const Icon(
                    Icons.meeting_room_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No rooms yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap ⋮ to add your first room',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
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

// ── Room card with switch state dots ──────────────────────

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

  Future<void> _confirmTurnOffAll(BuildContext context) async {
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
      await firestoreService.setRoomAllSwitchesOff(uid, room.roomId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All switches have been turned off.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to turn off all switches.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DevicesScreen(home: home, room: room),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room header
              ListTile(
                leading: Icon(
                  Icons.meeting_room_outlined,
                  color: Theme.of(context).primaryColor,
                ),
                title: Text(
                  room.roomName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.power_settings_new),
                  tooltip: 'Turn off all switches',
                  color: Colors.redAccent,
                  onPressed: () => _confirmTurnOffAll(context),
                ),
              ),

              const Divider(height: 0),

              // Switch state dots
              StreamBuilder<List<DeviceModel>>(
                stream: firestoreService.streamDevices(uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final devices = snap.data!
                      .where((d) => d.linkedRoom == room.roomId)
                      .toList();

                  if (devices.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No devices in this room',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    );
                  }

                  final allSwitches = devices.expand((d) => d.switches).toList();

                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allSwitches.map((sw) {
                        return Tooltip(
                          message: sw.label,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sw.isOn
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey.shade300,
                              border: Border.all(
                                color: sw.isOn
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.shade400,
                                width: 0.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
