import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'services/database_service.dart';
import 'screens/live_map_screen.dart';
import 'screens/ride_statistics_screen.dart';
import 'screens/route_management_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/bottom_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self Competition',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const MethodChannel _powerChannel =
      MethodChannel('selfcompetition/power');

  int _currentIndex = 0;
  int _screenOffTimeoutSeconds = 30;
  Timer? _screenSleepTimer;
  bool _screenDimmed = false;
  bool _settingsLoaded = false;

  List<Widget> get _screens => [
        LiveMapScreen(onSleepRequested: _dimScreen),
        const RideStatisticsScreen(),
        const RouteManagementScreen(),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPowerSettings();
  }

  Future<void> _loadPowerSettings() async {
    final settings = await DatabaseService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _screenOffTimeoutSeconds =
          (settings?['screen_off_timeout_seconds'] as num?)?.toInt() ?? 30;
      _settingsLoaded = true;
    });
    _scheduleScreenSleep();
  }

  void _scheduleScreenSleep() {
    _screenSleepTimer?.cancel();
    if (!_settingsLoaded) return;
    _screenSleepTimer = Timer(
      Duration(seconds: _screenOffTimeoutSeconds),
      _dimScreen,
    );
  }

  Future<void> _setPowerSavingMode(bool enabled) async {
    await _powerChannel.invokeMethod<void>('setPowerSavingMode', enabled);
  }

  void _dimScreen() {
    if (!mounted || _screenDimmed) return;
    setState(() {
      _screenDimmed = true;
    });
    _setPowerSavingMode(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

  void _onTabSelected(int index) {
    if (_screenDimmed) return;
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _wakeScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screenSleepTimer?.cancel();
    _setPowerSavingMode(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            // Header placeholder - currently unused, reserved for state info
            Container(
              color: Colors.white,
              height: 32,
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _wakeScreen,
                onPanDown: (_) => _wakeScreen(),
                child: Scaffold(
                  body: _screens[_currentIndex],
                  bottomNavigationBar: AppBottomNavigation(
                    currentIndex: _currentIndex,
                    onTap: _onTabSelected,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_screenDimmed)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _wakeScreen,
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: const Text(
                  'Screen dimmed to save battery\nTap to wake',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
