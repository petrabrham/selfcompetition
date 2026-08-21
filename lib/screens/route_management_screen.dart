import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/database_service.dart';
import '../services/gps_service.dart';
import '../services/gpx_service.dart';
import '../services/ride_service.dart';
import 'map_position_picker_screen.dart';

class RouteManagementScreen extends StatefulWidget {
  const RouteManagementScreen({super.key});
  @override State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}
class _RouteManagementScreenState extends State<RouteManagementScreen> {
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trasy'),
      actions: [
        IconButton(
          onPressed: () => _importGpxFiles(context),
          icon: const Icon(Icons.file_download_outlined),
          tooltip: 'Import GPX (gpx_import/)',
        ),
      ],
    ),
    body: FutureBuilder<List<Object?>>(
      future: Future.wait<Object?>([
        DatabaseService.instance.getRoutes(),
        DatabaseService.instance.getRidesWithoutRoute(),
        DatabaseService.instance.getActiveRouteId(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Chyba: ${snapshot.error}'));
        final data = snapshot.data!;
        final routes = data[0] as List<Map<String, dynamic>>;
        final unassignedRides = data[1] as List<Map<String, dynamic>>;
        final activeRouteId = data[2] as int?;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (unassignedRides.isNotEmpty)
              _RideGroupListItem(
                title: 'Nezařazené jízdy',
                rideCount: unassignedRides.length,
                onTap: () => _push(
                  context,
                  const RouteDetailScreen(routeId: null),
                ),
              ),
            if (routes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Žádné trasy')),
              )
            else
              ...routes.map((route) {
                final id = route['id'] as int;
                return _RouteListItem(
                  route: route,
                  isActive: id == activeRouteId,
                  onTap: () => _push(context, RouteDetailScreen(routeId: id)),
                  onEdit: () => _push(context, RouteFormScreen(routeId: id)),
                  onToggleActive: () => _toggleActiveRoute(id, id == activeRouteId),
                );
              }),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton(onPressed: () => _push(context, const RouteFormScreen()), child: const Icon(Icons.add)),
  );
  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) { if (mounted) setState(() {}); });

  Future<void> _toggleActiveRoute(int routeId, bool isCurrentlyActive) async {
    await DatabaseService.instance.setActiveRouteId(isCurrentlyActive ? null : routeId);
    if (mounted) setState(() {});
  }

  Future<void> _importGpxFiles(BuildContext context) async {
    final result = await RideService.instance.importGpxFiles();
    if (!context.mounted) return;

    final message = result.failed.isEmpty
        ? 'Importováno ${result.imported} jízd.'
        : 'Importováno ${result.imported} jízd. Selhalo: ${result.failed.length} (${result.failed.keys.join(', ')})';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    setState(() {});
  }
}

class _RideGroupListItem extends StatelessWidget {
  final String title;
  final int rideCount;
  final VoidCallback onTap;

  const _RideGroupListItem({
    required this.title,
    required this.rideCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.route),
      title: Text(title),
      subtitle: Text('$rideCount jízd'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _RouteListItem extends StatelessWidget {
  final Map<String,dynamic> route; final bool isActive; final VoidCallback onTap; final VoidCallback onEdit; final VoidCallback onToggleActive;
  const _RouteListItem({required this.route, required this.isActive, required this.onTap, required this.onEdit, required this.onToggleActive});
  @override Widget build(BuildContext context) => FutureBuilder<List<Map<String,dynamic>>>(
    future: DatabaseService.instance.getRidesByRoute(route['id'] as int),
    builder: (_, snapshot) => Card(
      color: isActive ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Checkbox(value: isActive, onChanged: (_) => onToggleActive()),
        title: Text(route['name'] as String? ?? 'Bez názvu'), subtitle: Text('${snapshot.data?.length ?? 0} jízd'), onTap: onTap,
        trailing: PopupMenuButton<String>(onSelected: (_) => onEdit(), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Upravit'))]),
      ),
    ),
  );
}

class RouteDetailScreen extends StatefulWidget {
  final int? routeId;

  const RouteDetailScreen({required this.routeId, super.key});

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  late Future<List<Map<String, dynamic>>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _refreshRides();
  }

  void _refreshRides() {
    _ridesFuture = widget.routeId == null
        ? DatabaseService.instance.getRidesWithoutRoute()
        : DatabaseService.instance.getRidesByRoute(widget.routeId!);
  }

  void _reloadRides() {
    if (!mounted) return;
    setState(_refreshRides);
  }

  Future<void> _deleteRide(Map<String, dynamic> ride) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat jízdu?'),
        content: const Text('Jízda a její GPX soubor budou odstraněny.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Zrušit')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Smazat')),
        ],
      ),
    );
    if (shouldDelete != true) return;

    final id = ride['id'] as int;
    await DatabaseService.instance.deleteRide(id);
    final fileName = ride['gpx_file_path'] as String?;
    if (fileName != null && fileName.isNotEmpty) {
      await GpxService.instance.deleteRideFile(fileName);
    }
    _reloadRides();
  }

  Future<void> _moveRide(Map<String, dynamic> ride) async {
    final routes = await DatabaseService.instance.getRoutes();
    if (!mounted) return;
    var selectionMade = false;
    final targetRouteId = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Přesunout jízdu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Nezařazené'),
                onTap: () {
                  selectionMade = true;
                  Navigator.pop(context, null);
                },
              ),
              ...routes.map((route) => ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(route['name'] as String? ?? 'Bez názvu'),
                    onTap: () {
                      selectionMade = true;
                      Navigator.pop(context, route['id'] as int);
                    },
                  )),
            ],
          ),
        ),
      ),
    );

    final currentRouteId = widget.routeId;
    if (!mounted || !selectionMade || targetRouteId == currentRouteId) return;
    await DatabaseService.instance.updateRide(
      ride['id'] as int,
      {'route_id': targetRouteId},
    );
    _reloadRides();
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.routeId == null ? 'Nezařazené jízdy' : 'Detail Trasy')),
    body: FutureBuilder<List<Map<String,dynamic>>>(
      future: _ridesFuture,
      builder: (context, rideSnapshot) {
        if (rideSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rides = rideSnapshot.data ?? <Map<String,dynamic>>[];
        final sortedRides = rides.toList()
          ..sort((a, b) => _rideStartTime(b).compareTo(_rideStartTime(a)));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            widget.routeId == null ? 'Nezařazené jízdy' : 'Jízdy na trase',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20), Text('Jízdy (${rides.length})'),
          if (rides.isEmpty)
            const Text('Žádné jízdy')
          else
            ...sortedRides.map((ride) => _RideListItem(
                  ride: ride,
                  onDelete: () => _deleteRide(ride),
                  onMove: () => _moveRide(ride),
                )),
        ]);
      },
    ),
  );
}

DateTime _rideStartTime(Map<String, dynamic> ride) {
  return DateTime.tryParse(ride['start_time'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

class _RideListItem extends StatelessWidget {
  final Map<String, dynamic> ride;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  const _RideListItem({
    required this.ride,
    required this.onDelete,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final startTime = _rideStartTime(ride);
    final endTime = DateTime.tryParse(ride['end_time'] as String? ?? '');
    final duration = endTime?.difference(startTime);
    final distanceKm = ((ride['distance_meters'] as num?)?.toDouble() ?? 0) / 1000;

    return ListTile(
      leading: const Icon(Icons.directions_bike),
      title: Text(ride['user_nick'] as String? ?? 'Bez přezdívky'),
      subtitle: Text(
        '${_formatDateTime(startTime)}  |  ${distanceKm.toStringAsFixed(1)} km  |  ${_formatDuration(duration)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'move') onMove();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'move',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.drive_file_move_outlined),
              title: Text('Přesunout do trasy'),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Smazat jízdu'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year.toString().padLeft(4, '0')}-'
      '${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String _formatDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

class RouteFormScreen extends StatefulWidget {
  final int? routeId; const RouteFormScreen({this.routeId, super.key});
  @override State<RouteFormScreen> createState() => _RouteFormScreenState();
}
class _RouteFormScreenState extends State<RouteFormScreen> {
  final key = GlobalKey<FormState>(); final name = TextEditingController(); final description = TextEditingController();
  final startLat = TextEditingController(); final startLon = TextEditingController(); final endLat = TextEditingController(); final endLon = TextEditingController(); final tolerance = TextEditingController();
  bool loading = false, saving = false;
  @override void initState() { super.initState(); if (widget.routeId != null) load(); }
  Future<void> load() async { setState(() => loading = true); final r = await DatabaseService.instance.getRoute(widget.routeId!); if (!mounted) return; if (r != null) { name.text = r['name'] as String? ?? ''; description.text = r['description'] as String? ?? ''; startLat.text = v(r['start_lat']); startLon.text = v(r['start_lon']); endLat.text = v(r['end_lat']); endLon.text = v(r['end_lon']); tolerance.text = v(r['tolerance_radius']); } setState(() => loading = false); }
  String v(dynamic x) => x?.toString() ?? '';
  @override void dispose() { name.dispose(); description.dispose(); startLat.dispose(); startLon.dispose(); endLat.dispose(); endLon.dispose(); tolerance.dispose(); super.dispose(); }
  double? n(String x) => x.trim().isEmpty ? null : double.tryParse(x.trim());
  Future<void> save() async { if (!key.currentState!.validate()) return; setState(() => saving = true); final now = DateTime.now().toIso8601String(); final r = <String,dynamic>{'name': name.text.trim(), 'description': description.text.trim().isEmpty ? null : description.text.trim(), 'start_lat': n(startLat.text), 'start_lon': n(startLon.text), 'end_lat': n(endLat.text), 'end_lon': n(endLon.text), 'tolerance_radius': n(tolerance.text) ?? 50.0, 'updated_at': now}; try { if (widget.routeId == null) { r['created_at'] = now; await DatabaseService.instance.insertRoute(r); } else { await DatabaseService.instance.updateRoute(widget.routeId!, r); } if (mounted) Navigator.pop(context); } catch (e) { if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba: $e'))); } } }
  Widget field(TextEditingController c, String label) => TextFormField(controller: c, decoration: InputDecoration(labelText: label), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (x) => x != null && x.trim().isNotEmpty && n(x) == null ? 'Zadejte číslo' : null);

  Future<void> pickFromMap(TextEditingController latController, TextEditingController lonController, String title, {required bool useLastGpxPosition}) async {
    final currentLat = double.tryParse(latController.text.trim());
    final currentLon = double.tryParse(lonController.text.trim());
    final initial = (currentLat != null && currentLon != null)
        ? LatLng(currentLat, currentLon)
        : await _initialGpxPosition(useLastGpxPosition);
    if (!mounted) return;
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => MapPositionPickerScreen(title: title, initialPosition: initial)),
    );
    if (result == null || !mounted) return;
    setState(() {
      latController.text = result.latitude.toStringAsFixed(6);
      lonController.text = result.longitude.toStringAsFixed(6);
    });
  }

  /// Výchozí pozice pro picker - bod z aktivní trasy, jinak aktuální GPS pozice.
  /// Pokud ani ta není dostupná, MapPositionPickerScreen sám spadne na Prahu.
  Future<LatLng?> _initialGpxPosition(bool useLastGpxPosition) async {
    final activeRouteId = await DatabaseService.instance.getActiveRouteId();
    if (activeRouteId != null) {
      final rides = await DatabaseService.instance.getRidesByRoute(activeRouteId);
      final position = await _positionFromRides(rides, useLastGpxPosition);
      if (position != null) return position;
    }
    return _currentGpsPosition();
  }

  Future<LatLng?> _currentGpsPosition() async {
    final cached = GPSService.instance.currentPosition;
    if (cached != null) return LatLng(cached.latitude, cached.longitude);
    final position = await GPSService.instance.getCurrentPosition();
    return position == null ? null : LatLng(position.latitude, position.longitude);
  }

  Future<LatLng?> _positionFromRides(
    List<Map<String, dynamic>> rides,
    bool useLastGpxPosition,
  ) async {
    for (final ride in rides) {
      final fileName = ride['gpx_file_path'] as String?;
      if (fileName == null || fileName.isEmpty) continue;
      try {
        final positions = await GpxService.instance.loadRide(fileName);
        if (positions.isNotEmpty) {
          final position = useLastGpxPosition ? positions.last : positions.first;
          return LatLng(position.latitude, position.longitude);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Widget positionFields(TextEditingController latController, TextEditingController lonController, String label, String pickerTitle, {required bool useLastGpxPosition}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: field(latController, '$label latitude')),
          const SizedBox(width: 8),
          Expanded(child: field(lonController, '$label longitude')),
        ],
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => pickFromMap(latController, lonController, pickerTitle, useLastGpxPosition: useLastGpxPosition),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Zadat z mapy'),
        ),
      ),
    ],
  );

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.routeId == null ? 'Nová Trasa' : 'Upravit Trasu')), body: loading ? const Center(child: CircularProgressIndicator()) : Form(key: key, child: ListView(padding: const EdgeInsets.all(16), children: [TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Název *'), validator: (x) => x == null || x.trim().isEmpty ? 'Název trasy je povinný' : null), TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Popis'), maxLines: 3), positionFields(startLat, startLon, 'Start', 'Vyberte start na mapě', useLastGpxPosition: false), const SizedBox(height: 12), positionFields(endLat, endLon, 'End', 'Vyberte cíl na mapě', useLastGpxPosition: true), field(tolerance, 'Toleranční radius'), const SizedBox(height: 20), ElevatedButton(onPressed: saving ? null : save, child: Text(saving ? 'Ukládám...' : 'Uložit'))])));
}
