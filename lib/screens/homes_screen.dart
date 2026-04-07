import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../services/firestore_service.dart';
import 'rooms_screen.dart';
import 'devices_screen.dart';
import 'settings_screen.dart';

class HomesScreen extends StatefulWidget {
  final bool autoNavigate;
  const HomesScreen({super.key, this.autoNavigate = true});

  @override
  State<HomesScreen> createState() => _HomesScreenState();
}

class _HomesScreenState extends State<HomesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  String? _favouriteHomeId;
  bool _checkedFavourite = false;

  @override
  void initState() {
    super.initState();
    _loadFavourite();
  }

  Future<void> _seedDeviceTemplates() async {
    try {
      await _firestoreService.seedDeviceTemplates();
    } catch (error) {
      debugPrint('Device template sync failed: $error');
    }
  }

  // Load favourite home and navigate directly if set
  Future<void> _loadFavourite() async {
    //unawaited(_seedDeviceTemplates());
    final userData = await _firestoreService.getUser(uid);
    if (!mounted) return;
    setState(() {
      _favouriteHomeId = userData?['favouriteHomeId'];
      _checkedFavourite = true;
    });

    // If favourite is set, navigate directly to that home's rooms
    if (widget.autoNavigate &&
        _favouriteHomeId != null &&
        _favouriteHomeId!.isNotEmpty) {
      final homes = await _firestoreService.streamHomes(uid).first;
      final favourite = homes
          .where((h) => h.homeId == _favouriteHomeId)
          .firstOrNull;
      if (favourite != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RoomsScreen(home: favourite, isEntryPoint: true),
          ),
        );
      }
    }
  }

  // FAB — lets user pick: add room or add device
  void _showAddOptions(List<HomeModel> homes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'What do you want to add?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.home)),
              title: const Text('Add New Home'),
              onTap: () {
                Navigator.pop(context);
                _showAddHomeDialog();
              },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.devices)),
              title: const Text('Add Device to a Home'),
              subtitle: const Text('Pick a home first'),
              onTap: () {
                Navigator.pop(context);
                _showPickHomeForDevice(homes);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Pick which home to add device in
  void _showPickHomeForDevice(List<HomeModel> homes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pick a home',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...homes.map(
              (home) => ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(home.homeName),
                subtitle: Text(home.address),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DevicesScreen(home: home, room: null),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add home bottom sheet
  void _showAddHomeDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
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
                'Add New Home',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Home name',
                  hintText: 'e.g. Main Villa',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter a home name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'e.g. Hyderabad, Telangana',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter an address' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      await _firestoreService.addHome(
                        uid,
                        HomeModel(
                          homeId: '',
                          homeName: nameController.text.trim(),
                          address: addressController.text.trim(),
                        ),
                      );
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditHomeDialog(HomeModel home) {
    final nameController = TextEditingController(text: home.homeName);
    final addressController = TextEditingController(text: home.address);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
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
                'Edit Home',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Home name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter a home name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter an address' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      await _firestoreService.updateHome(
                        uid,
                        home.homeId,
                        nameController.text.trim(),
                        addressController.text.trim(),
                      );
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Update Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(HomeModel home) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Home'),
        content: Text('Delete "${home.homeName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _firestoreService.deleteHome(uid, home.homeId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show spinner while checking favourite
    if (!_checkedFavourite) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Homes'),
        actions: [
          // Settings icon
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              // Reload favourite when returning from settings
              _loadFavourite();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<HomeModel>>(
        stream: _firestoreService.streamHomes(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final homes = snapshot.data ?? [];

          if (homes.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.home_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No homes yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to add your first home',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: homes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final home = homes[index];
              final isFavourite = home.homeId == _favouriteHomeId;
              return Card(
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      isFavourite ? Icons.star : Icons.home,
                      color: isFavourite ? Colors.amber : null,
                    ),
                  ),
                  title: Text(
                    home.homeName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(home.address),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.blue,
                        ),
                        onPressed: () => _showEditHomeDialog(home),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _confirmDelete(home),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomsScreen(home: home),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<HomeModel>>(
        stream: _firestoreService.streamHomes(uid),
        builder: (context, snapshot) {
          final homes = snapshot.data ?? [];
          return FloatingActionButton(
            onPressed: () => _showAddOptions(homes),
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }
}
