import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/gps_service.dart';

// Screens - Live Map screen
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({Key? key}) : super(key: key);

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GPSPosition? _currentPosition;
  bool _isLoading = false;
  String? _errorMessage;
  late MapController _mapController;
  bool _isTracking = false;
  bool _mapFailed = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadCurrentPosition();
    
    // Setup GPS listener only when user toggles tracking
    // Not in initState to avoid MapController issues
  }

  /// Setup GPS position listener for real-time tracking
  void _setupGPSListener() {
    GPSService.instance.addPositionListener((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        
        // Auto-center map on new position if tracking
        if (_isTracking) {
          _centerMapOnPosition(position);
        }

        if (kDebugMode) {
          debugPrint('=== LIVE MAP: GPS Update ===');
          debugPrint('Latitude: ${position.latitude}');
          debugPrint('Longitude: ${position.longitude}');
          debugPrint('============================');
        }
      }
    });
  }

  /// Center map on given position
  void _centerMapOnPosition(GPSPosition position) {
    try {
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        16.0,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Map center error: $e');
      }
    }
  }

  /// Load current GPS position
  Future<void> _loadCurrentPosition() async {
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
          _errorMessage = 'Failed to get GPS position. Check location permissions.';
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

  /// Toggle tracking mode
  void _toggleTracking() {
    setState(() {
      _isTracking = !_isTracking;
    });
    
    if (_isTracking) {
      // Setup GPS listener only when tracking starts
      _setupGPSListener();
    }
    
    if (kDebugMode) {
      debugPrint('GPS Tracking: ${_isTracking ? 'ENABLED' : 'DISABLED'}');
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    GPSService.instance.removePositionListener((position) {
      // Dummy callback for cleanup
    });
    super.dispose();
  }

  /// Fallback UI when map fails to load
  Widget _buildFallbackUI() {
    return Container(
      color: Colors.grey.shade200,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Icon(Icons.warning, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Map unavailable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Showing coordinates only',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
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
      children: [
        // Always show fallback UI for now (map has SSL issues on emulator)
        _buildFallbackUI(),

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
                onPressed: _currentPosition != null
                    ? () => _centerMapOnPosition(_currentPosition!)
                    : null,
                child: const Icon(Icons.my_location, color: Colors.white),
              ),
              const SizedBox(height: 8),
              // Zoom In
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 8),
              // Zoom Out
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
                child: const Icon(Icons.remove, color: Colors.white),
              ),
            ],
          ),
        ),
        // Bottom info panel
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Position info
                if (_currentPosition != null) ...[
                  Text(
                    'Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accuracy: ±${_currentPosition!.accuracy.toStringAsFixed(1)} m',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loadCurrentPosition,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text(
                          'Refresh',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking
                              ? Colors.green
                              : Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          _isTracking ? 'Tracking ON' : 'Tracking OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
