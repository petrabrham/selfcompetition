import 'package:flutter/material.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../services/ride_service.dart';

// Screens - Ride Statistics screen
class RideStatisticsScreen extends StatefulWidget {
  const RideStatisticsScreen({super.key});

  @override
  State<RideStatisticsScreen> createState() => _RideStatisticsScreenState();
}

class _RideStatisticsScreenState extends State<RideStatisticsScreen> {
  Timer? _liveRefreshTimer;
  Future<_StatisticsData>? _staticStatisticsFuture;
  int? _cachedRouteId;
  bool? _cachedUseCleanTime;
  _StatisticsData? _liveBaseStatistics;
  bool _isLoadingLiveCache = false;
  bool _isRefreshingLiveComparison = false;
  List<_ComparisonRow>? _liveRows;
  Duration? _liveElapsed;

  @override
  void initState() {
    super.initState();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !RideService.instance.isRecording) return;
      _ensureLiveCache();
      _refreshLiveComparison();
    });
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  Future<_StatisticsData> _loadStatistics() async {
    final settings = await DatabaseService.instance.getSettings();
    final showCleanDuration =
        (settings?['show_clean_duration'] as num?)?.toInt() != 0;
    final routeId = await DatabaseService.instance.getActiveRouteId();
    if (routeId == null) {
      return _StatisticsData([], showCleanDuration);
    }
    final rides = (await DatabaseService.instance.getRidesByRoute(routeId)).toList();
    rides.sort(
      (a, b) => _durationOf(a, showCleanDuration)
          .compareTo(_durationOf(b, showCleanDuration)),
    );
    if (!RideService.instance.isRecording) {
      return _StatisticsData(rides, showCleanDuration);
    }

    return _StatisticsData(rides, showCleanDuration);
  }

  Future<void> _ensureLiveCache() async {
    if (_isLoadingLiveCache) return;
    final settings = await DatabaseService.instance.getSettings();
    final showCleanDuration =
        (settings?['show_clean_duration'] as num?)?.toInt() != 0;
    final routeId = await DatabaseService.instance.getActiveRouteId();
    if (routeId == null) return;
    if (_cachedRouteId == routeId &&
        _cachedUseCleanTime == showCleanDuration &&
        _liveBaseStatistics != null) {
      return;
    }

    _isLoadingLiveCache = true;
    try {
      final rides = (await DatabaseService.instance.getRidesByRoute(routeId)).toList();
      rides.sort(
        (a, b) => _durationOf(a, showCleanDuration)
            .compareTo(_durationOf(b, showCleanDuration)),
      );
      await _materializeRouteTimeline(routeId);
      if (!mounted) return;
      setState(() {
        _cachedRouteId = routeId;
        _cachedUseCleanTime = showCleanDuration;
        _liveBaseStatistics = _StatisticsData(rides, showCleanDuration);
      });
      await _refreshLiveComparison();
    } finally {
      _isLoadingLiveCache = false;
    }
  }

  _StatisticsData _buildLiveStatistics() {
    final base = _liveBaseStatistics!;
    final showCleanDuration = base.showCleanDuration;

    final elapsed = showCleanDuration
        ? RideService.instance.currentCleanDuration
        : RideService.instance.currentRecordedDuration;
    return _StatisticsData(
      base.rides,
      showCleanDuration,
      liveRows: _liveRows ?? const [],
      liveElapsed: _liveElapsed ?? elapsed,
    );
  }

  Future<void> _materializeRouteTimeline(int routeId) async {
    await RideService.instance.recalculateRouteRides(routeId);
  }

  Future<void> _refreshLiveComparison() async {
    if (_isRefreshingLiveComparison) return;
    final base = _liveBaseStatistics;
    final routeId = _cachedRouteId;
    if (!mounted || base == null || routeId == null) return;
    _isRefreshingLiveComparison = true;
    try {
      final elapsed = base.showCleanDuration
          ? RideService.instance.currentCleanDuration
          : RideService.instance.currentRecordedDuration;
      final distances =
          await DatabaseService.instance.getRouteDistancesAtElapsedTime(
        routeId,
        elapsed.inMilliseconds / 1000,
        useCleanTime: base.showCleanDuration,
      );
      final rows = distances.map((row) => _ComparisonRow(
            label: _formatDate(row['start_time'] as String?),
            distanceMeters: (row['distance_meters'] as num).toDouble(),
            isCurrentRide: false,
            averageSpeedKmh: 0,
          )).toList();
      rows.add(_ComparisonRow(
        label: 'Current ride',
        distanceMeters:
            RideService.instance.currentDistanceAtElapsedTime(base.showCleanDuration),
        isCurrentRide: true,
        averageSpeedKmh: 0,
      ));
      rows.sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
      if (mounted) {
        setState(() {
          _liveRows = rows;
          _liveElapsed = elapsed;
        });
      }
    } finally {
      _isRefreshingLiveComparison = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (RideService.instance.isRecording) {
      _ensureLiveCache();
      if (_liveBaseStatistics == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildContent(context, _buildLiveStatistics());
    }
    if (_liveBaseStatistics != null) {
      _staticStatisticsFuture = null;
    }
    _liveBaseStatistics = null;
    _cachedRouteId = null;
    _cachedUseCleanTime = null;
    _liveRows = null;
    _liveElapsed = null;
    _staticStatisticsFuture ??= _loadStatistics();
    return FutureBuilder<_StatisticsData>(
      future: _staticStatisticsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        return _buildContent(
          context,
          snapshot.data ?? const _StatisticsData([], true),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, _StatisticsData statistics) {
    final rides = statistics.rides;
    if (rides.isEmpty && statistics.liveRows == null) {
      return const Center(
        child: Text('Select an active route in Route Management'),
      );
    }

    final bestDuration = rides.isEmpty
        ? 0
        : _durationOf(rides.first, statistics.showCleanDuration);
    final liveRows = statistics.liveRows;
    return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          children: [
            Text(
              'Ride Statistics',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
              horizontalMargin: 4,
              columnSpacing: 4,
              headingRowHeight: 32,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 42,
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              dataTextStyle: const TextStyle(fontSize: 10),
              columns: liveRows == null
                  ? [
                      const DataColumn(label: Text('#')),
                      const DataColumn(label: Text('Date')),
                      DataColumn(label: Text(statistics.showCleanDuration ? 'Clean time' : 'Recorded time')),
                      const DataColumn(label: Text('Distance')),
                      const DataColumn(label: Text('Average')),
                      const DataColumn(label: Text('Loss')),
                    ]
                  : [
                      const DataColumn(label: Text('#')),
                      const DataColumn(label: Text('Ride')),
                      DataColumn(label: Text(statistics.showCleanDuration ? 'Clean time' : 'Recorded time')),
                      const DataColumn(label: Text('Distance')),
                    ],
                rows: liveRows == null
                    ? rides.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ride = entry.value;
                  final duration = _durationOf(ride, statistics.showCleanDuration);
                  final loss = duration - bestDuration;
                  return DataRow(cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(_formatDate(ride['start_time'] as String?))),
                    DataCell(Text(_formatDuration(duration))),
                    DataCell(Text('${_distanceKm(ride).toStringAsFixed(1)} km')),
                    DataCell(Text('${_averageSpeed(ride).toStringAsFixed(1)} km/h')),
                    DataCell(Text(_formatDuration(loss))),
                  ]);
                }).toList()
                    : liveRows.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        return DataRow(
                          color: row.isCurrentRide
                              ? WidgetStatePropertyAll(
                                  Theme.of(context).colorScheme.primaryContainer,
                                )
                              : null,
                          cells: [
                            DataCell(Text('${index + 1}')),
                            DataCell(Text(row.label)),
                            DataCell(Text(_formatDuration(statistics.liveElapsed!.inSeconds))),
                            DataCell(Text('${(row.distanceMeters / 1000).toStringAsFixed(2)} km')),
                          ],
                        );
                      }).toList(),
              ),
            ),
          ],
        );
  }

  int _durationOf(Map<String, dynamic> ride, bool preferCleanDuration) {
    final stored = preferCleanDuration
        ? (ride['clean_duration_seconds'] as num?)?.toInt() ??
            (ride['recorded_duration_seconds'] as num?)?.toInt()
        : (ride['recorded_duration_seconds'] as num?)?.toInt();
    if (stored != null) return stored;
    final legacy = (ride['duration_seconds'] as num?)?.toInt();
    if (legacy != null) return legacy;
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

class _StatisticsData {
  final List<Map<String, dynamic>> rides;
  final bool showCleanDuration;
  final List<_ComparisonRow>? liveRows;
  final Duration? liveElapsed;

  const _StatisticsData(
    this.rides,
    this.showCleanDuration, {
    this.liveRows,
    this.liveElapsed,
  });
}


class _ComparisonRow {
  final String label;
  final double distanceMeters;
  final bool isCurrentRide;
  final double averageSpeedKmh;

  const _ComparisonRow({
    required this.label,
    required this.distanceMeters,
    required this.isCurrentRide,
    required this.averageSpeedKmh,
  });
}
