import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:async';
import '../services/gps_service.dart';
import '../services/ride_service.dart';
import '../services/database_service.dart';

// Screens - Live Map screen
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GPSPosition? _currentPosition;
  bool _isLoading = false;
  String? _errorMessage;
  late MapController _mapController;
  bool _isRecording = false;
  bool _isPaused = false;
  Duration _recordingDuration = Duration.zero;
  late Timer _timerTick;
  String _userNick = 'User1';

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _setupGPSListener();
    _startLiveTracking();
    _restoreRecordingState();
    _loadUserAndPosition();
  }

  void _restoreRecordingState() {
    final rideService = RideService.instance;
    if (!rideService.isRecording) return;

    _isRecording = true;
    _isPaused = rideService.isPaused;
    final ride = rideService.currentRide;
    if (ride != null) {
      _recordingDuration = DateTime.now().difference(ride.startTime);
    }

    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isPaused) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
    });
  }

  /// Načti uživatele z Settings a poté pozici
  Future<void> _loadUserAndPosition() async {
    try {
      final settings = await DatabaseService.instance.getSettings();
      setState(() {
        _userNick = settings?['user_nick'] ?? 'User1';
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading user: $e');
      }
    }
    
    _loadCurrentPosition();
  }

  /// Setup GPS position listener for real-time tracking
  void _setupGPSListener() {
    GPSService.instance.addPositionListener(_onGPSPosition);
  }

  void _onGPSPosition(GPSPosition position) {
    if (mounted) {
      setState(() {
        _currentPosition = position;
      });

    }
  }

  Future<void> _startLiveTracking() async {
    final settings = await DatabaseService.instance.getSettings();
    await GPSService.instance.startTracking(
      updateIntervalMs: settings?['gps_update_interval_ms'] as int? ?? 5000,
      minDistanceMeters:
          (settings?['min_distance_threshold_meters'] as num?)?.toDouble() ?? 5.0,
    );
  }

  /// Load current GPS position
  Future<void> _loadCurrentPosition() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final position = await GPSService.instance.getCurrentPosition();
      
      if (position != null) {
        setState(() {
          _currentPosition = position;
        });

        if (kDebugMode) {
          debugPrint('=== LIVE MAP: Initial Position ===');
          debugPrint('Latitude: ${position.latitude}');
          debugPrint('Longitude: ${position.longitude}');
          debugPrint('Accuracy: ${position.accuracy}');
          debugPrint('===================================');
        }
      } else {
        setState(() {
          _errorMessage =
              'No GPS position received within 10 seconds. Check the emulator location.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
      if (kDebugMode) {
        debugPrint('Live Map Error: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Začni záznam jízdy
  Future<void> _startRecording() async {
    await RideService.instance.startRecording(userId: _userNick);
    
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _recordingDuration = Duration.zero;
    });
    
    // Spusť timer pro aktualizaci doby trvání
    _timerTick = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isPaused) {
        setState(() {
          _recordingDuration = _recordingDuration + Duration(seconds: 1);
        });
      }
    });
    
    if (kDebugMode) {
      debugPrint('=== LIVE MAP: Recording started ===');
    }
  }

  void _togglePause() {
    if (!_isRecording) return;

    setState(() {
      _isPaused = !_isPaused;
    });

    if (_isPaused) {
      RideService.instance.pauseRecording();
    } else {
      RideService.instance.resumeRecording();
    }
  }

  /// Zastav záznam jízdy
  Future<void> _stopRecording() async {
    _timerTick.cancel();
    
    final success = await RideService.instance.stopRecording();
    
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✅ Ride saved!' : '❌ Error saving ride'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    if (kDebugMode) {
      debugPrint('=== LIVE MAP: Recording stopped ===');
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    if (_isRecording) {
      _timerTick.cancel();
    }
    GPSService.instance.removePositionListener(_onGPSPosition);
    super.dispose();
  }

  /// Fallback UI when map fails to load
  Widget _buildFallbackUI() {
    final ride = RideService.instance.currentRide;
    
    return Container(
      color: Colors.grey.shade200,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            // Recording status header
            if (_isRecording) ...[
              Container(
                margin: const EdgeInsets.only(right: 64.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  border: Border.all(color: Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🔴 RECORDING',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Time
                    _buildStatField(
                      label: 'Time',
                      value: _formatDuration(_recordingDuration),
                      icon: Icons.timer,
                    ),
                    const SizedBox(height: 8),
                    // Distance
                    if (ride != null)
                      _buildStatField(
                        label: 'Distance',
                        value: '${(ride.totalDistance / 1000).toStringAsFixed(2)} km',
                        icon: Icons.route,
                      ),
                    if (ride != null) const SizedBox(height: 8),
                    // Speed
                    if (ride != null)
                      _buildStatField(
                        label: 'Avg Speed',
                        value: '${(ride.avgSpeed * 3.6).toStringAsFixed(2)} km/h',
                        icon: Icons.speed,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Icon(Icons.location_on_outlined, color: Colors.blue, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Live Position',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
            ],
            
            // Position fields
            if (_currentPosition != null) ...[
              _buildPositionField(
                label: 'Latitude',
                value: _currentPosition!.latitude.toStringAsFixed(6),
                icon: Icons.location_on,
              ),
              const SizedBox(height: 12),
              _buildPositionField(
                label: 'Longitude',
                value: _currentPosition!.longitude.toStringAsFixed(6),
                icon: Icons.location_on,
              ),
              const SizedBox(height: 12),
              _buildPositionField(
                label: 'Accuracy',
                value: '±${_currentPosition!.accuracy.toStringAsFixed(1)} m',
                icon: Icons.precision_manufacturing,
              ),
              const SizedBox(height: 12),
              _buildPositionField(
                label: 'Speed',
                value: '${(_currentPosition!.speed * 3.6).toStringAsFixed(2)} km/h',
                icon: Icons.speed,
              ),
            ],
            
          ],
        ),
      ),
    );
  }

  /// Format recording duration
  String _formatDuration(Duration duration) {
    String minutes = duration.inMinutes.toString().padLeft(2, '0');
    String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Build stat field for recording (time, distance, speed)
  Widget _buildStatField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.red, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Build position field widget
  Widget _buildPositionField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always show fallback UI for now (map has SSL issues on emulator)
        _buildFallbackUI(),

        if (_isLoading)
          const Positioned(
            top: 16,
            left: 16,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Getting GPS position...'),
                  ],
                ),
              ),
            ),
          ),

        if (_errorMessage != null)
          Positioned(
            top: 16,
            left: 16,
            right: 80,
            child: Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_errorMessage!),
              ),
            ),
          ),

        // Zoom controls - top right
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              // Center on position
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.green,
                onPressed: null,
                child: const Icon(Icons.my_location, color: Colors.white),
              ),
              const SizedBox(height: 8),
              // Zoom In
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: null,
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 8),
              // Zoom Out
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: null,
                child: const Icon(Icons.remove, color: Colors.white),
              ),
            ],
          ),
        ),
        // Fixed recording controls. The Scaffold places this above bottom navigation.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            padding: const EdgeInsets.all(12.0),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: !_isRecording
                  ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startRecording,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('START RECORDING'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop),
                          label: const Text('STOP'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                          label: Text(_isPaused ? 'RESUME' : 'PAUSE'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
