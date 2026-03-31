import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../models/home_model.dart';
import '../theme_provider.dart';

class MeTab extends StatefulWidget {
  const MeTab({super.key});

  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  String? _favouriteHomeId;
  Map<String, dynamic>? _userData;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final data = await _firestoreService.getUser(uid);
    if (!mounted) return;
    setState(() {
      _userData = data;
      _favouriteHomeId = data?['favouriteHomeId'];
      final theme = data?['themeMode'] as String?;
      _themeMode = _themeModeFromString(theme);
    });
  }

  ThemeMode _themeModeFromString(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
    });
    themeNotifier.value = mode;
    await _firestoreService.setUserThemeMode(uid, _themeModeToString(mode));
  }

  // ── Section header ─────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ── Menu tile ──────────────────────────────────────────────

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (iconColor ?? Colors.blue).withOpacity(0.1),
        child: Icon(icon, color: iconColor ?? Colors.blue, size: 20),
      ),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = _userData?['displayName'] ?? user?.displayName ?? 'User';
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        children: [
          // ── Profile card ────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Home management ─────────────────────────────────
          _sectionHeader('Home Management'),

          StreamBuilder<List<HomeModel>>(
            stream: _firestoreService.streamHomes(uid),
            builder: (context, snapshot) {
              final homes = snapshot.data ?? [];
              return Column(
                children: [
                  // Default home picker
                  _tile(
                    icon: Icons.star_outline,
                    iconColor: Colors.amber,
                    title: 'Default Home',
                    subtitle:
                        homes
                            .where((h) => h.homeId == _favouriteHomeId)
                            .firstOrNull
                            ?.homeName ??
                        'Not set',
                    onTap: () => _showDefaultHomePicker(homes),
                  ),
                  // All homes
                  ...homes.map(
                    (home) => _tile(
                      icon: Icons.home_outlined,
                      iconColor: Colors.blue,
                      title: home.homeName,
                      subtitle: home.address,
                      onTap: () {
                        // Navigate to home's rooms
                      },
                    ),
                  ),
                  // Add home
                  _tile(
                    icon: Icons.add_home_outlined,
                    iconColor: Colors.green,
                    title: 'Add New Home',
                    trailing: const Icon(Icons.add),
                    onTap: _showAddHomeDialog,
                  ),
                ],
              );
            },
          ),

          // ── App settings ────────────────────────────────────
          _sectionHeader('App'),

          _tile(
            icon: Icons.brightness_6,
            iconColor: Colors.deepPurple,
            title: 'Theme',
            subtitle: _themeMode == ThemeMode.light
                ? 'Light'
                : _themeMode == ThemeMode.dark
                ? 'Dark'
                : 'System',
            onTap: _showThemePicker,
          ),

          _tile(
            icon: Icons.help_outline,
            iconColor: Colors.purple,
            title: 'Help & Support',
            onTap: () {},
          ),
          _tile(
            icon: Icons.privacy_tip_outlined,
            iconColor: Colors.teal,
            title: 'Privacy Policy',
            onTap: () {},
          ),
          _tile(
            icon: Icons.description_outlined,
            iconColor: Colors.orange,
            title: 'Terms of Service',
            onTap: () {},
          ),
          _tile(
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            title: 'About',
            subtitle: 'Version 1.0.0',
            onTap: () {},
          ),

          // ── Account ─────────────────────────────────────────
          _sectionHeader('Account'),

          _tile(
            icon: Icons.logout,
            iconColor: Colors.red,
            title: 'Logout',
            trailing: const SizedBox.shrink(),
            onTap: () => _confirmLogout(),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Default home picker ────────────────────────────────────

  void _showDefaultHomePicker(List<HomeModel> homes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Set Default Home',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ...homes.map(
              (home) => ListTile(
                leading: Icon(
                  home.homeId == _favouriteHomeId
                      ? Icons.star
                      : Icons.star_outline,
                  color: home.homeId == _favouriteHomeId
                      ? Colors.amber
                      : Colors.grey,
                ),
                title: Text(home.homeName),
                subtitle: Text(home.address),
                onTap: () async {
                  await _firestoreService.setFavouriteHome(uid, home.homeId);
                  setState(() => _favouriteHomeId = home.homeId);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.clear, color: Colors.red),
              title: const Text('Clear default'),
              onTap: () async {
                await _firestoreService.setFavouriteHome(uid, '');
                setState(() => _favouriteHomeId = null);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Theme',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System Default'),
              value: ThemeMode.system,
              groupValue: _themeMode,
              onChanged: (value) {
                if (value != null) {
                  _setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (value) {
                if (value != null) {
                  _setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: _themeMode,
              onChanged: (value) {
                if (value != null) {
                  _setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Add home dialog ────────────────────────────────────────

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

  // ── Logout confirmation ────────────────────────────────────

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
