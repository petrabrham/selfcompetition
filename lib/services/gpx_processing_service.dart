import 'gps_service.dart';

class RideDurationMetrics {
  final int recordedDurationSeconds;
  final int cleanDurationSeconds;

  const RideDurationMetrics({
    required this.recordedDurationSeconds,
    required this.cleanDurationSeconds,
  });
}

class ProcessedRide {
  final List<GPSPosition> positions;
  final RideDurationMetrics durationMetrics;
  final double distanceMeters;

  const ProcessedRide({
    required this.positions,
    required this.durationMetrics,
    required this.distanceMeters,
  });
}

class ComparisonTimelinePoint {
  final int pointIndex;
  final double elapsedCleanSeconds;
  final double elapsedRecordedSeconds;
  final double distanceMeters;
  final GPSPosition position;

  const ComparisonTimelinePoint({
    required this.pointIndex,
    required this.elapsedCleanSeconds,
    required this.elapsedRecordedSeconds,
    required this.distanceMeters,
    required this.position,
  });
}

class LiveRideMetrics {
  final Duration recordedDuration;
  final Duration cleanDuration;
  final double recordedDistanceMeters;
  final double cleanDistanceMeters;

  const LiveRideMetrics({
    required this.recordedDuration,
    required this.cleanDuration,
    required this.recordedDistanceMeters,
    required this.cleanDistanceMeters,
  });
}

class LiveRideTimeline {
  final double pauseRadiusMeters;
  final int minimumPauseDurationSeconds;
  final GPSPosition _start;
  GPSPosition _lastCommitted;
  final List<GPSPosition> _pauseCandidate = [];
  Duration _recordedDuration = Duration.zero;
  Duration _cleanDuration = Duration.zero;
  double _recordedDistanceMeters = 0;
  double _cleanDistanceMeters = 0;

  LiveRideTimeline({
    required GPSPosition start,
    required this.pauseRadiusMeters,
    required this.minimumPauseDurationSeconds,
  })  : _start = start,
        _lastCommitted = start;

  LiveRideMetrics get metrics => LiveRideMetrics(
        recordedDuration: _recordedDuration,
        cleanDuration: _cleanDuration,
        recordedDistanceMeters: _recordedDistanceMeters,
        cleanDistanceMeters: _cleanDistanceMeters,
      );

  void add(GPSPosition position) {
    _recordedDuration = position.timestamp.difference(_start.timestamp);
    _recordedDistanceMeters += _distance(_lastCommitted, position);

    if (_pauseCandidate.isEmpty) {
      _pauseCandidate.add(_lastCommitted);
    }
    _pauseCandidate.add(position);
    final anchor = _pauseCandidate.first;

    if (_distance(anchor, position) <= pauseRadiusMeters) {
      _lastCommitted = position;
      return;
    }

    final candidateDuration = position.timestamp
        .difference(anchor.timestamp)
        .inSeconds;
    final candidateDistance = _distance(anchor, position);
    final sparsePause = _pauseCandidate.length == 2 &&
        candidateDuration >= minimumPauseDurationSeconds &&
        candidateDistance / candidateDuration <= 1 / 3.6;
    final stationaryPause = _pauseCandidate.length > 2 &&
        _pauseCandidate[_pauseCandidate.length - 2].timestamp
                .difference(anchor.timestamp)
                .inSeconds >=
            minimumPauseDurationSeconds;

    if (sparsePause || stationaryPause) {
      _lastCommitted = position;
      _pauseCandidate
        ..clear()
        ..add(position);
      return;
    }

    _commitCandidate();
    _pauseCandidate
      ..clear()
      ..add(position);
    _lastCommitted = position;
  }

  void _commitCandidate() {
    for (var index = 1; index < _pauseCandidate.length; index++) {
      final first = _pauseCandidate[index - 1];
      final second = _pauseCandidate[index];
      _cleanDuration += second.timestamp.difference(first.timestamp);
      _cleanDistanceMeters += _distance(first, second);
    }
  }

  double _distance(GPSPosition first, GPSPosition second) {
    return GPSService.calculateDistance(
      first.latitude,
      first.longitude,
      second.latitude,
      second.longitude,
    );
  }
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

  double distanceAtElapsedTime(
    List<GPSPosition> positions, {
    required Duration elapsed,
    required bool useCleanTime,
    required double pauseRadiusMeters,
    required int minimumPauseDurationSeconds,
  }) {
    if (positions.length < 2 || elapsed.isNegative) return 0;
    final pausedSegments = useCleanTime
        ? _pausedSegmentIndices(
            positions,
            pauseRadiusMeters: pauseRadiusMeters,
            minimumPauseDurationSeconds: minimumPauseDurationSeconds,
          )
        : <int>{};
    final targetSeconds = elapsed.inMilliseconds / 1000;
    var elapsedSeconds = 0.0;
    var distanceMeters = 0.0;

    for (var index = 0; index < positions.length - 1; index++) {
      final first = positions[index];
      final second = positions[index + 1];
      final segmentSeconds = second.timestamp.difference(first.timestamp).inMilliseconds / 1000;
      final segmentDistance = _distanceBetween(first, second);
      final paused = pausedSegments.contains(index);
      final effectiveSeconds = paused ? 0.0 : segmentSeconds;
      final effectiveDistance = paused ? 0.0 : segmentDistance;

      if (effectiveSeconds > 0 && elapsedSeconds + effectiveSeconds >= targetSeconds) {
        final fraction = ((targetSeconds - elapsedSeconds) / effectiveSeconds).clamp(0.0, 1.0);
        return distanceMeters + effectiveDistance * fraction;
      }
      elapsedSeconds += effectiveSeconds;
      distanceMeters += effectiveDistance;
    }
    return distanceMeters;
  }

  Set<int> _pausedSegmentIndices(
    List<GPSPosition> positions, {
    required double pauseRadiusMeters,
    required int minimumPauseDurationSeconds,
  }) {
    final paused = <int>{};
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
      final sparseGap = nextIndex == anchorIndex + 1 &&
          _isSparsePauseGap(
            anchor,
            positions[nextIndex],
            minimumPauseDurationSeconds,
          );
      if (stationarySeconds >= minimumPauseDurationSeconds || sparseGap) {
        for (var segment = anchorIndex; segment < nextIndex; segment++) {
          paused.add(segment);
        }
        anchorIndex = nextIndex;
      } else {
        anchorIndex++;
      }
    }
    return paused;
  }

  ProcessedRide processRide(
    List<GPSPosition> positions, {
    GPSPosition? startBoundary,
    GPSPosition? endBoundary,
    required double pauseRadiusMeters,
    required int minimumPauseDurationSeconds,
  }) {
    final trimmed = _trimToBoundaries(
      positions,
      startBoundary: startBoundary,
      endBoundary: endBoundary,
    );
    return ProcessedRide(
      positions: trimmed,
      durationMetrics: calculateDurations(
        trimmed,
        pauseRadiusMeters: pauseRadiusMeters,
        minimumPauseDurationSeconds: minimumPauseDurationSeconds,
      ),
      distanceMeters: _calculateDistance(trimmed),
    );
  }

  List<ComparisonTimelinePoint> buildComparisonTimeline(
    List<GPSPosition> positions, {
    required double pauseRadiusMeters,
    required int minimumPauseDurationSeconds,
  }) {
    if (positions.isEmpty) return [];
    final pausedSegments = _pausedSegmentIndices(
      positions,
      pauseRadiusMeters: pauseRadiusMeters,
      minimumPauseDurationSeconds: minimumPauseDurationSeconds,
    );
    final timeline = <ComparisonTimelinePoint>[];
    var cleanSeconds = 0.0;
    var recordedSeconds = 0.0;
    var distanceMeters = 0.0;
    timeline.add(
      ComparisonTimelinePoint(
        pointIndex: 0,
        elapsedCleanSeconds: 0,
        elapsedRecordedSeconds: 0,
        distanceMeters: 0,
        position: positions.first,
      ),
    );

    for (var index = 1; index < positions.length; index++) {
      final first = positions[index - 1];
      final second = positions[index];
      final segmentSeconds = second.timestamp
              .difference(first.timestamp)
              .inMilliseconds /
          1000;
      final segmentDistance = _distanceBetween(first, second);
      recordedSeconds += segmentSeconds;
      if (!pausedSegments.contains(index - 1)) {
        cleanSeconds += segmentSeconds;
        distanceMeters += segmentDistance;
      }
      timeline.add(
        ComparisonTimelinePoint(
          pointIndex: index,
          elapsedCleanSeconds: cleanSeconds,
          elapsedRecordedSeconds: recordedSeconds,
          distanceMeters: distanceMeters,
          position: second,
        ),
      );
    }
    return timeline;
  }

  List<GPSPosition> _trimToBoundaries(
    List<GPSPosition> positions, {
    GPSPosition? startBoundary,
    GPSPosition? endBoundary,
  }) {
    if (positions.length < 2) return positions;
    final startIndex = startBoundary == null
        ? 0
        : _closestIndex(positions, startBoundary);
    final endIndex = endBoundary == null
        ? positions.length - 1
        : _closestIndex(positions, endBoundary);
    if (startIndex >= endIndex) return positions;
    return positions.sublist(startIndex, endIndex + 1);
  }

  int _closestIndex(List<GPSPosition> positions, GPSPosition target) {
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < positions.length; index++) {
      final distance = _distanceBetween(positions[index], target);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    return closestIndex;
  }

  double _calculateDistance(List<GPSPosition> positions) {
    var distance = 0.0;
    for (var index = 1; index < positions.length; index++) {
      distance += _distanceBetween(positions[index - 1], positions[index]);
    }
    return distance;
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
