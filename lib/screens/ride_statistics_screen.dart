import 'package:flutter/material.dart';
import '../services/database_service.dart';

// Screens - Ride Statistics screen
class RideStatisticsScreen extends StatefulWidget {
  const RideStatisticsScreen({super.key});

  @override
  State<RideStatisticsScreen> createState() => _RideStatisticsScreenState();
}

class _RideStatisticsScreenState extends State<RideStatisticsScreen> {
  Future<List<Map<String, dynamic>>> _loadRides() async {
    final routeId = await DatabaseService.instance.getActiveRouteId();
    if (routeId == null) return [];
    final rides = (await DatabaseService.instance.getRidesByRoute(routeId)).toList();
    rides.sort((a, b) => _durationOf(a).compareTo(_durationOf(b)));
    return rides;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadRides(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final rides = snapshot.data ?? [];
        if (rides.isEmpty) {
          return const Center(
            child: Text('Select an active route in Route Management'),
          );
        }

        final bestDuration = _durationOf(rides.first);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          children: [
            Text(
              'Ride Statistics',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            DataTable(
              horizontalMargin: 4,
              columnSpacing: 4,
              headingRowHeight: 32,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 42,
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              dataTextStyle: const TextStyle(fontSize: 10),
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Datum')),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Distance')),
                DataColumn(label: Text('Average')),
                DataColumn(label: Text('Loss')),
              ],
                rows: rides.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ride = entry.value;
                  final duration = _durationOf(ride);
                  final loss = duration - bestDuration;
                  return DataRow(cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(_formatDate(ride['start_time'] as String?))),
                    DataCell(Text(_formatDuration(duration))),
                    DataCell(Text('${_distanceKm(ride).toStringAsFixed(1)} km')),
                    DataCell(Text('${_averageSpeed(ride).toStringAsFixed(1)} km/h')),
                    DataCell(Text(_formatDuration(loss))),
                  ]);
                }).toList(),
            ),
          ],
        );
      },
    );
  }

  int _durationOf(Map<String, dynamic> ride) {
    final stored = (ride['duration_seconds'] as num?)?.toInt();
    if (stored != null) return stored;
    final start = DateTime.tryParse(ride['start_time'] as String? ?? '');
    final end = DateTime.tryParse(ride['end_time'] as String? ?? '');
    return start == null || end == null ? 0 : end.difference(start).inSeconds;
  }

  double _distanceKm(Map<String, dynamic> ride) =>
      ((ride['distance_meters'] as num?)?.toDouble() ?? 0) / 1000;

  double _averageSpeed(Map<String, dynamic> ride) =>
      (ride['avg_speed_kmh'] as num?)?.toDouble() ?? 0;

  String _formatDate(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return 'N/A';
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-'
        '${twoDigits(date.month)}-${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds < 0 ? 0 : seconds);
    return '${duration.inHours.toString().padLeft(2, '0')}:${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}';
  }
}
