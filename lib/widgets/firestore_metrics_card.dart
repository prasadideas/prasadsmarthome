import 'package:flutter/material.dart';
import '../services/firestore_metrics.dart';

class FirestoreMetricsCard extends StatefulWidget {
  final String screenLabel;

  const FirestoreMetricsCard({super.key, this.screenLabel = 'This Screen'});

  @override
  State<FirestoreMetricsCard> createState() => _FirestoreMetricsCardState();
}

class _FirestoreMetricsCardState extends State<FirestoreMetricsCard> {
  final FirestoreMetrics _firestoreMetrics = FirestoreMetrics.instance;
  late FirestoreUsageSnapshot _baselineMetrics;

  @override
  void initState() {
    super.initState();
    _baselineMetrics = _firestoreMetrics.snapshot();
  }

  int _delta(int current, int baseline) {
    final difference = current - baseline;
    return difference < 0 ? 0 : difference;
  }

  List<MapEntry<String, int>> _topEntries(Map<String, int> sourceMap) {
    final entries = sourceMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.length <= 4) return entries;
    return entries.take(4).toList();
  }

  Widget _buildMetricTile(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceList(String title, List<MapEntry<String, int>> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text(
            'No activity yet',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentWrites(List<String> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Write Events',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text(
            'No write events recorded',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                entry,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _firestoreMetrics,
      builder: (context, _) {
        final snapshot = _firestoreMetrics.snapshot();
        final screenReads = _delta(
          snapshot.estimatedReads,
          _baselineMetrics.estimatedReads,
        );
        final screenWrites = _delta(snapshot.writes, _baselineMetrics.writes);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Firestore Usage',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _firestoreMetrics.reset();
                        setState(() {
                          _baselineMetrics = _firestoreMetrics.snapshot();
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Estimated from app-side Firestore calls. One-time reads come from get calls. Listener reads come from snapshot deliveries.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildMetricTile(
                      'Session Reads',
                      snapshot.estimatedReads,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildMetricTile(
                      'Session Writes',
                      snapshot.writes,
                      Colors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMetricTile(
                      'One-time Reads',
                      snapshot.oneTimeReads,
                      Colors.indigo,
                    ),
                    const SizedBox(width: 12),
                    _buildMetricTile(
                      'Listener Reads',
                      snapshot.listenerReads,
                      Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMetricTile(
                      '${widget.screenLabel} Reads',
                      screenReads,
                      Colors.teal,
                    ),
                    const SizedBox(width: 12),
                    _buildMetricTile(
                      '${widget.screenLabel} Writes',
                      screenWrites,
                      Colors.deepOrange,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSourceList(
                  'Top Read Sources',
                  _topEntries(snapshot.readsBySource),
                ),
                const SizedBox(height: 12),
                _buildSourceList(
                  'Top Write Sources',
                  _topEntries(snapshot.writesBySource),
                ),
                const SizedBox(height: 12),
                _buildRecentWrites(snapshot.recentWriteEvents),
              ],
            ),
          ),
        );
      },
    );
  }
}
