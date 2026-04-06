import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/scene_model.dart';
import '../models/home_model.dart';
import '../services/firestore_service.dart';
import '../main.dart' as main_app;

class ScenesTab extends StatefulWidget {
  const ScenesTab({super.key});

  @override
  State<ScenesTab> createState() => _ScenesTabState();
}

class _ScenesTabState extends State<ScenesTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  final List<Map<String, dynamic>> _sceneIcons = [
    {'label': 'Morning',  'icon': Icons.wb_sunny_outlined},
    {'label': 'Night',    'icon': Icons.nights_stay_outlined},
    {'label': 'Movie',    'icon': Icons.movie_outlined},
    {'label': 'Dinner',   'icon': Icons.restaurant_outlined},
    {'label': 'Sleep',    'icon': Icons.bed},
    {'label': 'Party',    'icon': Icons.celebration},
    {'label': 'Away',     'icon': Icons.directions_walk},
    {'label': 'Welcome',  'icon': Icons.waving_hand},
  ];

  void _showAddSceneSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AddSceneScreen(
          uid: uid,
          firestoreService: _firestoreService,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  String _formatSchedule(SceneModel scene) {
    if (!scene.isScheduled || scene.scheduledTime == null) return '';
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabels =
        scene.scheduledDays.map((d) => days[d]).join(', ');
    return '${scene.scheduledTime}  $dayLabels';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenes'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add') _showAddSceneSheet();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(children: [
                  Icon(Icons.add),
                  SizedBox(width: 12),
                  Text('Create Scene'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<SceneModel>>(
        stream: _firestoreService.streamScenes(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final scenes = snapshot.data ?? [];

          if (scenes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No scenes yet',
                      style:
                          TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text(
                      'Create a scene to control multiple switches at once',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showAddSceneSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Scene'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: scenes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final scene = scenes[index];
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .primaryColor
                        .withOpacity(0.1),
                    child: Icon(
                      _sceneIcons.firstWhere(
                        (e) => e['label'] == scene.icon,
                        orElse: () => {'icon': Icons.auto_awesome},
                      )['icon'] as IconData,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  title: Text(scene.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${scene.actions.length} actions',
                          style: const TextStyle(fontSize: 12)),
                      if (scene.isScheduled)
                        Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 12, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              _formatSchedule(scene),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.blue),
                            ),
                          ],
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active toggle for scheduled scenes
                      if (scene.isScheduled)
                        Switch(
                          value: scene.isActive,
                          onChanged: (v) =>
                              _firestoreService.updateSceneActive(
                                  uid, scene.sceneId, v),
                        ),
                      // Manual trigger
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline,
                            color: Colors.green),
                        tooltip: 'Run now',
                        onPressed: () async {
                          await main_app.sceneScheduler.executeScene(
                              scene.sceneId, uid);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('"${scene.name}" activated'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      // Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => _firestoreService.deleteScene(
                            uid, scene.sceneId),
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

// ── Add Scene full screen ──────────────────────────────────────

class _AddSceneScreen extends StatefulWidget {
  final String uid;
  final FirestoreService firestoreService;

  const _AddSceneScreen({
    required this.uid,
    required this.firestoreService,
  });

  @override
  State<_AddSceneScreen> createState() => _AddSceneScreenState();
}

class _AddSceneScreenState extends State<_AddSceneScreen> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'Morning';
  HomeModel? _selectedHome;
  final List<SceneAction> _actions = [];
  bool _isScheduled = false;
  TimeOfDay _scheduledTime = TimeOfDay.now();
  final List<int> _selectedDays = [];
  bool _saving = false;

  final List<Map<String, dynamic>> _sceneIcons = [
    {'label': 'Morning',  'icon': Icons.wb_sunny_outlined},
    {'label': 'Night',    'icon': Icons.nights_stay_outlined},
    {'label': 'Movie',    'icon': Icons.movie_outlined},
    {'label': 'Dinner',   'icon': Icons.restaurant_outlined},
    {'label': 'Sleep',    'icon': Icons.bed},
    {'label': 'Party',    'icon': Icons.celebration},
    {'label': 'Away',     'icon': Icons.directions_walk},
    {'label': 'Welcome',  'icon': Icons.waving_hand},
  ];

  final _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  void _showAddActionSheet() async {
    final homes = await widget.firestoreService
        .streamHomes(widget.uid)
        .first;
    if (!mounted) return;

    // Pick home first if not set
    if (_selectedHome == null && homes.length == 1) {
      setState(() => _selectedHome = homes.first);
    } else if (_selectedHome == null && homes.length > 1) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select home'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: homes
                .map((h) => ListTile(
                      title: Text(h.homeName),
                      onTap: () {
                        setState(() => _selectedHome = h);
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
          ),
        ),
      );
    }

    if (_selectedHome == null || !mounted) return;

    // Stream devices for selected home
    final devices = await widget.firestoreService
        .streamDevices(widget.uid)
        .first;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select switches for this scene',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                children: devices.map((device) {
                  return ExpansionTile(
                    leading:
                        const Icon(Icons.devices_outlined),
                    title: Text(device.deviceName),
                    children: device.switches
                        .asMap()
                        .entries
                        .map((entry) {
                      final i = entry.key;
                      final sw = entry.value;
                      final macId = device.macId;
                      final existing = macId != null && macId.isNotEmpty
                          ? _actions.where((a) =>
                          a.macId == macId &&
                          a.switchIndex == i).firstOrNull
                          : null;

                      return StatefulBuilder(
                        builder: (context, setRow) => ListTile(
                          leading: Icon(
                            IconData(
                              int.tryParse(sw.icon) ??
                                  Icons.toggle_on.codePoint,
                              fontFamily: 'MaterialIcons',
                            ),
                            size: 18,
                          ),
                          title: Text(sw.label),
                          trailing: existing != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      existing.targetState
                                          ? 'ON'
                                          : 'OFF',
                                      style: TextStyle(
                                        color: existing.targetState
                                            ? Colors.green
                                            : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red),
                                      onPressed: () {
                                        final macId = device.macId;
                                        if (macId != null && macId.isNotEmpty) {
                                          setState(() => _actions
                                              .removeWhere((a) =>
                                                  a.macId ==
                                                      macId &&
                                                  a.switchIndex == i));
                                          setRow(() {});
                                        }
                                      },
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        final macId = device.macId;
                                        if (macId != null && macId.isNotEmpty) {
                                          setState(() =>
                                              _actions.add(SceneAction(
                                                macId: macId,
                                                deviceName:
                                                    device.deviceName,
                                                switchIndex: i,
                                                switchLabel: sw.label,
                                                targetState: true,
                                              )));
                                          setRow(() {});
                                        }
                                      },
                                      child: const Text('ON',
                                          style: TextStyle(
                                              color: Colors.green)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        final macId = device.macId;
                                        if (macId != null && macId.isNotEmpty) {
                                          setState(() =>
                                              _actions.add(SceneAction(
                                                macId: macId,
                                                deviceName:
                                                    device.deviceName,
                                                switchIndex: i,
                                                switchLabel: sw.label,
                                                targetState: false,
                                              )));
                                          setRow(() {});
                                        }
                                      },
                                      child: const Text('OFF',
                                          style: TextStyle(
                                              color: Colors.grey)),
                                    ),
                                  ],
                                ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveScene() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a scene name')),
      );
      return;
    }
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one action')),
      );
      return;
    }

    setState(() => _saving = true);

    final timeStr = _isScheduled
        ? '${_scheduledTime.hour.toString().padLeft(2, '0')}:${_scheduledTime.minute.toString().padLeft(2, '0')}'
        : null;

    final sceneRef = await widget.firestoreService.addScene(
      widget.uid,
      SceneModel(
        sceneId: '',
        name: _nameController.text.trim(),
        icon: _selectedIcon,
        homeId: _selectedHome?.homeId ?? '',
        actions: _actions,
        isScheduled: _isScheduled,
        scheduledTime: timeStr,
        scheduledDays: _isScheduled ? _selectedDays : [],
        isActive: true,
      ),
    );

    // Schedule the scene if it's scheduled
    if (_isScheduled) {
      final scene = SceneModel(
        sceneId: sceneRef,
        name: _nameController.text.trim(),
        icon: _selectedIcon,
        homeId: _selectedHome?.homeId ?? '',
        actions: _actions,
        isScheduled: _isScheduled,
        scheduledTime: timeStr,
        scheduledDays: _selectedDays,
        isActive: true,
      );
      await main_app.sceneScheduler.scheduleScene(scene);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Scene'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveScene,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Scene name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Scene name',
              hintText: 'e.g. Good Night',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Icon picker
          const Text('Icon',
              style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _sceneIcons.map((item) {
              final isSelected = _selectedIcon == item['label'];
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedIcon = item['label'] as String),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item['icon'] as IconData,
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey),
                      const SizedBox(height: 2),
                      Text(item['label'] as String,
                          style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Actions',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              TextButton.icon(
                onPressed: _showAddActionSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_actions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text('No actions yet — tap Add',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ..._actions.map((action) => ListTile(
                  dense: true,
                  leading: Icon(
                    action.targetState
                        ? Icons.toggle_on
                        : Icons.toggle_off,
                    color: action.targetState
                        ? Colors.green
                        : Colors.grey,
                  ),
                  title: Text(
                      '${action.deviceName} — ${action.switchLabel}'),
                  subtitle: Text(
                    action.targetState ? 'Turn ON' : 'Turn OFF',
                    style: TextStyle(
                        color: action.targetState
                            ? Colors.green
                            : Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => setState(() => _actions.remove(action)),
                  ),
                )),

          const SizedBox(height: 24),

          // Schedule toggle
          Card(
            child: SwitchListTile(
              value: _isScheduled,
              onChanged: (v) => setState(() => _isScheduled = v),
              title: const Text('Schedule this scene'),
              subtitle: const Text('Run automatically at a set time'),
              secondary: const Icon(Icons.schedule),
            ),
          ),

          if (_isScheduled) ...[
            const SizedBox(height: 12),
            // Time picker
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200)),
              leading: const Icon(Icons.access_time),
              title: const Text('Time'),
              trailing: Text(
                _scheduledTime.format(context),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onTap: _pickTime,
            ),
            const SizedBox(height: 12),
            // Day picker
            const Text('Repeat on',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1;
                final isSelected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(_dayLabels[i]),
                  selected: isSelected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                );
              }),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}