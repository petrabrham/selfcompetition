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

  RideService._internal();

  /// Aktuální nahrávající se jízda
  RecordedRide? get currentRide => _currentRide;

  /// Zda se právě nahrává
  bool get isRecording => _isRecording;

  bool get isPaused => _isPaused;

  String? get lastError => _lastError;

  /// Začni záznam nové jízdy
  Future<void> startRecording({required String userId}) async {
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
      const routeId = 0;
      if (kDebugMode) {
        debugPrint('Ride: Saving with route_id=0 (Route Management not implemented yet)');
      }
      final rideId = await DatabaseService.instance.insertRide({
        'route_id': routeId,
        'gpx_file_path': '',
        'start_time': _currentRide!.startTime.toIso8601String(),
        'end_time': _currentRide!.endTime!.toIso8601String(),
        'distance_meters': _currentRide!.totalDistance,
        'avg_speed_kmh': _currentRide!.avgSpeed * 3.6, // Konvertuj na km/h
        'user_nick': _currentRide!.userId ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      });

      final gpxPath = await GpxService.instance.saveRide(
        routeId: routeId,
        rideId: rideId,
        userNick: _currentRide!.userId ?? 'Unknown',
        startTime: _currentRide!.startTime,
        positions: _currentRide!.positions,
      );
      await DatabaseService.instance.updateRide(rideId, {
        'gpx_file_path': gpxPath,
      });

      if (kDebugMode) {
        debugPrint('Ride saved to DB with ID: $rideId');
        debugPrint('GPX saved to: $gpxPath');
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
}
