import 'package:flutter/foundation.dart';
import 'gps_service.dart';
import 'database_service.dart';
import 'gpx_service.dart';

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

  RideService._internal();

  /// Aktuální nahrávající se jízda
  RecordedRide? get currentRide => _currentRide;

  /// Zda se právě nahrává
  bool get isRecording => _isRecording;

  bool get isPaused => _isPaused;

  String? get lastError => _lastError;

  int? get selectedRouteId => _selectedRouteId;

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
    }
  }

  /// GPS position update callback
  void _onPositionUpdate(GPSPosition position) {
    if (_isRecording && !_isPaused && _currentRide != null) {
      _currentRide!.addPosition(position);
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
      final rideId = await DatabaseService.instance.insertRide({
        'route_id': routeId,
        'gpx_file_path': gpxFilename, // Now just the filename
        'start_time': _currentRide!.startTime.toIso8601String(),
        'end_time': _currentRide!.endTime!.toIso8601String(),
        'saved_at': _currentRide!.startTime.toIso8601String(),
        'duration_seconds': _currentRide!.endTime!
          .difference(_currentRide!.startTime)
          .inSeconds,
        'distance_meters': _currentRide!.totalDistance,
        'avg_speed_kmh': _currentRide!.avgSpeed * 3.6, // Konvertuj na km/h
        'user_nick': _currentRide!.userId ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      });

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
    final tolerance = ((route['tolerance_radius'] as num?)?.toDouble() ?? 50) / 2;

    var start = _routePoint(route, 'start_lat', 'start_lon');
    var end = _routePoint(route, 'end_lat', 'end_lon');
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

    return (start == null || _containsPosition(positions, start, tolerance)) &&
        (end == null || _containsPosition(positions, end, tolerance));
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

  bool _containsPosition(
    List<GPSPosition> positions,
    GPSPosition target,
    double radiusMeters,
  ) {
    return positions.any((position) => GPSService.calculateDistance(
          position.latitude,
          position.longitude,
          target.latitude,
          target.longitude,
        ) <= radiusMeters);
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
        final durationSeconds = endTime.difference(startTime).inSeconds;
        final avgSpeedKmh = durationSeconds > 0
            ? (distanceMeters / 1000) / (durationSeconds / 3600)
            : 0.0;

        final finalFileName =
            await GpxService.instance.moveImportedFileToGpx(fileName);

        await DatabaseService.instance.insertRide({
          'route_id': null,
          'gpx_file_path': finalFileName,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'saved_at': startTime.toIso8601String(),
          'duration_seconds': durationSeconds,
          'distance_meters': distanceMeters,
          'avg_speed_kmh': avgSpeedKmh,
          'user_nick': userNick,
          'created_at': DateTime.now().toIso8601String(),
        });

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

  Future<ImportResult> importGpxBytes(List<ImportedGpxFile> files) async {
    var importedCount = 0;
    final failed = <String, String>{};
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
        final durationSeconds = endTime.difference(startTime).inSeconds;
        final avgSpeedKmh = durationSeconds > 0
            ? (distanceMeters / 1000) / (durationSeconds / 3600)
            : 0.0;

        await DatabaseService.instance.insertRide({
          'route_id': null,
          'gpx_file_path': fileName,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'saved_at': startTime.toIso8601String(),
          'duration_seconds': durationSeconds,
          'distance_meters': distanceMeters,
          'avg_speed_kmh': avgSpeedKmh,
          'user_nick': userNick,
          'created_at': DateTime.now().toIso8601String(),
        });
        importedCount++;
      } catch (e) {
        failed[file.name] = e.toString();
      }
    }
    return ImportResult(
      imported: importedCount,
      failed: failed,
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
  final String directoryPath;

  ImportResult({
    required this.imported,
    required this.failed,
    required this.directoryPath,
  });
}
