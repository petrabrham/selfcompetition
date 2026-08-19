import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// GPS Position model
class GPSPosition {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed;
  final DateTime timestamp;

  GPSPosition({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.timestamp,
  });

  @override
  String toString() =>
      'GPSPosition(lat: $latitude, lon: $longitude, alt: $altitude, spd: $speed m/s, acc: $accuracy m)';
}

/// GPS Tracking Service
/// Manages real-time GPS position tracking using geolocator package
class GPSService {
  static final GPSService _instance = GPSService._internal();

  static GPSService get instance => _instance;

  GPSPosition? _currentPosition;
  bool _isTracking = false;
  Stream<Position>? _positionStream;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _replayTimer;
  bool _isReplaying = false;

  // Callback for position updates
  final List<Function(GPSPosition)> _positionListeners = [];

  GPSService._internal();

  /// Get current GPS position
  GPSPosition? get currentPosition => _currentPosition;

  /// Check if GPS is currently tracking
  bool get isTracking => _isTracking;

  bool get isReplaying => _isReplaying;

  /// Check location services availability and permissions
  Future<bool> checkLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          debugPrint('GPS: Location services are disabled');
        }
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            debugPrint('GPS: Location permission denied');
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          debugPrint('GPS: Location permission denied forever. Opening app settings.');
        }
        await Geolocator.openLocationSettings();
        return false;
      }

      if (kDebugMode) {
        debugPrint('GPS: Location permission granted');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GPS Error checking permission: $e');
      }
      return false;
    }
  }

  /// Get current position once
  Future<GPSPosition?> getCurrentPosition() async {
    try {
      if (!await checkLocationPermission()) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      _currentPosition = _convertPosition(position);
      if (kDebugMode) {
        debugPrint('GPS: Current position: $_currentPosition');
      }
      return _currentPosition;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('GPS: Timed out while waiting for a position');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GPS Error getting current position: $e');
      }
      return null;
    }
  }

  /// Start continuous GPS tracking
  Future<bool> startTracking({
    required int updateIntervalMs,
    required double minDistanceMeters,
  }) async {
    try {
      if (_isTracking) {
        if (kDebugMode) {
          debugPrint('GPS: Already tracking');
        }
        return true;
      }

      if (!await checkLocationPermission()) {
        return false;
      }

      _isTracking = true;
      if (kDebugMode) {
        debugPrint('GPS: Starting tracking (interval: ${updateIntervalMs}ms, minDistance: ${minDistanceMeters}m)');
      }

      _positionStream = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: minDistanceMeters.toInt(), // Filter by distance
          intervalDuration: Duration(milliseconds: updateIntervalMs),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Self Competition',
            notificationText: 'Recording GPS position in the background',
            notificationChannelName: 'Self Competition GPS',
            enableWakeLock: false,
            setOngoing: true,
          ),
        ),
      );

      _positionSubscription = _positionStream?.listen(
        (Position position) {
          _currentPosition = _convertPosition(position);
          _notifyListeners(_currentPosition!);

          if (kDebugMode) {
            debugPrint('GPS: Position update: $_currentPosition');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            debugPrint('GPS Stream Error: $error');
          }
          _isTracking = false;
        },
        cancelOnError: false,
      );

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GPS Error starting tracking: $e');
      }
      _isTracking = false;
      return false;
    }
  }

  /// Replay recorded positions through the same listener pipeline as live GPS.
  Future<bool> startReplay(
    List<GPSPosition> positions, {
    double speedMultiplier = 1.0,
  }) async {
    if (positions.isEmpty) return false;
    if (speedMultiplier <= 0) return false;
    await stopTracking();
    _isReplaying = true;
    var index = 0;

    void emitNext() {
      if (!_isReplaying || index >= positions.length) {
        stopReplay();
        return;
      }
      final currentIndex = index++;
      _currentPosition = positions[currentIndex];
      _notifyListeners(_currentPosition!);

      if (index < positions.length && _isReplaying) {
        final elapsed = positions[index].timestamp.difference(
          positions[currentIndex].timestamp,
        );
        final delay = Duration(
          microseconds: (elapsed.inMicroseconds / speedMultiplier).round(),
        );
        _replayTimer = Timer(
          delay.isNegative || delay == Duration.zero
              ? const Duration(milliseconds: 1)
              : delay,
          emitNext,
        );
      } else if (index >= positions.length) {
        stopReplay();
      }
    }

    emitNext();
    return true;
  }

  Future<void> stopReplay() async {
    _isReplaying = false;
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  /// Stop GPS tracking
  Future<void> stopTracking() async {
    try {
      await stopReplay();
      _isTracking = false;
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _positionStream = null;
      if (kDebugMode) {
        debugPrint('GPS: Tracking stopped');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GPS Error stopping tracking: $e');
      }
    }
  }

  /// Add listener for position updates
  void addPositionListener(Function(GPSPosition) callback) {
    _positionListeners.add(callback);
  }

  /// Remove listener
  void removePositionListener(Function(GPSPosition) callback) {
    _positionListeners.remove(callback);
  }

  /// Notify all listeners about position update
  void _notifyListeners(GPSPosition position) {
    for (var listener in _positionListeners) {
      listener(position);
    }
  }

  /// Convert geolocator Position to our GPSPosition model
  GPSPosition _convertPosition(Position position) {
    return GPSPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        position.timestamp.millisecondsSinceEpoch,
      ),
    );
  }

  /// Calculate distance between two points (Haversine formula)
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2));

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c * 1000; // Return in meters
  }

  static double _toRad(double degrees) => degrees * (pi / 180.0);
}
