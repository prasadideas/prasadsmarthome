import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/home_model.dart';
import '../services/firestore_service.dart';
import '../widgets/firestore_metrics_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  String? _favouriteHomeId;

  @override
  void initState() {
    super.initState();
    _loadFavourite();
  }

  Future<void> _loadFavourite() async {
    final userData = await _firestoreService.getUser(uid);
    if (!mounted) return;
    setState(() {
      _favouriteHomeId = userData?['favouriteHomeId'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FirestoreMetricsCard(screenLabel: 'Settings'),
          const SizedBox(height: 24),

          // ── Favourite home section ──────────────────────────
          const Text(
            'Default Home',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'This home opens automatically when you launch the app.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          StreamBuilder<List<HomeModel>>(
            stream: _firestoreService.streamHomes(uid),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final homes = snapshot.data!;
              if (homes.isEmpty) {
                return const Text(
                  'No homes added yet.',
                  style: TextStyle(color: Colors.grey),
                );
              }

              return Column(
                children: homes.map((home) {
                  final isSelected = home.homeId == _favouriteHomeId;
                  return Card(
                    elevation: isSelected ? 3 : 1,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Colors.amber.shade100
                            : Colors.grey.shade100,
                        child: Icon(
                          isSelected ? Icons.star : Icons.home_outlined,
                          color: isSelected ? Colors.amber : Colors.grey,
                        ),
                      ),
                      title: Text(
                        home.homeName,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(home.address),
                      trailing: isSelected
                          ? const Chip(
                              label: Text(
                                'Default',
                                style: TextStyle(fontSize: 12),
                              ),
                              backgroundColor: Colors.amber,
                            )
                          : TextButton(
                              onPressed: () async {
                                await _firestoreService.setFavouriteHome(
                                  uid,
                                  home.homeId,
                                );
                                setState(() {
                                  _favouriteHomeId = home.homeId;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${home.homeName} set as default home',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Set as default'),
                            ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // ── Clear favourite ─────────────────────────────────
          if (_favouriteHomeId != null)
            ListTile(
              leading: const Icon(Icons.star_border, color: Colors.grey),
              title: const Text('Clear default home'),
              subtitle: const Text('App will show all homes on launch'),
              onTap: () async {
                await _firestoreService.setFavouriteHome(uid, '');
                setState(() => _favouriteHomeId = null);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Default home cleared')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
