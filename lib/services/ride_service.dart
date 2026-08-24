import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'gps_service.dart';
import 'database_service.dart';
import 'gpx_service.dart';
import 'gpx_processing_service.dart';

/// Model pro jednu najedtenou jízdu
class RecordedRide {
  final DateTime startTime;
  DateTime? endTime;
  final List<GPSPosition> positions;
  double totalDistance = 0.0; // v metrech
  double avgSpeed = 0.0; // v m/s
  String? userId;

  RecordedRide({
    required this.startTime,
    required this.positions,
  });

  /// Přidej novou pozici a aktualizuj vzdálenost
  void addPosition(GPSPosition position) {
    if (positions.isNotEmpty) {
      // Vypočítej vzdálenost k poslední pozici
      double distance = GPSService.calculateDistance(
        positions.last.latitude,
        positions.last.longitude,
        position.latitude,
        position.longitude,
      );
      totalDistance += distance;
    }
    positions.add(position);
  }

  /// Urči průměrnou rychlost
  void calculateStats() {
    if (endTime != null && positions.isNotEmpty) {
      Duration elapsed = endTime!.difference(startTime);
      double seconds = elapsed.inSeconds.toDouble();
      if (seconds > 0) {
        avgSpeed = totalDistance / seconds; // m/s
      }
    }
  }

  @override
  String toString() =>
      'RecordedRide(distance: ${(totalDistance / 1000).toStringAsFixed(2)} km, avgSpeed: ${(avgSpeed * 3.6).toStringAsFixed(2)} km/h)';
}

/// Ride Recording Service
/// Spravuje záznam jízdy - GPS tracking, počítání vzdálenosti a času
class RideService {
  static final RideService _instance = RideService._internal();

  static RideService get instance => _instance;

  RecordedRide? _currentRide;
  bool _isRecording = false;
  bool _isPaused = false;
  String? _lastError;
  int? _selectedRouteId;
  GPSPosition? _cleanStartPoint;
  double? _cleanStartRadiusMeters;
  int? _cleanStartIndex;
  double _pauseRadiusMeters = 20.0;
  int _pauseMinDurationSeconds = 90;

  RideService._internal();

  /// Aktuální nahrávající se jízda
  RecordedRide? get currentRide => _currentRide;

  /// Zda se právě nahrává
  bool get isRecording => _isRecording;

  bool get isPaused => _isPaused;

  String? get lastError => _lastError;

  int? get selectedRouteId => _selectedRouteId;

  bool get hasCleanRideStarted => _cleanStartIndex != null;

  Duration get currentCleanDuration {
    final ride = _currentRide;
    final startIndex = _cleanStartIndex;
    if (ride == null || startIndex == null || startIndex >= ride.positions.length) {
      return Duration.zero;
    }
    return _liveCleanDuration(ride.positions.sublist(startIndex));
  }

  Duration get currentRecordedDuration {
    final ride = _currentRide;
    if (ride == null || ride.positions.length < 2) return Duration.zero;
    return ride.positions.last.timestamp.difference(ride.positions.first.timestamp);
  }

  double currentDistanceAtElapsedTime(bool useCleanTime) {
    final ride = _currentRide;
    if (ride == null) return 0;
    final positions = useCleanTime && _cleanStartIndex != null
        ? ride.positions.sublist(_cleanStartIndex!)
        : ride.positions;
    final elapsed = useCleanTime ? currentCleanDuration : currentRecordedDuration;
    return GpxProcessingService.instance.distanceAtElapsedTime(
      positions,
      elapsed: elapsed,
      useCleanTime: useCleanTime,
      pauseRadiusMeters: _pauseRadiusMeters,
      minimumPauseDurationSeconds: _pauseMinDurationSeconds,
    );
  }

  Future<double> historicalDistanceAtElapsedTime(
    Map<String, dynamic> ride,
    Duration elapsed, {
    required bool useCleanTime,
  }) async {
    final fileName = ride['gpx_file_path'] as String?;
    if (fileName == null || fileName.isEmpty) return 0;
    final allPositions = await GpxService.instance.loadRide(fileName);
    if (allPositions.length < 2) return 0;
    final startTime = DateTime.tryParse(ride['start_time'] as String? ?? '');
    final endTime = DateTime.tryParse(ride['end_time'] as String? ?? '');
    final trimmedPositions = allPositions.where((position) {
      final afterStart = startTime == null || !position.timestamp.isBefore(startTime);
      final beforeEnd = endTime == null || !position.timestamp.isAfter(endTime);
      return afterStart && beforeEnd;
    }).toList();
    final positions = trimmedPositions.length >= 2
        ? trimmedPositions
        : allPositions;
    if (kDebugMode && trimmedPositions.length < 2) {
      debugPrint(
        'Ride comparison: using full GPX because trimmed timestamps yielded '
        '${trimmedPositions.length} points for ride ${ride['id']}',
      );
    }
    final settings = await DatabaseService.instance.getSettings();
    return GpxProcessingService.instance.distanceAtElapsedTime(
      positions,
      elapsed: elapsed,
      useCleanTime: useCleanTime,
      pauseRadiusMeters:
          (settings?['pause_radius_meters'] as num?)?.toDouble() ?? 20.0,
      minimumPauseDurationSeconds:
          (settings?['pause_min_duration_seconds'] as num?)?.toInt() ?? 90,
    );
  }

  /// Začni záznam nové jízdy
  Future<void> startRecording({required String userId, int? routeId}) async {
    _lastError = null;
    if (_isRecording) {
      _lastError = 'Already recording';
      if (kDebugMode) {
        debugPrint('Ride: Already recording');
      }
      return;
    }

    _currentRide = RecordedRide(
      startTime: DateTime.now(),
      positions: [],
    );
    _currentRide!.userId = userId;
    _selectedRouteId = routeId;
    _cleanStartIndex = null;
    _cleanStartPoint = null;
    _cleanStartRadiusMeters = null;
    final settings = await DatabaseService.instance.getSettings();
    _pauseRadiusMeters =
      (settings?['pause_radius_meters'] as num?)?.toDouble() ?? 20.0;
    _pauseMinDurationSeconds =
      (settings?['pause_min_duration_seconds'] as num?)?.toInt() ?? 90;
    await _configureCleanStart(routeId);
    _isRecording = true;
    _isPaused = false;

    if (kDebugMode) {
      debugPrint('=== RIDE: Recording started ===');
      debugPrint('User: $userId');
      debugPrint('Start time: ${_currentRide!.startTime}');
      debugPrint('================================');
    }

    // Nastartuj GPS listener
    GPSService.instance.addPositionListener(_onPositionUpdate);

    // Keep the start point even when a short recording ends before the next
    // periodic GPS stream update arrives.
    final currentPosition = GPSService.instance.currentPosition;
    if (currentPosition != null) {
      _currentRide!.addPosition(currentPosition);
      _checkCleanStart(currentPosition);
    }
  }

  /// GPS position update callback
  void _onPositionUpdate(GPSPosition position) {
    if (_isRecording && !_isPaused && _currentRide != null) {
      _currentRide!.addPosition(position);
      _checkCleanStart(position);
      if (kDebugMode) {
        debugPrint(
          'Ride point #${_currentRide!.positions.length}: '
          'lat=${position.latitude.toStringAsFixed(6)}, '
          'lon=${position.longitude.toStringAsFixed(6)}, '
          'accuracy=${position.accuracy.toStringAsFixed(1)}m, '
          'distance=${_currentRide!.totalDistance.toStringAsFixed(1)}m',
        );
      }
    }
  }

  Future<void> _configureCleanStart(int? routeId) async {
    if (routeId == null) {
      _cleanStartIndex = 0;
      return;
    }
    final route = await DatabaseService.instance.getRoute(routeId);
    if (route == null) {
      _cleanStartIndex = 0;
      return;
    }
    _cleanStartPoint = _routePoint(route, 'start_lat', 'start_lon');
    _cleanStartRadiusMeters = ((route['tolerance_radius'] as num?)?.toDouble() ?? 50) / 2;

    if (_cleanStartPoint == null) {
      final mainRideId = await DatabaseService.instance.getMainRideId(routeId);
      final mainRide = mainRideId == null
          ? null
          : await DatabaseService.instance.getRide(mainRideId);
      final fileName = mainRide?['gpx_file_path'] as String?;
      if (fileName != null && fileName.isNotEmpty) {
        final positions = await GpxService.instance.loadRide(fileName);
        if (positions.isNotEmpty) {
          _cleanStartPoint = positions.first;
          _cleanStartRadiusMeters = 100.0;
        }
      }
    }
  }

  void _checkCleanStart(GPSPosition position) {
    if (_cleanStartIndex != null || _currentRide == null) return;
    final startPoint = _cleanStartPoint;
    final radius = _cleanStartRadiusMeters;
    if (startPoint == null || radius == null) {
      _cleanStartIndex = 0;
      return;
    }
    if (GPSService.calculateDistance(
          position.latitude,
          position.longitude,
          startPoint.latitude,
          startPoint.longitude,
        ) <= radius) {
      _cleanStartIndex = _currentRide!.positions.length - 1;
      if (kDebugMode) debugPrint('Ride: Clean timer started at route start');
    }
  }

  Duration _liveCleanDuration(List<GPSPosition> positions) {
    final metrics = GpxProcessingService.instance.calculateDurations(
      positions,
      pauseRadiusMeters: _pauseRadiusMeters,
      minimumPauseDurationSeconds: _pauseMinDurationSeconds,
    );
    if (positions.isEmpty) return Duration.zero;
    final secondsSinceLastPoint = DateTime.now()
        .difference(positions.last.timestamp)
        .inSeconds;
    final tailSeconds = (secondsSinceLastPoint >= _pauseMinDurationSeconds
        ? 0
      : secondsSinceLastPoint.clamp(0, _pauseMinDurationSeconds))
      .toInt();
    return Duration(seconds: metrics.cleanDurationSeconds + tailSeconds);
  }

  /// Zastav záznam a ulož jízdu do DB
  Future<bool> stopRecording() async {
    _lastError = null;
    if (!_isRecording || _currentRide == null) {
      _lastError = 'No active recording session';
      if (kDebugMode) {
        debugPrint('Ride: Not recording');
      }
      return false;
    }

    _isRecording = false;
    _isPaused = false;
    GPSService.instance.removePositionListener(_onPositionUpdate);
    _currentRide!.endTime = DateTime.now();
    _currentRide!.calculateStats();

    if (kDebugMode) {
      debugPrint('=== RIDE: Recording stopped ===');
      debugPrint('Duration: ${_currentRide!.endTime!.difference(_currentRide!.startTime).inMinutes} minutes');
      debugPrint('Distance: ${(_currentRide!.totalDistance / 1000).toStringAsFixed(2)} km');
      debugPrint('Avg Speed: ${(_currentRide!.avgSpeed * 3.6).toStringAsFixed(2)} km/h');
      debugPrint('Positions: ${_currentRide!.positions.length}');
      debugPrint('================================');
    }

    // Ulož do databáze
    try {
      var routeId = _selectedRouteId;
      if (routeId != null &&
          !await validatePositionsForRoute(routeId, _currentRide!.positions)) {
        routeId = null;
        _lastError = 'Ride does not pass the active route start or end point';
        if (kDebugMode) debugPrint('Ride: Route validation failed; saving unassigned');
      }
      if (kDebugMode) {
        debugPrint('Ride: Saving with route_id=$routeId');
      }
      
      // Generate GPX first to get filename
      final gpxFilename = await GpxService.instance.saveRide(
        userNick: _currentRide!.userId ?? 'Unknown',
        startTime: _currentRide!.startTime,
        positions: _currentRide!.positions,
      );

      // Save ride metadata to DB with GPX filename
      final settings = await DatabaseService.instance.getSettings();
      final cleanPositions = _cleanStartIndex == null
          ? <GPSPosition>[]
          : _currentRide!.positions.sublist(_cleanStartIndex!);
      final durationMetrics = _calculateDurationMetrics(
        cleanPositions,
        settings,
      );
      final cleanStartTime = cleanPositions.isEmpty
          ? _currentRide!.startTime
          : cleanPositions.first.timestamp;
      final rideId = await DatabaseService.instance.insertRide({
        'route_id': routeId,
        'gpx_file_path': gpxFilename, // Now just the filename
        'start_time': cleanStartTime.toIso8601String(),
        'end_time': _currentRide!.endTime!.toIso8601String(),
        'saved_at': _currentRide!.startTime.toIso8601String(),
        'duration_seconds': durationMetrics.recordedDurationSeconds,
        'recorded_duration_seconds': durationMetrics.recordedDurationSeconds,
        'clean_duration_seconds': durationMetrics.cleanDurationSeconds,
        'distance_meters': _currentRide!.totalDistance,
        'avg_speed_kmh': _currentRide!.avgSpeed * 3.6, // Konvertuj na km/h
        'user_nick': _currentRide!.userId ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      });
      await recalculateRide(rideId);

      if (kDebugMode) {
        debugPrint('Ride saved to DB with ID: $rideId');
        debugPrint('GPX saved to: gpx/$gpxFilename');
        debugPrint('GPX points: ${_currentRide!.positions.length}');
      }

      return true;
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) {
        debugPrint('Ride Error saving to DB: $e');
      }
      return false;
    }
  }

  void pauseRecording() {
    if (_isRecording) {
      _isPaused = true;
      if (kDebugMode) debugPrint('Ride: Recording paused');
    }
  }

  void resumeRecording() {
    if (_isRecording) {
      _isPaused = false;
      if (kDebugMode) debugPrint('Ride: Recording resumed');
    }
  }

  /// Zrušit aktuální záznam
  void cancelRecording() {
    if (_isRecording) {
      _isRecording = false;
      _isPaused = false;
      _selectedRouteId = null;
      _currentRide = null;
      if (kDebugMode) {
        debugPrint('Ride: Recording cancelled');
      }
    }
  }

  /// Odstrani GPS listener
  void cleanup() {
    GPSService.instance.removePositionListener(_onPositionUpdate);
  }

  /// Import GPX souborů z adresáře gpx_import/ jako nezařazené jízdy.
  Future<bool> validateRideForRoute(
    int routeId,
    Map<String, dynamic> ride,
  ) async {
    final fileName = ride['gpx_file_path'] as String?;
    if (fileName == null || fileName.isEmpty) return false;
    final positions = await GpxService.instance.loadRide(fileName);
    return validatePositionsForRoute(routeId, positions);
  }

  Future<bool> validatePositionsForRoute(
    int routeId,
    List<GPSPosition> positions,
  ) async {
    if (positions.isEmpty) return false;
    final route = await DatabaseService.instance.getRoute(routeId);
    if (route == null) return false;
    final explicitRadius = ((route['tolerance_radius'] as num?)?.toDouble() ?? 50) / 2;
    const implicitRadius = 100.0;
    final explicitStart = _routePoint(route, 'start_lat', 'start_lon');
    final explicitEnd = _routePoint(route, 'end_lat', 'end_lon');
    var start = explicitStart;
    var end = explicitEnd;
    final mainRideId = await DatabaseService.instance.getMainRideId(routeId);
    if ((start == null || end == null) && mainRideId != null) {
      final mainRide = await DatabaseService.instance.getRide(mainRideId);
      final fileName = mainRide?['gpx_file_path'] as String?;
      if (fileName != null && fileName.isNotEmpty) {
        final mainPositions = await GpxService.instance.loadRide(fileName);
        if (mainPositions.isNotEmpty) {
          start ??= mainPositions.first;
          end ??= mainPositions.last;
        }
      }
    }

    final startRadius = explicitStart == null ? implicitRadius : explicitRadius;
    final endRadius = explicitEnd == null ? implicitRadius : explicitRadius;
    final startDistance = start == null ? null : _minimumDistance(positions, start);
    final endDistance = end == null ? null : _minimumDistance(positions, end);
    final startMatches = startDistance == null || startDistance <= startRadius;
    final endMatches = endDistance == null || endDistance <= endRadius;

    if (kDebugMode) {
      debugPrint(
        'Ride route validation: '
        'start=${startDistance?.toStringAsFixed(1) ?? 'not defined'}m '
        '(limit ${startRadius.toStringAsFixed(1)}m), '
        'end=${endDistance?.toStringAsFixed(1) ?? 'not defined'}m '
        '(limit ${endRadius.toStringAsFixed(1)}m)',
      );
    }
    return startMatches && endMatches;
  }

  GPSPosition? _routePoint(
    Map<String, dynamic> route,
    String latitudeKey,
    String longitudeKey,
  ) {
    final latitude = (route[latitudeKey] as num?)?.toDouble();
    final longitude = (route[longitudeKey] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    return GPSPosition(
      latitude: latitude,
      longitude: longitude,
      altitude: 0,
      accuracy: 0,
      speed: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  double _minimumDistance(
    List<GPSPosition> positions,
    GPSPosition target,
  ) {
    if (positions.length == 1) {
      return GPSService.calculateDistance(
        positions.first.latitude,
        positions.first.longitude,
        target.latitude,
        target.longitude,
      );
    }

    var minimum = double.infinity;
    for (var index = 0; index < positions.length - 1; index++) {
      final distance = _distanceFromTargetToSegment(
        positions[index],
        positions[index + 1],
        target,
      );
      if (distance < minimum) minimum = distance;
    }
    return minimum;
  }

  double _distanceFromTargetToSegment(
    GPSPosition start,
    GPSPosition end,
    GPSPosition target,
  ) {
    const metersPerLatitudeDegree = 111320.0;
    final metersPerLongitudeDegree =
        metersPerLatitudeDegree * math.cos(target.latitude * math.pi / 180);
    final startX = (start.longitude - target.longitude) * metersPerLongitudeDegree;
    final startY = (start.latitude - target.latitude) * metersPerLatitudeDegree;
    final endX = (end.longitude - target.longitude) * metersPerLongitudeDegree;
    final endY = (end.latitude - target.latitude) * metersPerLatitudeDegree;
    final deltaX = endX - startX;
    final deltaY = endY - startY;
    final lengthSquared = deltaX * deltaX + deltaY * deltaY;
    if (lengthSquared == 0) return math.sqrt(startX * startX + startY * startY);

    final projection = (-(startX * deltaX + startY * deltaY) / lengthSquared)
        .clamp(0.0, 1.0);
    final closestX = startX + projection * deltaX;
    final closestY = startY + projection * deltaY;
    return math.sqrt(closestX * closestX + closestY * closestY);
  }

  RideDurationMetrics _calculateDurationMetrics(
    List<GPSPosition> positions,
    Map<String, dynamic>? settings,
  ) {
    return GpxProcessingService.instance.calculateDurations(
      positions,
      pauseRadiusMeters:
          (settings?['pause_radius_meters'] as num?)?.toDouble() ?? 20.0,
      minimumPauseDurationSeconds:
          (settings?['pause_min_duration_seconds'] as num?)?.toInt() ?? 90,
    );
  }

  Future<void> recalculateCleanDurations() async {
    final rides = await DatabaseService.instance.getAllRides();
    for (final ride in rides) {
      try {
        await recalculateRide(ride['id'] as int);
      } catch (error) {
        if (kDebugMode) debugPrint('Clean duration recalculation failed: $error');
      }
    }
  }

  Future<void> recalculateRouteRides(int routeId) async {
    final rides = await DatabaseService.instance.getRidesByRoute(routeId);
    for (final ride in rides) {
      await recalculateRide(ride['id'] as int);
    }
  }

  Future<void> recalculateRide(int rideId) async {
    final ride = await DatabaseService.instance.getRide(rideId);
    final fileName = ride?['gpx_file_path'] as String?;
    if (ride == null || fileName == null || fileName.isEmpty) return;
    final settings = await DatabaseService.instance.getSettings();
    final positions = await GpxService.instance.loadRide(fileName);
    if (positions.isEmpty) return;

    final routeId = ride['route_id'] as int?;
    GPSPosition? startBoundary;
    GPSPosition? endBoundary;
    if (routeId != null) {
      final route = await DatabaseService.instance.getRoute(routeId);
      if (route != null) {
        startBoundary = _routePoint(route, 'start_lat', 'start_lon');
        endBoundary = _routePoint(route, 'end_lat', 'end_lon');
        if (startBoundary == null || endBoundary == null) {
          final mainRideId = await DatabaseService.instance.getMainRideId(routeId);
          if (mainRideId != null && mainRideId != rideId) {
            final mainRide = await DatabaseService.instance.getRide(mainRideId);
            final mainFileName = mainRide?['gpx_file_path'] as String?;
            if (mainFileName != null && mainFileName.isNotEmpty) {
              final mainPositions = await GpxService.instance.loadRide(mainFileName);
              if (mainPositions.isNotEmpty) {
                startBoundary ??= mainPositions.first;
                endBoundary ??= mainPositions.last;
              }
            }
          }
        }
      }
    }

    final processed = GpxProcessingService.instance.processRide(
      positions,
      startBoundary: startBoundary,
      endBoundary: endBoundary,
      pauseRadiusMeters:
          (settings?['pause_radius_meters'] as num?)?.toDouble() ?? 20.0,
      minimumPauseDurationSeconds:
          (settings?['pause_min_duration_seconds'] as num?)?.toInt() ?? 90,
    );
    if (processed.positions.isEmpty) return;
    final speedDuration = processed.durationMetrics.cleanDurationSeconds > 0
        ? processed.durationMetrics.cleanDurationSeconds
        : processed.durationMetrics.recordedDurationSeconds;
    await DatabaseService.instance.updateRide(rideId, {
      'start_time': processed.positions.first.timestamp.toIso8601String(),
      'end_time': processed.positions.last.timestamp.toIso8601String(),
      'duration_seconds': processed.durationMetrics.recordedDurationSeconds,
      'recorded_duration_seconds': processed.durationMetrics.recordedDurationSeconds,
      'clean_duration_seconds': processed.durationMetrics.cleanDurationSeconds,
      'distance_meters': processed.distanceMeters,
      'avg_speed_kmh': speedDuration == 0
          ? 0.0
          : (processed.distanceMeters / 1000) / (speedDuration / 3600),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Import GPX souborů z adresáře gpx_import/ jako nezařazené jízdy.
  Future<ImportResult> importGpxFiles() async {
    final fileNames = await GpxService.instance.listImportableFiles();
    var importedCount = 0;
    final failed = <String, String>{};
    if (fileNames.isEmpty) {
      return ImportResult(
        imported: 0,
        failed: failed,
        directoryPath: await GpxService.instance.getImportDirectoryPath(),
      );
    }

    final settings = await DatabaseService.instance.getSettings();
    final userNick = settings?['user_nick'] as String? ?? 'Import';

    for (final fileName in fileNames) {
      try {
        final positions = await GpxService.instance.loadImportFile(fileName);
        if (kDebugMode) {
          debugPrint('GPX import: $fileName -> ${positions.length} points');
        }
        if (positions.isEmpty) {
          failed[fileName] = 'The GPX file contains no GPS points';
          continue;
        }

        double distanceMeters = 0;
        for (var i = 1; i < positions.length; i++) {
          distanceMeters += GPSService.calculateDistance(
            positions[i - 1].latitude,
            positions[i - 1].longitude,
            positions[i].latitude,
            positions[i].longitude,
          );
        }

        final startTime = positions.first.timestamp;
        final endTime = positions.last.timestamp;
        final durationMetrics = _calculateDurationMetrics(positions, settings);
        final avgSpeedKmh = durationMetrics.recordedDurationSeconds > 0
          ? (distanceMeters / 1000) /
            (durationMetrics.recordedDurationSeconds / 3600)
            : 0.0;

        final finalFileName =
            await GpxService.instance.moveImportedFileToGpx(fileName);

        final rideId = await DatabaseService.instance.insertRide({
          'route_id': null,
          'gpx_file_path': finalFileName,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'saved_at': startTime.toIso8601String(),
          'duration_seconds': durationMetrics.recordedDurationSeconds,
          'recorded_duration_seconds': durationMetrics.recordedDurationSeconds,
          'clean_duration_seconds': durationMetrics.cleanDurationSeconds,
          'distance_meters': distanceMeters,
          'avg_speed_kmh': avgSpeedKmh,
          'user_nick': userNick,
          'created_at': DateTime.now().toIso8601String(),
        });
        await recalculateRide(rideId);

        importedCount++;
      } catch (e) {
        failed[fileName] = e.toString();
        if (kDebugMode) {
          debugPrint('GPX import failed: $fileName -> $e');
        }
      }
    }

    return ImportResult(
      imported: importedCount,
      failed: failed,
      directoryPath: await GpxService.instance.getImportDirectoryPath(),
    );
  }

  Future<ImportResult> importGpxBytes(
    List<ImportedGpxFile> files, {
    int? targetRouteId,
  }) async {
    var importedCount = 0;
    final failed = <String, String>{};
    final unassigned = <ImportedRideRejection>[];
    final settings = await DatabaseService.instance.getSettings();
    final userNick = settings?['user_nick'] as String? ?? 'Import';

    for (final file in files) {
      try {
        final fileName = await GpxService.instance.saveImportedBytes(
          file.name,
          file.bytes,
        );
        final positions = await GpxService.instance.loadRide(fileName);
        if (positions.isEmpty) {
          failed[file.name] = 'The GPX file contains no GPS points';
          await GpxService.instance.deleteRideFile(fileName);
          continue;
        }

        double distanceMeters = 0;
        for (var i = 1; i < positions.length; i++) {
          distanceMeters += GPSService.calculateDistance(
            positions[i - 1].latitude,
            positions[i - 1].longitude,
            positions[i].latitude,
            positions[i].longitude,
          );
        }
        final startTime = positions.first.timestamp;
        final endTime = positions.last.timestamp;
        final durationMetrics = _calculateDurationMetrics(positions, settings);
        final avgSpeedKmh = durationMetrics.recordedDurationSeconds > 0
          ? (distanceMeters / 1000) /
            (durationMetrics.recordedDurationSeconds / 3600)
            : 0.0;

        var assignedRouteId = targetRouteId;
        if (targetRouteId != null) {
          final existingRides = await DatabaseService.instance.getRidesByRoute(targetRouteId);
          if (existingRides.isNotEmpty &&
              !await validatePositionsForRoute(targetRouteId, positions)) {
            assignedRouteId = null;
          }
        }

        final rideId = await DatabaseService.instance.insertRide({
          'route_id': assignedRouteId,
          'gpx_file_path': fileName,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'saved_at': startTime.toIso8601String(),
          'duration_seconds': durationMetrics.recordedDurationSeconds,
          'recorded_duration_seconds': durationMetrics.recordedDurationSeconds,
          'clean_duration_seconds': durationMetrics.cleanDurationSeconds,
          'distance_meters': distanceMeters,
          'avg_speed_kmh': avgSpeedKmh,
          'user_nick': userNick,
          'created_at': DateTime.now().toIso8601String(),
        });
        if (targetRouteId != null && assignedRouteId == null) {
          unassigned.add(ImportedRideRejection(id: rideId, name: file.name));
        }
        await recalculateRide(rideId);
        importedCount++;
      } catch (e) {
        failed[file.name] = e.toString();
      }
    }
    return ImportResult(
      imported: importedCount,
      failed: failed,
      unassigned: unassigned,
      directoryPath: await GpxService.instance.getImportDirectoryPath(),
    );
  }
}

class ImportedGpxFile {
  final String name;
  final Uint8List bytes;

  ImportedGpxFile({required this.name, required this.bytes});
}

class ImportResult {
  final int imported;
  final Map<String, String> failed;
  final List<ImportedRideRejection> unassigned;
  final String directoryPath;

  ImportResult({
    required this.imported,
    required this.failed,
    this.unassigned = const [],
    required this.directoryPath,
  });
}

class ImportedRideRejection {
  final int id;
  final String name;

  ImportedRideRejection({required this.id, required this.name});
}
