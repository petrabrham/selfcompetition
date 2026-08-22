import 'dart:io';
import 'dart:typed_data';

import 'package:gpx/gpx.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'gps_service.dart';

class GpxService {
	static final GpxService instance = GpxService._();

	GpxService._();

	/// Load recorded positions from a GPX file stored in the flat gpx/ directory.
	Future<List<GPSPosition>> loadRide(String fileName) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final file = File(path.join(documentsDirectory.path, 'gpx', fileName));
		return _loadPositions(file);
	}

	/// List GPX files reserved for debug replay.
	Future<List<String>> listTestRides() async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final directory = Directory(path.join(documentsDirectory.path, 'gpx_test'));
		if (!await directory.exists()) return [];

		final files = await directory
			.list()
			.where((entry) => entry is File && entry.path.toLowerCase().endsWith('.gpx'))
			.map((entry) => path.basename(entry.path))
			.toList();
		files.sort();
		return files;
	}

	/// Load a debug replay file from the separate gpx_test/ directory.
	Future<List<GPSPosition>> loadTestRide(String fileName) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final file = File(path.join(documentsDirectory.path, 'gpx_test', fileName));
		return _loadPositions(file);
	}

	Future<void> deleteRideFile(String fileName) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final file = File(path.join(documentsDirectory.path, 'gpx', fileName));
		if (await file.exists()) await file.delete();
	}

	/// List GPX files waiting to be imported from gpx_import/.
	Future<List<String>> listImportableFiles() async {
		final directory = await importDirectory;
		if (!await directory.exists()) await directory.create(recursive: true);

		final files = await directory
			.list()
			.where((entry) => entry is File && entry.path.toLowerCase().endsWith('.gpx'))
			.map((entry) => path.basename(entry.path))
			.toList();
		files.sort();
		return files;
	}

	Future<Directory> get importDirectory async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		return Directory(path.join(documentsDirectory.path, 'gpx_import'));
	}

	Future<String> getImportDirectoryPath() async => (await importDirectory).path;

	Future<String> saveImportedBytes(String fileName, Uint8List bytes) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final directory = Directory(path.join(documentsDirectory.path, 'gpx'));
		await directory.create(recursive: true);

		var finalFileName = fileName;
		var finalFilePath = path.join(directory.path, finalFileName);
		var counter = 1;
		final nameWithoutExt = fileName.replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '');
		while (File(finalFilePath).existsSync()) {
			finalFileName = '${nameWithoutExt}_${counter.toString().padLeft(2, '0')}.gpx';
			finalFilePath = path.join(directory.path, finalFileName);
			counter++;
		}
		await File(finalFilePath).writeAsBytes(bytes);
		return finalFileName;
	}

	/// Load positions from a file waiting in gpx_import/.
	Future<List<GPSPosition>> loadImportFile(String fileName) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final file = File(path.join(documentsDirectory.path, 'gpx_import', fileName));
		return _loadPositions(file);
	}

	/// Move an already-validated import file into the flat gpx/ directory.
	/// Returns the final filename (collision-safe) used in gpx/.
	Future<String> moveImportedFileToGpx(String fileName) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final sourceFile = File(path.join(documentsDirectory.path, 'gpx_import', fileName));
		final gpxDirectory = Directory(path.join(documentsDirectory.path, 'gpx'));
		await gpxDirectory.create(recursive: true);

		var finalFileName = fileName;
		var finalFilePath = path.join(gpxDirectory.path, finalFileName);
		var counter = 1;
		final nameWithoutExt = fileName.replaceFirst(RegExp(r'\.gpx$'), '');
		while (File(finalFilePath).existsSync()) {
			finalFileName = '${nameWithoutExt}_${counter.toString().padLeft(2, '0')}.gpx';
			finalFilePath = path.join(gpxDirectory.path, finalFileName);
			counter++;
		}

		await sourceFile.copy(finalFilePath);
		await sourceFile.delete();
		return finalFileName;
	}

	Future<List<GPSPosition>> _loadPositions(File file) async {
		final gpx = GpxReader().fromString(await file.readAsString());
		final positions = <GPSPosition>[];

		for (final track in gpx.trks) {
			for (final segment in track.trksegs) {
				for (final point in segment.trkpts) {
					if (point.lat == null || point.lon == null) continue;
					positions.add(
						GPSPosition(
							latitude: point.lat!,
							longitude: point.lon!,
							altitude: point.ele ?? 0,
							accuracy: 0,
							speed: 0,
							timestamp: point.time ?? DateTime.now(),
						),
					);
				}
			}
		}

		return positions;
	}

	/// Save a ride as GPX file in a flat gpx/ directory
	/// Returns only the filename (not full path)
	Future<String> saveRide({
		required String userNick,
		required DateTime startTime,
		required List<GPSPosition> positions,
	}) async {
		final documentsDirectory = await getApplicationDocumentsDirectory();
		final gpxDirectory = Directory(
			path.join(documentsDirectory.path, 'gpx'),
		);
		await gpxDirectory.create(recursive: true);

		final gpx = Gpx()..creator = 'Self Competition';
		final track = Trk(name: 'Ride');
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
		final filePath = path.join(gpxDirectory.path, fileName);
		
		// Handle filename collision
		int counter = 1;
		String finalFileName = fileName;
		String finalFilePath = filePath;
		while (File(finalFilePath).existsSync()) {
			final fileNameWithoutExt = fileName.replaceFirst(RegExp(r'\.gpx$'), '');
			finalFileName = '${fileNameWithoutExt}_${counter.toString().padLeft(2, '0')}.gpx';
			finalFilePath = path.join(gpxDirectory.path, finalFileName);
			counter++;
		}
		
		await File(finalFilePath).writeAsString(
			GpxWriter().asString(gpx, pretty: true),
		);
		return finalFileName;
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
