import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/database_service.dart';

// Screens - Settings screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Controllers for form fields
  final TextEditingController _nickController = TextEditingController();
  
  // State variables
  double _gpsIntervalSeconds = 5.0; // seconds
  double _minDistance = 5.0; // meters
  int _numRidesToDisplay = 3;
  double _screenOffTimeoutSeconds = 30.0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _nickError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Listen to nick changes and validate
    _nickController.addListener(_validateNick);
    // Validate immediately
    _validateNick();
  }

  /// Validate user nick
  void _validateNick() {
    final nick = _nickController.text;
    
    setState(() {
      if (nick.isEmpty) {
        _nickError = 'Nickname cannot be empty';
      } else if (nick.length > 20) {
        _nickError = 'Nickname must be 20 characters or less';
      } else if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(nick)) {
        _nickError = 'Only letters, numbers, underscore and dash allowed';
      } else {
        _nickError = null;
      }
    });
  }

  /// Load settings from database
  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await DatabaseService.instance.getSettings();
      if (settings != null) {
        setState(() {
          _nickController.text = settings['user_nick'] ?? 'User1';
          _gpsIntervalSeconds = (settings['gps_update_interval_ms'] ?? 5000) / 1000.0;
          _minDistance = settings['min_distance_threshold_meters'] ?? 5.0;
          _numRidesToDisplay = settings['num_rides_to_display'] ?? 3;
          _screenOffTimeoutSeconds =
              (settings['screen_off_timeout_seconds'] ?? 30).toDouble();
          // Validate after loading from database
          _validateNick();
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Save settings to database
  Future<void> _saveSettings() async {
    // Validate nick before saving
    if (_nickError != null) {
      setState(() {
        _errorMessage = _nickError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await DatabaseService.instance.updateSettings({
        'user_nick': _nickController.text.isEmpty ? 'User1' : _nickController.text,
        'gps_update_interval_ms': (_gpsIntervalSeconds * 1000).toInt(),
        'min_distance_threshold_meters': _minDistance,
        'num_rides_to_display': _numRidesToDisplay,
        'screen_off_timeout_seconds': _screenOffTimeoutSeconds.toInt(),
      });

      // Debug: Read and print settings from database
      if (kDebugMode) {
        final settings = await DatabaseService.instance.getSettings();
        if (settings != null) {
          debugPrint('=== DATABASE SETTINGS ===');
          debugPrint('User Nick: ${settings['user_nick']}');
          debugPrint('GPS Interval (ms): ${settings['gps_update_interval_ms']}');
          debugPrint('Min Distance (m): ${settings['min_distance_threshold_meters']}');
          debugPrint('Rides to Display: ${settings['num_rides_to_display']}');
          debugPrint('Screen Off Timeout (s): ${settings['screen_off_timeout_seconds']}');
          debugPrint('Updated At: ${settings['updated_at']}');
          debugPrint('========================');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _nickController.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Container(
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
            ),

          // User Nick TextField
          const Text(
            'User Nickname',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nickController,
            maxLength: 20,
            decoration: InputDecoration(
              hintText: 'e.g., User1, Cycler1',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              prefixIcon: const Icon(Icons.person),
              errorText: _nickError,
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Colors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
              helperText: 'Letters, numbers, underscore, dash only',
            ),
          ),
          const SizedBox(height: 24),

          // GPS Update Interval Slider
          const Text(
            'GPS Recording Interval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'How often to record position',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _gpsIntervalSeconds,
                  min: 0.5,
                  max: 10.0,
                  divisions: 19,
                  label: '${_gpsIntervalSeconds.toStringAsFixed(1)}s',
                  onChanged: (value) {
                    setState(() {
                      _gpsIntervalSeconds = value;
                    });
                  },
                ),
              ),
              Text('${_gpsIntervalSeconds.toStringAsFixed(1)}s'),
            ],
          ),
          const SizedBox(height: 24),

          // Minimum Distance Threshold Slider
          const Text(
            'Minimum Distance Threshold',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Ignore movements smaller than',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _minDistance,
                  min: 1.0,
                  max: 20.0,
                  divisions: 19,
                  label: '${_minDistance.toStringAsFixed(1)}m',
                  onChanged: (value) {
                    setState(() {
                      _minDistance = value;
                    });
                  },
                ),
              ),
              Text('${_minDistance.toStringAsFixed(1)}m'),
            ],
          ),
          const SizedBox(height: 24),

          // Screen Off Timeout Slider
          const Text(
            'Screen Off Timeout (recording)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Dim screen after inactivity while recording',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _screenOffTimeoutSeconds,
                  min: 10,
                  max: 120,
                  divisions: 22,
                  label: '${_screenOffTimeoutSeconds.toInt()}s',
                  onChanged: (value) {
                    setState(() {
                      _screenOffTimeoutSeconds = value;
                    });
                  },
                ),
              ),
              Text('${_screenOffTimeoutSeconds.toInt()}s'),
            ],
          ),
          const SizedBox(height: 24),

          // Number of Rides to Display Slider
          const Text(
            'Rides to Display',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'How many previous rides to show for comparison',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _numRidesToDisplay.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_numRidesToDisplay',
                  onChanged: (value) {
                    setState(() {
                      _numRidesToDisplay = value.toInt();
                    });
                  },
                ),
              ),
              Text('$_numRidesToDisplay'),
            ],
          ),
          const SizedBox(height: 32),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isLoading || _nickError != null) ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.grey,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Settings',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
