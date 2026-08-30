import 'package:flutter_test/flutter_test.dart';
import 'package:selfcompetition/services/gps_service.dart';
import 'package:selfcompetition/services/gpx_processing_service.dart';

void main() {
  final processor = GpxProcessingService.instance;

  test('calculates recorded and clean duration around a pause', () {
    final positions = _positions([
      (0, 0, 0),
      (10, 0, 10),
      (10, 0, 130),
      (20, 0, 140),
    ]);

    final metrics = processor.calculateDurations(
      positions,
      pauseRadiusMeters: 20,
      minimumPauseDurationSeconds: 60,
    );

    expect(metrics.recordedDurationSeconds, 140);
    expect(metrics.cleanDurationSeconds, 20);
  });

  test('materialized timeline preserves recorded time during a pause', () {
    final positions = _positions([
      (0, 0, 0),
      (10, 0, 10),
      (10, 0, 130),
      (20, 0, 140),
    ]);

    final timeline = processor.buildComparisonTimeline(
      positions,
      pauseRadiusMeters: 20,
      minimumPauseDurationSeconds: 60,
    );

    expect(timeline, hasLength(4));
    expect(timeline.last.elapsedRecordedSeconds, 140);
    expect(timeline.last.elapsedCleanSeconds, 20);
    expect(timeline.last.distanceMeters, greaterThan(0));
  });

  test('distanceAtElapsedTime interpolates between recorded points', () {
    final positions = _positions([
      (0, 0, 0),
      (100, 0, 100),
    ]);

    final distance = processor.distanceAtElapsedTime(
      positions,
      elapsed: const Duration(seconds: 50),
      useCleanTime: false,
      pauseRadiusMeters: 20,
      minimumPauseDurationSeconds: 60,
    );

    expect(distance, closeTo(50, 1));
  });
}

List<GPSPosition> _positions(
  List<(double latitude, double longitude, int seconds)> values,
) {
  final start = DateTime.utc(2026, 1, 1);
  return values
      .map((value) => GPSPosition(
            latitude: value.$1 / 111000,
            longitude: value.$2 / 111000,
            altitude: 0,
            accuracy: 1,
            speed: 0,
            timestamp: start.add(Duration(seconds: value.$3)),
          ))
      .toList();
}
