import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_shell.dart';
import 'screens/login_screen.dart';
import 'services/firestore_service.dart';
import 'services/mqtt_service.dart';
import 'services/mqtt_provider.dart';
import 'services/scene_scheduler.dart';
import 'theme_provider.dart';

// Singleton MQTT service to ensure only one instance exists
late final MqttService _mqttService;
late final SceneScheduler sceneScheduler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  final firestoreService = FirestoreService();
  _mqttService = MqttService(firestoreService: firestoreService);
  sceneScheduler = SceneScheduler(
    firestoreService: firestoreService,
    mqttService: _mqttService,
  );
  await sceneScheduler.initialize();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _loadThemeFromUser(user.uid);
      } else {
        themeNotifier.value = ThemeMode.system;
      }
    });
  }

  Future<void> _loadThemeFromUser(String uid) async {
    final userData = await _firestoreService.getUser(uid);
    if (userData == null) return;
    final mode = userData['themeMode'] as String?;
    if (mode != null) {
      themeNotifier.value = _themeModeFromString(mode);
    }
  }

  ThemeMode _themeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MqttProvider(
          mqtt: _mqttService,
          child: MaterialApp(
            title: 'SmartHome',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorSchemeSeed: Colors.blue,
              useMaterial3: true,
            ),
            themeMode: themeMode,
            // Auth gate — shows login or main shell
            home: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasData) {
                  return const MainShell(); // logged in
                }
                return LoginScreen(); // not logged in
              },
            ),
          ),
        );
      },
    );
  }
}
