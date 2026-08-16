import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// SQLite Database Service
/// Manages all database operations for Routes, Rides, and Settings tables
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  static DatabaseService get instance => _instance;

  Database? _database;

  DatabaseService._internal();

  /// Get database instance, initializing if necessary
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database and create tables
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'selfcompetition.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE Settings ADD COLUMN screen_off_timeout_seconds INTEGER DEFAULT 30',
      );
    }
  }

  /// Create all tables
  Future<void> _createTables(Database db, int version) async {
    // Routes table - stores route definitions
    await db.execute('''
      CREATE TABLE Routes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        start_lat REAL NOT NULL,
        start_lon REAL NOT NULL,
        end_lat REAL NOT NULL,
        end_lon REAL NOT NULL,
        tolerance_radius REAL DEFAULT 50.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Rides table - stores individual ride recordings
    await db.execute('''
      CREATE TABLE Rides(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        route_id INTEGER NOT NULL,
        gpx_file_path TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        distance_meters REAL DEFAULT 0.0,
        avg_speed_kmh REAL DEFAULT 0.0,
        user_nick TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (route_id) REFERENCES Routes(id)
      )
    ''');

    // Settings table - stores user preferences
    await db.execute('''
      CREATE TABLE Settings(
        id INTEGER PRIMARY KEY,
        user_nick TEXT,
        gps_update_interval_ms INTEGER DEFAULT 1000,
        min_distance_threshold_meters REAL DEFAULT 5.0,
        num_rides_to_display INTEGER DEFAULT 3,
        screen_off_timeout_seconds INTEGER DEFAULT 30,
        updated_at TEXT NOT NULL
      )
    ''');

    // Initialize default settings
    await db.insert('Settings', {
      'id': 1,
      'user_nick': 'User1',
      'gps_update_interval_ms': 5000,
      'min_distance_threshold_meters': 5.0,
      'num_rides_to_display': 3,
      'screen_off_timeout_seconds': 30,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// ============ ROUTES OPERATIONS ============

  /// Get all routes
  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final db = await database;
    return await db.query('Routes', orderBy: 'created_at DESC');
  }

  /// Get single route by ID
  Future<Map<String, dynamic>?> getRoute(int id) async {
    final db = await database;
    final result = await db.query('Routes', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  /// Insert new route
  Future<int> insertRoute(Map<String, dynamic> route) async {
    final db = await database;
    return await db.insert('Routes', route);
  }

  /// Update route
  Future<int> updateRoute(int id, Map<String, dynamic> route) async {
    final db = await database;
    return await db.update(
      'Routes',
      route,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete route
  Future<int> deleteRoute(int id) async {
    final db = await database;
    return await db.delete('Routes', where: 'id = ?', whereArgs: [id]);
  }

  /// ============ RIDES OPERATIONS ============

  /// Get all rides
  Future<List<Map<String, dynamic>>> getAllRides() async {
    final db = await database;
    return await db.query('Rides', orderBy: 'start_time DESC');
  }

  /// Get rides by route
  Future<List<Map<String, dynamic>>> getRidesByRoute(int routeId) async {
    final db = await database;
    return await db.query(
      'Rides',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'start_time DESC',
    );
  }

  /// Get single ride by ID
  Future<Map<String, dynamic>?> getRide(int id) async {
    final db = await database;
    final result = await db.query('Rides', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  /// Insert new ride
  Future<int> insertRide(Map<String, dynamic> ride) async {
    final db = await database;
    return await db.insert('Rides', ride);
  }

  /// Update ride
  Future<int> updateRide(int id, Map<String, dynamic> ride) async {
    final db = await database;
    return await db.update(
      'Rides',
      ride,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete ride
  Future<int> deleteRide(int id) async {
    final db = await database;
    return await db.delete('Rides', where: 'id = ?', whereArgs: [id]);
  }

  /// Get recent rides for a route (for comparison/ranking)
  Future<List<Map<String, dynamic>>> getRecentRidesForRoute(
    int routeId, {
    required int limit,
  }) async {
    final db = await database;
    return await db.query(
      'Rides',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'start_time DESC',
      limit: limit,
    );
  }

  /// ============ SETTINGS OPERATIONS ============

  /// Get app settings
  Future<Map<String, dynamic>?> getSettings() async {
    final db = await database;
    final result = await db.query('Settings', where: 'id = ?', whereArgs: [1]);
    return result.isNotEmpty ? result.first : null;
  }

  /// Update settings
  Future<int> updateSettings(Map<String, dynamic> settings) async {
    final db = await database;
    settings['updated_at'] = DateTime.now().toIso8601String();
    return await db.update(
      'Settings',
      settings,
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  /// Update user nick
  Future<int> updateUserNick(String nick) async {
    return await updateSettings({'user_nick': nick});
  }

  /// Update GPS interval
  Future<int> updateGpsInterval(int intervalMs) async {
    return await updateSettings({'gps_update_interval_ms': intervalMs});
  }

  /// Update minimum distance threshold
  Future<int> updateMinDistanceThreshold(double meters) async {
    return await updateSettings({'min_distance_threshold_meters': meters});
  }

  /// ============ UTILITY OPERATIONS ============

  /// Close database connection
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Clear all data (for testing/reset)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('Rides');
    await db.delete('Routes');
  }
}
