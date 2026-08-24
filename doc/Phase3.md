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
