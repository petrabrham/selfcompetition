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
import '../widgets/bottom_navigation.dart';

enum _MapOrientationMode { free, northUp }

// Screens - Live Map screen
class LiveMapScreen extends StatefulWidget {
  final VoidCallback? onSleepRequested;
  final String? selectedRideFileName;

  const LiveMapScreen({
    super.key,
    this.onSleepRequested,
    this.selectedRideFileName,
  });

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
  String _activeRouteName = 'No active route';
  Map<String, dynamic>? _activeRoute;
  List<LatLng> _bestRouteTrack = [];
    List<LatLng> _selectedRideTrack = [];
  String? _replayFileName;
  Duration _recordingDuration = Duration.zero;
  late Timer _timerTick;
  Timer? _screenSleepTimer;
  String _userNick = 'User1';
  int _screenOffTimeoutSeconds = 30;
  bool _settingsLoaded = false;
  final GlobalKey _bottomPanelKey = GlobalKey();
  double _bottomPanelHeight = 0;
  bool _showCleanDuration = true;
  int _comparisonRideLimit = 3;
  bool _isLoadingComparisonPositions = false;
  List<LatLng> _historicalRidePositions = [];

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
    _loadSelectedRide();
  }

  Future<void> _loadSelectedRide() async {
    final fileName = widget.selectedRideFileName;
    if (fileName == null || fileName.isEmpty) return;
    try {
      final positions = await GpxService.instance.loadRide(fileName);
      if (!mounted) return;
      setState(() {
        _selectedRideTrack = positions
            .map((position) => LatLng(position.latitude, position.longitude))
            .toList();
      });
    } catch (_) {
      // The map remains usable if the selected GPX file is unavailable.
    }
  }

  Future<void> _loadActiveRoute() async {
    final routeId = await DatabaseService.instance.getActiveRouteId();
    final route = routeId == null ? null : await DatabaseService.instance.getRoute(routeId);
    if (routeId != null) {
      try {
        await RideService.instance.recalculateRouteRides(routeId);
      } catch (error) {
        if (kDebugMode) debugPrint('Comparison timeline rebuild failed: $error');
      }
    }
    final bestTrack = route == null ? <LatLng>[] : await _loadBestRouteTrack(route);
    if (!mounted) return;
    setState(() {
      _activeRouteId = routeId;
      _activeRouteName = route?['name'] as String? ?? 'No active route';
      _activeRoute = route;
      _bestRouteTrack = bestTrack;
    });
    _refreshHistoricalRidePositions();
  }

  Future<List<LatLng>> _loadBestRouteTrack(Map<String, dynamic> route) async {
    final routeId = route['id'] as int?;
    if (routeId == null) return [];
    final mainRideId = await DatabaseService.instance.getMainRideId(routeId);
    if (mainRideId == null) return [];
    final mainRide = await DatabaseService.instance.getRide(mainRideId);
    final fileName = mainRide?['gpx_file_path'] as String?;
    if (fileName == null || fileName.isEmpty) return [];

    try {
      final positions = await GpxService.instance.loadRide(fileName);
      final trimmed = _trimRoutePositions(positions, route);
      return trimmed
          .map((position) => LatLng(position.latitude, position.longitude))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<GPSPosition> _trimRoutePositions(
    List<GPSPosition> positions,
    Map<String, dynamic> route,
  ) {
    if (positions.length < 2) return positions;
    var startIndex = 0;
    var endIndex = positions.length - 1;

    final start = _routePoint(route, 'start_lat', 'start_lon');
    final end = _routePoint(route, 'end_lat', 'end_lon');
    if (start != null) startIndex = _closestPositionIndex(positions, start);
    if (end != null) endIndex = _closestPositionIndex(positions, end);
    if (startIndex >= endIndex) return positions;
    return positions.sublist(startIndex, endIndex + 1);
  }

  LatLng? _routePoint(
    Map<String, dynamic> route,
    String latitudeKey,
    String longitudeKey,
  ) {
    final latitude = (route[latitudeKey] as num?)?.toDouble();
    final longitude = (route[longitudeKey] as num?)?.toDouble();
    return latitude == null || longitude == null
        ? null
        : LatLng(latitude, longitude);
  }

  int _closestPositionIndex(List<GPSPosition> positions, LatLng target) {
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < positions.length; index++) {
      final position = positions[index];
      final distance = GPSService.calculateDistance(
        position.latitude,
        position.longitude,
        target.latitude,
        target.longitude,
      );
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    return closestIndex;
  }

  void _scheduleBottomPanelMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _bottomPanelKey.currentContext?.findRenderObject() as RenderBox?;
      final height = box?.size.height ?? 0;
      if (height != _bottomPanelHeight) {
        setState(() => _bottomPanelHeight = height);
      }
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
        _refreshHistoricalRidePositions();
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
        _showCleanDuration =
            (settings?['show_clean_duration'] as num?)?.toInt() != 0;
        _comparisonRideLimit =
            (settings?['num_rides_to_display'] as num?)?.toInt() ?? 3;
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

  void _refreshHistoricalRidePositions() {
    if (!_isRecording || _activeRouteId == null) return;
    unawaited(_loadHistoricalRidePositions());
  }

  Future<void> _loadHistoricalRidePositions() async {
    if (_isLoadingComparisonPositions || _activeRouteId == null) return;
    _isLoadingComparisonPositions = true;
    try {
      final elapsed = _showCleanDuration
          ? RideService.instance.currentCleanDuration
          : RideService.instance.currentRecordedDuration;
      final rows =
          await DatabaseService.instance.getRidePositionsNearestElapsedTime(
        _activeRouteId!,
        elapsed.inMilliseconds / 1000,
        useCleanTime: _showCleanDuration,
        limit: _comparisonRideLimit,
      );
      if (!mounted) return;
      setState(() {
        _historicalRidePositions = rows
            .map((row) => LatLng(
                  (row['latitude'] as num).toDouble(),
                  (row['longitude'] as num).toDouble(),
                ))
            .toList();
      });
    } finally {
      _isLoadingComparisonPositions = false;
    }
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

  String _formatRecordingDuration(Duration duration) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:'
        '${twoDigits(duration.inMinutes.remainder(60))}:'
        '${twoDigits(duration.inSeconds.remainder(60))}';
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
        title: const Text('Replay saved ride'),
        content: SizedBox(
          width: double.maxFinite,
          child: replayableFiles.isEmpty
              ? const Text('No GPX files found in gpx_test.')
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
      if (!started) throw StateError('The GPX file contains no GPS points.');
      setState(() => _replayFileName = fileName);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start replay: $error')),
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
      if (!_isRecording && !GPSService.instance.isReplaying) {
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
    if (GPSService.instance.isReplaying) return;
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
    _refreshHistoricalRidePositions();
    _scheduleScreenSleep();
    
    // Spusť timer pro aktualizaci doby trvání
    _timerTick = Timer.periodic(Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isPaused) {
        setState(() {
          _recordingDuration = _recordingDuration + Duration(seconds: 1);
        });
        _refreshHistoricalRidePositions();
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
      _historicalRidePositions = [];
    });

    if (mounted) {
      _startLiveTracking();
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? error == null
                    ? 'Ride saved!'
                    : 'Ride saved as unassigned: $error'
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
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
        if (_bestRouteTrack.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _bestRouteTrack,
                color: Colors.blue,
                strokeWidth: 4,
              ),
            ],
          ),
        if (_selectedRideTrack.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _selectedRideTrack,
                color: Colors.green,
                strokeWidth: 4,
              ),
            ],
          ),
        if (_isRecording &&
            (RideService.instance.currentRide?.positions.length ?? 0) >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: RideService.instance.currentRide!.positions
                    .map((position) => LatLng(position.latitude, position.longitude))
                    .toList(),
                color: Colors.red,
                strokeWidth: 4,
              ),
            ],
          ),
        if (_activeRoute != null) _buildRouteToleranceCircles(_activeRoute!),
        if (_isRecording && _historicalRidePositions.isNotEmpty)
          MarkerLayer(
            markers: _historicalRidePositions
                .asMap()
                .entries
                .map(
                  (entry) => Marker(
                    point: entry.value,
                    width: 34,
                    height: 34,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
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

  CircleLayer _buildRouteToleranceCircles(Map<String, dynamic> route) {
    final tolerance = (route['tolerance_radius'] as num?)?.toDouble() ?? 0;
    final circleRadius = tolerance / 2;
    final circles = <CircleMarker>[];

    void addCircle(String latKey, String lonKey, Color color) {
      final latitude = (route[latKey] as num?)?.toDouble();
      final longitude = (route[lonKey] as num?)?.toDouble();
      if (latitude == null || longitude == null || circleRadius <= 0) return;
      circles.add(
        CircleMarker(
          point: LatLng(latitude, longitude),
          radius: circleRadius,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.25),
          borderColor: color,
          borderStrokeWidth: 2,
        ),
      );
    }

    addCircle('start_lat', 'start_lon', Colors.green);
    addCircle('end_lat', 'end_lon', Colors.red);
    return CircleLayer(circles: circles);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBottomPanelMeasurement();
    final mapContent = GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
        // Ends above the bottom panel so the map's own attribution popup is not hidden.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: _bottomPanelHeight,
          child: _buildMapLayer(),
        ),

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

        if (_isRecording && _currentPosition != null)
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      RideService.instance.hasCleanRideStarted
                          ? 'Clean time: ${_formatRecordingDuration(RideService.instance.currentCleanDuration)}'
                          : 'Clean time: waiting for start',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${((RideService.instance.currentRide?.totalDistance ?? 0) / 1000).toStringAsFixed(2)} km',
                    ),
                    Text('${_currentPosition!.altitude.toStringAsFixed(0)} m'),
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
            key: _bottomPanelKey,
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
                            'Active route: $_activeRouteName',
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

        if (_selectedRideTrack.length >= 2)
          Positioned(
            right: 16,
            bottom: 150,
            child: FloatingActionButton.small(
              heroTag: 'clear-selected-ride',
              backgroundColor: Colors.green,
              onPressed: () => setState(() => _selectedRideTrack = []),
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
      ],
      ),
    );

    if (widget.selectedRideFileName != null) {
      return Scaffold(
        body: mapContent,
        bottomNavigationBar: AppBottomNavigation(
          currentIndex: 0,
          onTap: (_) => Navigator.of(context).pop(),
        ),
      );
    }
    return mapContent;
  }
}
