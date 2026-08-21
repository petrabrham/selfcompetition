import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Full-screen map with a fixed center crosshair; returns the centered
/// position via Navigator.pop when the user confirms.
class MapPositionPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initialPosition;

  const MapPositionPickerScreen({
    required this.title,
    this.initialPosition,
    super.key,
  });

  @override
  State<MapPositionPickerScreen> createState() =>
      _MapPositionPickerScreenState();
}

class _MapPositionPickerScreenState extends State<MapPositionPickerScreen> {
  static const _fallbackPosition = LatLng(50.0755, 14.4378); // Praha

  late final MapController _mapController;
  late LatLng _center;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = widget.initialPosition ?? _fallbackPosition;
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    _mapController.move(_mapController.camera.center, _mapController.camera.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context, _center),
            icon: const Icon(Icons.check),
            tooltip: 'Potvrdit pozici',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 17,
              maxZoom: 19,
              onMapReady: () => setState(() => _mapReady = true),
              onPositionChanged: (camera, hasGesture) {
                setState(() => _center = camera.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.selfcompetition',
              ),
            ],
          ),
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.add, size: 42, color: Colors.red),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.blue,
                  onPressed: () => _zoomBy(1),
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.blue,
                  onPressed: () => _zoomBy(-1),
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
