import 'dart:io';

import 'package:gpx/gpx.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'gps_service.dart';

class GpxService {
	static final GpxService instance = GpxService._();

	GpxService._();

	Future<String> saveRide({
		required int routeId,
		required int rideId,
		required String userNick,
		required DateTime startTime,
		required List<GPSPosition> positions,
	}) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final rideDirectory = Directory(
			path.join(documentsDirectory.path, 'data', 'routes', '$routeId', 'rides'),
		);
		await rideDirectory.create(recursive: true);

		final gpx = Gpx()..creator = 'Self Competition';
		final track = Trk(name: 'Ride $rideId');
		final segment = Trkseg();
		segment.trkpts.addAll(
			positions.map(
				(position) => Wpt()
					..lat = position.latitude
					..lon = position.longitude
					..ele = position.altitude
					..time = position.timestamp,
			),
		);
		track.trksegs.add(segment);
		gpx.trks.add(track);

		final timestamp = _formatTimestamp(startTime);
		final fileName = '${_sanitizeFileName(userNick)}_$timestamp.gpx';
		final filePath = path.join(rideDirectory.path, fileName);
		await File(filePath).writeAsString(
			GpxWriter().asString(gpx, pretty: true),
		);
		return filePath;
	}

	String _formatTimestamp(DateTime value) {
		String twoDigits(int number) => number.toString().padLeft(2, '0');

		return '${value.year.toString().padLeft(4, '0')}-'
			'${twoDigits(value.month)}-${twoDigits(value.day)}_'
			'${twoDigits(value.hour)}-${twoDigits(value.minute)}';
	}

	String _sanitizeFileName(String value) {
		return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
	}
}
