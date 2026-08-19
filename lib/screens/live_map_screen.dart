import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/gps_service.dart';
import '../services/gpx_service.dart';
import '../services/ride_service.dart';
import '../services/database_service.dart';

enum _MapOrientationMode { free, northUp }

// Screens - Live Map screen
class LiveMapScreen extends StatefulWidget {
  final VoidCallback? onSleepRequested;

  const LiveMapScreen({super.key, this.onSleepRequested});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _powerChannel =
      MethodChannel('selfcompetition/power');
  static LatLng? _lastMapCenter;
  static double _lastMapZoom = 16;
  static double _lastMapRotation = 0;
  static bool _lastFollowPosition = true;
  static _MapOrientationMode _lastOrientationMode =
      _MapOrientationMode.northUp;

  GPSPosition? _currentPosition;
  bool _isLoading = false;
  String? _errorMessage;
  late MapController _mapController;
  bool _mapReady = false;
  bool _followPosition = true;
  _MapOrientationMode _orientationMode = _MapOrientationMode.northUp;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _screenDimmed = false;
  int? _activeRouteId;
  String _activeRouteName = 'Žádná aktivní trasa';
  String? _replayFileName;
  Duration _recordingDuration = Duration.zero;
  late Timer _timerTick;
  Timer? _screenSleepTimer;
  String _userNick = 'User1';
  int _screenOffTimeoutSeconds = 30;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _followPosition = _lastFollowPosition;
    _orientationMode = _lastOrientationMode;
    _setupGPSListener();
    _startLiveTracking();
    _restoreRecordingState();
    _loadUserAndPosition();
    _loadActiveRoute();
  }

  Future<void> _loadActiveRoute() async {
    final routeId = await DatabaseService.instance.getActiveRouteId();
    final route = routeId == null ? null : await DatabaseService.instance.getRoute(routeId);
    if (!mounted) return;
    setState(() {
      _activeRouteId = routeId;
      _activeRouteName = route?['name'] as String? ?? 'Žádná aktivní trasa';
    });
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

    if (_settingsLoaded) {
      _scheduleScreenSleep();
    }
  }

  /// Načti uživatele z Settings a poté pozici
  Future<void> _loadUserAndPosition() async {
    try {
      final settings = await DatabaseService.instance.getSettings();
      setState(() {
        _userNick = settings?['user_nick'] ?? 'User1';
        _screenOffTimeoutSeconds = settings?['screen_off_timeout_seconds'] ?? 30;
        _settingsLoaded = true;
      });
      if (kDebugMode) {
        debugPrint(
          'POWER: Loaded screen timeout: ${_screenOffTimeoutSeconds}s',
        );
      }
      _scheduleScreenSleep();
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
    _currentPosition = position;

    if (_screenDimmed) {
      return;
    }

    if (_mapReady && _followPosition) {
      _centerMapOnPosition(position);
    }

    if (mounted) {
      setState(() {
        // Trigger UI update while screen is active.
      });

    }
  }

  void _centerMapOnPosition(GPSPosition position) {
    if (!_mapReady) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      _mapController.camera.zoom,
    );
  }

  void _toggleFollowPosition() {
    if (_currentPosition == null) return;

    setState(() {
      _followPosition = !_followPosition;
      _lastFollowPosition = _followPosition;
    });

    if (_followPosition && _currentPosition != null) {
      _centerMapOnPosition(_currentPosition!);
    }
  }

  bool get _isNorthUp => _orientationMode == _MapOrientationMode.northUp;

  int get _rotationInteractionFlags => _isNorthUp
      ? InteractiveFlag.all & ~InteractiveFlag.rotate
      : InteractiveFlag.all;

  void _toggleOrientationMode() {
    setState(() {
      _orientationMode = _isNorthUp
          ? _MapOrientationMode.free
          : _MapOrientationMode.northUp;
      _lastOrientationMode = _orientationMode;
    });

    if (_isNorthUp) {
      _lastMapRotation = 0;
      if (_mapReady) {
        _mapController.rotate(0);
      }
    }
  }

  void _storeMapCamera(MapCamera camera) {
    _lastMapCenter = camera.center;
    _lastMapZoom = camera.zoom;
    _lastMapRotation = camera.rotation;
  }

  void _scheduleScreenSleep() {
    _screenSleepTimer?.cancel();

    if (kDebugMode) {
      debugPrint(
        'POWER: Scheduling screen dim in ${_screenOffTimeoutSeconds}s',
      );
    }

    _screenSleepTimer = Timer(
      Duration(seconds: _screenOffTimeoutSeconds),
      () {
        if (kDebugMode) {
          debugPrint('POWER: Screen dim timer fired');
        }
        _dimScreen();
      },
    );
  }

  void _dimScreen() {
    if (widget.onSleepRequested != null) {
      widget.onSleepRequested!();
      return;
    }

    if (!mounted || _screenDimmed) {
      if (kDebugMode) {
        debugPrint(
          'POWER: Screen dim skipped '
          '(mounted=$mounted, dimmed=$_screenDimmed)',
        );
      }
      return;
    }

    setState(() {
      _screenDimmed = true;
    });
    if (kDebugMode) {
      debugPrint('POWER: Screen dimmed');
    }
    _setPowerSavingMode(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _sleepNow() {
    _screenSleepTimer?.cancel();
    _dimScreen();
  }

  Future<void> _selectReplayRide() async {
    final replayableFiles = await GpxService.instance.listTestRides();
    if (!mounted) return;

    final fileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Přehrát uloženou jízdu'),
        content: SizedBox(
          width: double.maxFinite,
          child: replayableFiles.isEmpty
              ? const Text('V adresáři gpx_test nejsou žádné GPX soubory.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: replayableFiles.length,
                  itemBuilder: (_, index) {
                    final fileName = replayableFiles[index];
                    return ListTile(
                      title: Text(fileName),
                      onTap: () => Navigator.pop(context, fileName),
                    );
                  },
                ),
        ),
      ),
    );
    if (fileName == null || !mounted) return;

    try {
      final positions = await GpxService.instance.loadTestRide(fileName);
      final started = await GPSService.instance.startReplay(positions);
      if (!started) throw StateError('GPX neobsahuje žádné GPS body.');
      setState(() => _replayFileName = fileName);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Replay se nepodařilo spustit: $error')),
      );
    }
  }

  Future<void> _stopReplay() async {
    await GPSService.instance.stopReplay();
    if (mounted) {
      setState(() => _replayFileName = null);
      _startLiveTracking();
    }
  }

  Future<void> _setRecordingKeepScreenOn(bool enabled) async {
    try {
      await _powerChannel.invokeMethod<void>(
        'setRecordingKeepScreenOn',
        enabled,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Power setting error: ${e.message}');
      }
    }
  }

  Future<void> _setPowerSavingMode(bool enabled) async {
    try {
      await _powerChannel.invokeMethod<void>(
        'setPowerSavingMode',
        enabled,
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Power saving mode error: ${e.message}');
      }
    }
  }

  void _wakeScreen() {
    _screenSleepTimer?.cancel();

    if (_screenDimmed && mounted) {
      setState(() {
        _screenDimmed = false;
      });
      _setPowerSavingMode(false);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _scheduleScreenSleep();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _wakeScreen();
      if (_isRecording && !_screenDimmed) {
        _setRecordingKeepScreenOn(true);
      }
      if (!_isRecording) {
        _startLiveTracking();
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_isRecording) {
        _setRecordingKeepScreenOn(false);
      }
      if (!_isRecording) {
        GPSService.instance.stopTracking();
      }
    }
  }

  Future<void> _startLiveTracking() async {
    final settings = await DatabaseService.instance.getSettings();
    if (!mounted && !RideService.instance.isRecording) return;
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
    await RideService.instance.startRecording(
      userId: _userNick,
      routeId: _activeRouteId,
    );
    await _setRecordingKeepScreenOn(true);
    
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _recordingDuration = Duration.zero;
    });
    _scheduleScreenSleep();
    
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

    _wakeScreen();

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
    await _setRecordingKeepScreenOn(false);
    final error = RideService.instance.lastError;
    _screenSleepTimer?.cancel();
    _wakeScreen();
    
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });

    if (mounted) {
      _startLiveTracking();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✅ Ride saved!'
                : '❌ Error saving ride${error != null ? ': $error' : ''}',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    if (kDebugMode) {
      debugPrint('=== LIVE MAP: Recording stopped ===');
      if (!success) {
        debugPrint('Live Map: Ride save failed${error != null ? ': $error' : ''}');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lastFollowPosition = _followPosition;
    _lastOrientationMode = _orientationMode;
    if (_mapReady) {
      _storeMapCamera(_mapController.camera);
    }
    _mapController.dispose();
    _screenSleepTimer?.cancel();
    _setPowerSavingMode(false);
    if (!_isRecording) {
      GPSService.instance.stopTracking();
      _setRecordingKeepScreenOn(false);
    }
    if (_isRecording) {
      _timerTick.cancel();
    }
    GPSService.instance.removePositionListener(_onGPSPosition);
    super.dispose();
  }

  Widget _buildMapLayer() {
    final center = _lastMapCenter ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const LatLng(50.0755, 14.4378));

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _lastMapZoom,
        initialRotation: _lastMapRotation,
        interactionOptions: InteractionOptions(
          flags: _rotationInteractionFlags,
        ),
        onPositionChanged: (camera, hasGesture) {
          _storeMapCamera(camera);
          if (hasGesture && _followPosition && mounted) {
            setState(() {
              _followPosition = false;
              _lastFollowPosition = false;
            });
          }
        },
        onMapReady: () {
          if (_lastMapCenter != null) {
            _mapController.moveAndRotate(
              _lastMapCenter!,
              _lastMapZoom,
              _isNorthUp ? 0 : _lastMapRotation,
            );
          } else if (_followPosition && _currentPosition != null) {
            _centerMapOnPosition(_currentPosition!);
            if (_isNorthUp) {
              _mapController.rotate(0);
            }
          }

          if (mounted) {
            setState(() {
              _mapReady = true;
            });
          } else {
            _mapReady = true;
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.selfcompetition',
        ),
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                width: 42,
                height: 42,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 42,
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
        _buildMapLayer(),

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
                backgroundColor: _followPosition ? Colors.green : Colors.grey,
                onPressed: _currentPosition != null
                    ? _toggleFollowPosition
                    : null,
                child: Icon(
                  _followPosition ? Icons.my_location : Icons.location_searching,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              // Orientation mode: FREE / NORTH
              FloatingActionButton(
                mini: true,
                backgroundColor: _isNorthUp ? Colors.indigo : Colors.grey,
                onPressed: _toggleOrientationMode,
                child: Icon(
                  _isNorthUp ? Icons.explore_off : Icons.explore,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              // Zoom In
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: _mapReady
                    ? () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        )
                    : null,
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 8),
              // Zoom Out
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: _mapReady
                    ? () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        )
                    : null,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isRecording)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.route, size: 18, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            'Aktivní trasa: $_activeRouteName',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  if (kDebugMode)
                    OutlinedButton.icon(
                      onPressed: _replayFileName == null
                          ? _selectReplayRide
                          : _stopReplay,
                      icon: Icon(
                        _replayFileName == null ? Icons.replay : Icons.stop,
                      ),
                      label: Text(
                        _replayFileName == null
                            ? 'Replay GPX'
                            : 'Stop replay: $_replayFileName',
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isRecording ? _stopRecording : _startRecording,
                            icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                            label: Text(_isRecording ? 'STOP' : 'START RECORDING'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecording ? Colors.red : Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isRecording ? _togglePause : _sleepNow,
                            icon: Icon(_isRecording
                                ? (_isPaused ? Icons.play_arrow : Icons.pause)
                                : Icons.bedtime),
                            label: Text(_isRecording
                                ? (_isPaused ? 'RESUME' : 'PAUSE')
                                : 'SLEEP'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecording ? Colors.orange : Colors.indigo,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
