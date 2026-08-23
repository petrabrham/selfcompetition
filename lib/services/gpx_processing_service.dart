import 'gps_service.dart';

class RideDurationMetrics {
  final int recordedDurationSeconds;
  final int cleanDurationSeconds;

  const RideDurationMetrics({
    required this.recordedDurationSeconds,
    required this.cleanDurationSeconds,
  });
}

class GpxProcessingService {
  static final GpxProcessingService instance = GpxProcessingService._();

  GpxProcessingService._();

  RideDurationMetrics calculateDurations(
    List<GPSPosition> positions, {
    required double pauseRadiusMeters,
    required int minimumPauseDurationSeconds,
  }) {
    if (positions.length < 2) {
      return const RideDurationMetrics(
        recordedDurationSeconds: 0,
        cleanDurationSeconds: 0,
      );
    }

    final recordedDuration = positions.last.timestamp
        .difference(positions.first.timestamp)
        .inSeconds
        .clamp(0, 1 << 31);
    var pausedSeconds = 0;
    var anchorIndex = 0;

    while (anchorIndex < positions.length - 1) {
      final anchor = positions[anchorIndex];
      var nextIndex = anchorIndex + 1;
      while (nextIndex < positions.length &&
          _distanceBetween(anchor, positions[nextIndex]) <= pauseRadiusMeters) {
        nextIndex++;
      }

      final lastStationaryIndex = nextIndex - 1;
      final stationarySeconds = positions[lastStationaryIndex].timestamp
          .difference(anchor.timestamp)
          .inSeconds;
      if (stationarySeconds >= minimumPauseDurationSeconds) {
        pausedSeconds += stationarySeconds;
        anchorIndex = nextIndex;
      } else if (nextIndex == anchorIndex + 1 &&
          _isSparsePauseGap(
            anchor,
            positions[nextIndex],
            minimumPauseDurationSeconds,
          )) {
        pausedSeconds += positions[nextIndex].timestamp
            .difference(anchor.timestamp)
            .inSeconds;
        anchorIndex = nextIndex;
      } else {
        anchorIndex++;
      }
    }

    return RideDurationMetrics(
      recordedDurationSeconds: recordedDuration,
      cleanDurationSeconds: (recordedDuration - pausedSeconds).clamp(0, recordedDuration),
    );
  }

  double _distanceBetween(GPSPosition first, GPSPosition second) {
    return GPSService.calculateDistance(
      first.latitude,
      first.longitude,
      second.latitude,
      second.longitude,
    );
  }

  bool _isSparsePauseGap(
    GPSPosition first,
    GPSPosition second,
    int minimumPauseDurationSeconds,
  ) {
    final gapSeconds = second.timestamp.difference(first.timestamp).inSeconds;
    if (gapSeconds < minimumPauseDurationSeconds) return false;
    final averageSpeedMetersPerSecond =
        _distanceBetween(first, second) / gapSeconds;
    return averageSpeedMetersPerSecond <= 1 / 3.6;
  }
}
