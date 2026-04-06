import 'package:flutter/foundation.dart';

class FirestoreUsageSnapshot {
  final int estimatedReads;
  final int oneTimeReads;
  final int listenerReads;
  final int writes;
  final Map<String, int> readsBySource;
  final Map<String, int> writesBySource;
  final List<String> recentWriteEvents;

  const FirestoreUsageSnapshot({
    required this.estimatedReads,
    required this.oneTimeReads,
    required this.listenerReads,
    required this.writes,
    required this.readsBySource,
    required this.writesBySource,
    required this.recentWriteEvents,
  });
}

class FirestoreMetrics extends ChangeNotifier {
  static const int _maxRecentWriteEvents = 12;

  FirestoreMetrics._();

  static final FirestoreMetrics instance = FirestoreMetrics._();

  int _oneTimeReads = 0;
  int _listenerReads = 0;
  int _writes = 0;
  final Map<String, int> _readsBySource = {};
  final Map<String, int> _writesBySource = {};
  final List<String> _recentWriteEvents = [];

  int get estimatedReads => _oneTimeReads + _listenerReads;
  int get oneTimeReads => _oneTimeReads;
  int get listenerReads => _listenerReads;
  int get writes => _writes;

  FirestoreUsageSnapshot snapshot() {
    return FirestoreUsageSnapshot(
      estimatedReads: estimatedReads,
      oneTimeReads: _oneTimeReads,
      listenerReads: _listenerReads,
      writes: _writes,
      readsBySource: Map<String, int>.from(_readsBySource),
      writesBySource: Map<String, int>.from(_writesBySource),
      recentWriteEvents: List<String>.from(_recentWriteEvents),
    );
  }

  void recordOneTimeRead(String source, {int count = 1}) {
    if (count <= 0) return;
    _oneTimeReads += count;
    _readsBySource.update(
      source,
      (value) => value + count,
      ifAbsent: () => count,
    );
    notifyListeners();
  }

  void recordListenerRead(String source, {int count = 1}) {
    if (count <= 0) return;
    _listenerReads += count;
    _readsBySource.update(
      source,
      (value) => value + count,
      ifAbsent: () => count,
    );
    notifyListeners();
  }

  void recordWrite(String source, {int count = 1}) {
    if (count <= 0) return;
    _writes += count;
    _writesBySource.update(
      source,
      (value) => value + count,
      ifAbsent: () => count,
    );

    final entry = '${DateTime.now().toIso8601String()}  $source  +$count';
    _recentWriteEvents.insert(0, entry);
    if (_recentWriteEvents.length > _maxRecentWriteEvents) {
      _recentWriteEvents.removeLast();
    }

    if (kDebugMode) {
      debugPrint(
        '[FirestoreMetrics] WRITE source=$source count=$count totalWrites=$_writes',
      );
    }

    notifyListeners();
  }

  void reset() {
    _oneTimeReads = 0;
    _listenerReads = 0;
    _writes = 0;
    _readsBySource.clear();
    _writesBySource.clear();
    _recentWriteEvents.clear();
    notifyListeners();
  }
}
