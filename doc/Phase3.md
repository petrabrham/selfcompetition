# Phase 3 - Clean Time and Real-Time Comparison

## Goal

Turn the stored GPX rides into a fair real-time comparison experience. The first priority is a correct clean ride time. Real-time ranking and virtual riders depend on the same processed ride timeline.

## Priority 1 - Clean Ride Time

### Source of Truth

- The original GPX file remains immutable.
- Derived values are stored in SQLite for fast statistics and ranking.
- A processed GPX copy is not created unless future profiling proves it necessary.
- `recorded_duration_seconds` stores the raw duration from the first to last retained GPX timestamp.
- `clean_duration_seconds` stores the duration after trimming and pause detection.
- `Settings.show_clean_duration` controls whether statistics and future real-time UI prefer clean duration or recorded duration, with a safe fallback to recorded duration when clean data is unavailable.

### Materialized Comparison Timeline

GPX remains the immutable source of truth, but it must not be reparsed or scanned on every live refresh. Each route ride therefore gets a derived, local relational timeline rebuilt when its GPX, route boundaries, main ride, or pause settings change.

```text
ComparisonTimelinePoints
   ride_id                    INTEGER NOT NULL
   elapsed_clean_seconds      REAL NOT NULL
   elapsed_recorded_seconds   REAL NOT NULL
   distance_meters            REAL NOT NULL
   latitude                   REAL NOT NULL
   longitude                  REAL NOT NULL
   altitude_meters            REAL
   speed_mps                  REAL
   PRIMARY KEY (ride_id, elapsed_clean_seconds)
```

- A timeline point represents a GPX position on the processed ride timeline.
- Detected pause intervals advance recorded time but do not advance clean time or distance.
- The current live ride maintains the same timeline incrementally as each GPS point arrives; it does not rescan prior points every second.
- At `STOP`, the completed ride is processed again from the complete GPX file as the authoritative persisted result.
- Historical rides are materialized once into SQLite and queried by elapsed time or distance during live comparison.
- The derived timeline is disposable and rebuilt from the original GPX whenever the source or processing parameters change.

### Required Comparison Queries

At live elapsed time `T`:

```text
distanceAtTime(ride, T)
positionAtTime(ride, T)
```

For ranking at `T`:

```text
SELECT ride_id, distance_meters
FROM ComparisonTimelinePoints
WHERE elapsed_clean_seconds <= T
GROUP BY ride_id
ORDER BY distance_meters DESC
```

For a distance checkpoint `D`:

```text
SELECT ride_id, MIN(elapsed_clean_seconds)
FROM ComparisonTimelinePoints
WHERE distance_meters >= D
GROUP BY ride_id
ORDER BY MIN(elapsed_clean_seconds) ASC
```

### Processing Rules

1. Load the original GPX positions for a ride.
2. Trim the ride to the route boundaries:
   - use explicit route start/end circles when configured;
   - otherwise use the first/last point of the route main ride.
3. Detect pauses in the retained GPX path:
   - use `Settings.pause_radius_meters` (default 20 m) as the stationary radius around a pause anchor point;
   - begin a candidate pause at a retained point and keep collecting following points while they remain within the pause radius of that anchor;
   - if the stationary interval is at least `Settings.pause_min_duration_seconds` (default 90 s), exclude its duration;
   - for sparse recorded GPX with no intermediate stationary points, treat a timestamp gap as a pause only when its average movement is at most 1 km/h;
   - exclude that time from `clean_duration_seconds`.
4. Calculate and persist:
   - `saved_at`: first original GPX timestamp;
   - `start_time`: timestamp of the clean start after crossing the route start boundary;
   - `end_time`: timestamp of the trimmed end;
   - `recorded_duration_seconds`: raw trimmed elapsed time;
   - `clean_duration_seconds`: trimmed elapsed time minus detected pauses;
   - `distance_meters`: distance along the trimmed path;
   - `avg_speed_kmh`: distance divided by clean duration;
   - `updated_at`.

### Recalculation Triggers

Recalculate derived ride metadata before saving the database update when:

- recording stops;
- a GPX file is imported;
- a ride is assigned or moved to another route;
- route start or end changes;
- tolerance or pause-detection settings change;
- the route main ride changes when implicit boundaries are in use.
- settings change between clean and recorded timeline mode.

### Acceptance Criteria

- A ride started before a configured start point begins timing at that point.
- A ride ended after a configured end point stops timing at that point.
- Long stationary gaps are excluded from clean duration.
- Statistics and ranking use stored `duration_seconds`, not raw first-to-last timestamps.
- Recalculation never modifies the original GPX file.

## Priority 2 - Real-Time Comparison

### Live Comparison

- Compare the current recording against rides of the active route.
- Build a clean elapsed-time timeline from original GPX points and detected pauses.
- During recording, Ride Statistics ranks the current ride and historical rides by distance reached at the same selected elapsed time; the current ride row is highlighted.
- Estimate historical position at the current clean elapsed time through interpolation between GPS points.
- Display current rank, time loss to the leading ride, and time loss to the ride ahead.
- Render virtual historical riders only for the configured comparison set.

### Acceptance Criteria

- The current rider has a stable rank while recording.
- Historical positions follow their GPX route at the corresponding clean elapsed time.
- Time loss updates from the same processed timeline used for statistics.
- GPS gaps and missing historical points fail gracefully without stopping recording.

## Map Compliance and Provider Strategy

Before expanding map usage:

- Show visible `© OpenStreetMap contributors` attribution on every OSM map.
- Keep a stable, identifiable application User-Agent and use the official HTTPS tile URL for standard OSM tiles.
- Do not prefetch, scrape, or create offline packs from `tile.openstreetmap.org`.
- Add a map provider setting so the tile provider can be changed without a release.
- Use an explicit offline-capable provider or self-hosted tiles before implementing offline map downloads.

## Out of Scope

- Social leaderboards and cloud synchronization.
- Multi-user competition.
- Turn-by-turn navigation.
- Production offline map packs before a compliant provider is chosen.
