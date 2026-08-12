import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

  @override
  void initState() {
    super.initState();
    _loadCurrentPosition();
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
          debugPrint('=== LIVE MAP: Current Position ===');
          debugPrint('Latitude: ${position.latitude}');
          debugPrint('Longitude: ${position.longitude}');
          debugPrint('Altitude: ${position.altitude} m');
          debugPrint('Accuracy: ${position.accuracy} m');
          debugPrint('Speed: ${position.speed} m/s');
          debugPrint('Timestamp: ${position.timestamp}');
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Current Position',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),

          // Loading state
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32.0),
                child: CircularProgressIndicator(),
              ),
            ),

          // Position data
          if (_currentPosition != null && !_isLoading) ...[
            // Latitude
            _buildPositionField(
              label: 'Latitude',
              value: _currentPosition!.latitude.toStringAsFixed(6),
              icon: Icons.location_on,
            ),
            const SizedBox(height: 16),

            // Longitude
            _buildPositionField(
              label: 'Longitude',
              value: _currentPosition!.longitude.toStringAsFixed(6),
              icon: Icons.location_on,
            ),
            const SizedBox(height: 16),

            // Altitude
            _buildPositionField(
              label: 'Altitude',
              value: '${_currentPosition!.altitude.toStringAsFixed(1)} m',
              icon: Icons.height,
            ),
            const SizedBox(height: 16),

            // Accuracy
            _buildPositionField(
              label: 'Accuracy',
              value: '±${_currentPosition!.accuracy.toStringAsFixed(1)} m',
              icon: Icons.precision_manufacturing,
              color: _getAccuracyColor(_currentPosition!.accuracy),
            ),
            const SizedBox(height: 16),

            // Speed
            _buildPositionField(
              label: 'Speed',
              value: '${(_currentPosition!.speed * 3.6).toStringAsFixed(2)} km/h',
              icon: Icons.speed,
            ),
            const SizedBox(height: 16),

            // Timestamp
            _buildPositionField(
              label: 'Updated',
              value: _currentPosition!.timestamp.toIso8601String(),
              icon: Icons.access_time,
            ),
            const SizedBox(height: 32),
          ],

          // Refresh button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _loadCurrentPosition,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.grey,
              ),
              child: const Text(
                'Refresh Position',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build position field widget
  Widget _buildPositionField({
    required String label,
    required String value,
    required IconData icon,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.blue, size: 24),
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

  /// Get color based on accuracy value
  Color _getAccuracyColor(double accuracy) {
    if (accuracy < 10) return Colors.green;
    if (accuracy < 50) return Colors.orange;
    return Colors.red;
  }
}
