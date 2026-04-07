import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../models/room_model.dart';
import '../models/device_model.dart';
import '../services/firestore_service.dart';
import '../services/mqtt_provider.dart';
import '../services/mqtt_service.dart';
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
    // Auto-connect MQTT broker after a short delay to allow context to be ready
    Future.delayed(const Duration(milliseconds: 500), _autoConnectMqtt);
  }

  Future<void> _autoConnectMqtt() async {
    if (!mounted) return;

    final mqtt = MqttProvider.read(context);

    // Only auto-connect if not already connected
    if (!mqtt.isConnected) {
      debugPrint('[HomeTab] Auto-connecting to MQTT broker...');

      // Load saved settings before connecting
      final settings = await MqttService.loadAllSettings();
      mqtt.brokerHost = settings['host'] as String;
      mqtt.brokerPort = settings['port'] as int;
      mqtt.apiKey = settings['apiKey'] as String;
      mqtt.useTls = settings['useTls'] as bool;
      mqtt.heartbeatInterval = Duration(seconds: settings['interval'] as int);
      mqtt.offlineTimeout = Duration(seconds: settings['timeout'] as int);

      debugPrint(
        '[HomeTab] Using settings: ${settings['host']}:${settings['port']}',
      );
      await mqtt.connect();
      debugPrint('[HomeTab] MQTT connection result: ${mqtt.isConnected}');
    }
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
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No rooms yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap ⋮ to add your first room',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
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
          'Are you sure you want to turn off all switches in this room?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
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

      final devices = await firestoreService
          .streamDevicesInRoom(uid, room.roomId)
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
              builder: (_) => DevicesScreen(home: home, room: room),
            ),
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
                      top: Radius.circular(20),
                    ),
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
                        child: Icon(_roomIcon(), color: cs.primary, size: 22),
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
                        icon: const Icon(Icons.power_settings_new, size: 20),
                        color: cs.error,
                        tooltip: 'Turn off all',
                        onPressed: () => _confirmTurnOffAll(context),
                      ),
                      // Arrow
                      Icon(
                        Icons.chevron_right,
                        color: cs.onPrimaryContainer.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),

                // ── Device switch dots ───────────────────────
                StreamBuilder<List<DeviceModel>>(
                  stream: firestoreService.streamDevices(uid),
                  builder: (context, snap) {
                    final mqtt = MqttProvider.of(context);
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    final devices = snap.data!
                        .where((d) => d.linkedRoom == room.roomId)
                        .toList();

                    for (final device in devices) {
                      final macId = device.macId;
                      if (macId == null || macId.isEmpty) continue;
                      mqtt.seedStates(
                        macId,
                        device.switches.map((sw) => sw.toMap()).toList(),
                      );
                    }

                    if (devices.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Text(
                          'No devices yet',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.4),
                          ),
                        ),
                      );
                    }

                    // Count ON switches across all devices
                    final totalSwitches = devices.fold<int>(
                      0,
                      (count, device) => count + device.switches.length,
                    );
                    final onCount = devices.fold<int>(0, (count, device) {
                      final macId = device.macId;
                      if (macId == null || macId.isEmpty) {
                        return count +
                            device.switches.where((sw) => sw.isOn).length;
                      }

                      return count +
                          device.switches.asMap().entries.where((entry) {
                            final mqttState = mqtt.getState(macId, entry.key);
                            return mqttState?.isOn ?? entry.value.isOn;
                          }).length;
                    });

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Summary line
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: onCount > 0
                                    ? cs.primary
                                    : cs.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                onCount > 0
                                    ? '$onCount of $totalSwitches switches on'
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
                          ...devices.map(
                            (device) => _DeviceDotRow(device: device, cs: cs),
                          ),
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
    final mqtt = MqttProvider.of(context);
    final macId = device.macId;

    if (macId != null && macId.isNotEmpty) {
      mqtt.seedStates(macId, device.switches.map((sw) => sw.toMap()).toList());
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.deviceName,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withOpacity(0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: device.switches.asMap().entries.map((entry) {
              final sw = entry.value;
              final isOn = macId != null && macId.isNotEmpty
                  ? (mqtt.getState(macId, entry.key)?.isOn ?? sw.isOn)
                  : sw.isOn;
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
                      color: isOn ? cs.primary : cs.onSurface.withOpacity(0.25),
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
