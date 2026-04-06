import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/scene_model.dart';
import '../services/firestore_service.dart';
import '../services/mqtt_service.dart';

class SceneScheduler {
  static const String _taskName = 'scene_scheduler_task';
  static const String _channelId = 'scene_scheduler';
  static const String _channelName = 'Scene Scheduler';

  final FirestoreService _firestoreService;
  final MqttService _mqttService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;

  SceneScheduler({
    required FirestoreService firestoreService,
    required MqttService mqttService,
  })  : _firestoreService = firestoreService,
        _mqttService = mqttService,
        _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Initialize notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(settings);

    // Initialize WorkManager
    await Workmanager().initialize(_callbackDispatcher, isInDebugMode: true);

    // Register periodic task for scene checking
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15), // Check every 15 minutes
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  @pragma('vm:entry-point')
  static void _callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      try {
        // This runs in background isolate
        await _executeScheduledScenes();
        return true;
      } catch (e) {
        debugPrint('Scene scheduler task failed: $e');
        return false;
      }
    });
  }

  static Future<void> _executeScheduledScenes() async {
    // This would need to be implemented to run in background
    // For now, we'll implement the foreground version
    debugPrint('Checking for scheduled scenes...');
  }

  Future<void> scheduleScene(SceneModel scene) async {
    if (!scene.isScheduled || scene.scheduledTime == null || scene.scheduledDays.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final timeParts = scene.scheduledTime!.split(':');
    final scheduledHour = int.parse(timeParts[0]);
    final scheduledMinute = int.parse(timeParts[1]);

    for (final day in scene.scheduledDays) {
      final nextExecution = _getNextExecutionDate(now, day, scheduledHour, scheduledMinute);
      if (nextExecution != null) {
        await _scheduleNotification(scene, nextExecution);
      }
    }
  }

  Future<void> cancelSceneSchedule(String sceneId) async {
    await _notificationsPlugin.cancel(int.parse(sceneId.hashCode.toString()));
  }

  DateTime? _getNextExecutionDate(DateTime now, int weekday, int hour, int minute) {
    // weekday: 1=Monday, 7=Sunday
    final daysUntilTarget = (weekday - now.weekday + 7) % 7;
    final targetDate = now.add(Duration(days: daysUntilTarget == 0 ? 7 : daysUntilTarget));

    final scheduledTime = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hour,
      minute,
    );

    // If the time has already passed today, schedule for next week
    if (scheduledTime.isBefore(now) && daysUntilTarget == 0) {
      return scheduledTime.add(const Duration(days: 7));
    }

    return scheduledTime;
  }

  Future<void> _scheduleNotification(SceneModel scene, DateTime executionTime) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Scheduled scene execution',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      scene.sceneId.hashCode,
      'Scene Scheduled: ${scene.name}',
      'Executing scene at ${scene.scheduledTime}',
      tz.TZDateTime.from(executionTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> executeScene(String sceneId, String uid) async {
    try {
      // Get scene from Firestore
      final sceneDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scenes')
          .doc(sceneId)
          .get();

      if (!sceneDoc.exists) return;

      final scene = SceneModel.fromMap(sceneId, sceneDoc.data()!);

      // Execute each action
      for (final action in scene.actions) {
        _mqttService.publishCommand(
          macAddress: action.macId,
          switchIndex: action.switchIndex,
          isOn: action.targetState,
          type: 'toggle', // Could be enhanced to support other types
        );

        // Small delay between commands
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Show notification
      await _notificationsPlugin.show(
        sceneId.hashCode,
        'Scene Executed',
        '${scene.name} has been activated',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Scene execution notifications',
          ),
        ),
      );

      debugPrint('Executed scene: ${scene.name}');
    } catch (e) {
      debugPrint('Failed to execute scene $sceneId: $e');
    }
  }

  Future<void> checkAndExecuteScheduledScenes(String uid) async {
    try {
      final now = DateTime.now();
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final currentWeekday = now.weekday; // 1=Monday, 7=Sunday

      final scenesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scenes')
          .where('isScheduled', isEqualTo: true)
          .where('isActive', isEqualTo: true)
          .where('scheduledDays', arrayContains: currentWeekday)
          .get();

      for (final doc in scenesSnapshot.docs) {
        final scene = SceneModel.fromMap(doc.id, doc.data());
        if (scene.scheduledTime == currentTime) {
          await executeScene(scene.sceneId, uid);
        }
      }
    } catch (e) {
      debugPrint('Failed to check scheduled scenes: $e');
    }
  }
}