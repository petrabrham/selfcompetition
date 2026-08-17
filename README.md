# Self Competition

Self Competition is a Flutter cycling application for recording rides and,
later, comparing them against previous rides on the same route.

The project is currently moving from the completed Phase 1 MVP to Phase 2,
which focuses on route and ride management.

## Current Features

- Live OpenStreetMap map with the current GPS position
- GPS tracking with configurable update interval and distance threshold
- Ride recording with START, PAUSE, RESUME and STOP controls
- Ride distance and duration tracking
- Saving ride metadata to SQLite
- GPX generation for recorded rides
- User nickname and recording settings
- Global screen-saving mode on all screens
- Configurable screen timeout from 30 seconds to 15 minutes
- Portrait-only application layout
- Free map rotation and North-Up rotation lock
- Persistent map camera position and follow-position toggle
- Android foreground location service for background recording
- Custom Android and iOS launcher icons

## Screens

- **Live Map**: map, GPS position, recording controls and map controls
- **Ride Statistics**: placeholder for ride comparison and statistics
- **Route Management**: foundation for routes and stored rides
- **Settings**: nickname, GPS recording and screen timeout settings

## Technology

- Flutter 3.44.9 or newer
- Dart 3.12.2 or newer
- `flutter_map` with OpenStreetMap tiles
- `geolocator` for GPS tracking
- `sqflite` for local metadata storage
- `gpx` for GPX file generation
- `path_provider` and `path` for application storage
- Android foreground location service

## Requirements

- Flutter SDK 3.44.9+
- Dart SDK 3.12.2+
- Android SDK configured for the project
- A physical Android device or emulator with location services enabled
- Internet access for live OpenStreetMap tiles

The application requests location permissions and, on Android, uses a
foreground notification while tracking location in the background.

## Running Locally

From the project directory:

```bash
flutter pub get
flutter analyze
flutter run
```

To run on a specific Android device:

```bash
flutter devices
flutter run -d <device-id>
```

The current Android build can also be compiled with:

```bash
cd android
./gradlew :app:compileDebugKotlin
```

On Windows PowerShell, use `gradlew.bat` instead of `./gradlew`.

## App Icon

The launcher icon source is stored at `assets/icons/app_icon.png`.

To regenerate Android and iOS launcher icons after replacing the source image:

```bash
dart run flutter_launcher_icons
```

## Energy Saving

The application uses a global screen-saving mode independent of whether a ride
is being recorded. After the configured inactivity timeout it applies:

- a black overlay over the complete application, including navigation,
- window brightness set to zero,
- Android `PARTIAL_WAKE_LOCK` for continued CPU/GPS work,
- `KEEP_SCREEN_ON` to prevent the ordinary system timeout from locking the
	device.

The first tap on the overlay only wakes the application. It does not activate
the control underneath it. The Android Power button remains a system action and
may activate the device lock screen according to the phone's security settings.

## Roadmap

### Phase 1: MVP - completed

- Basic navigation and four application screens
- GPS tracking and live map
- Ride recording and persistence
- GPX generation
- Settings
- Energy-saving behavior

### Phase 2: Route and Ride Management - next

- Create and select routes
- Assign rides to routes
- Browse stored rides
- View, export and delete rides
- Route start and finish positions
- Reliable pause handling in stored tracks

### Phase 3: Real-Time Comparison

- Compare the current ride with stored rides on the selected route
- Virtual competitors on the map
- Real-time ranking
- Time difference to faster rides
- Motivation and trend indicators

### Later

- GPX import and full export management
- Cached and offline map tiles
- Route corridor and tolerance detection
- Course-Up map orientation
- Performance improvements and production polish

## Documentation

- [Application requirements](doc/APP_REQUIREMENTS.md)
- [Phase 1 notes](doc/phase1.md)
- [Flutter installation checklist](doc/flutter-install-checklist.md)
