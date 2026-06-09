import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/posture_status.dart';
import '../models/session_summary.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'postureguard.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE posture_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            status INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL UNIQUE,
            date TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            good_posture_percent REAL NOT NULL,
            longest_streak INTEGER NOT NULL,
            worst_moment_timestamp INTEGER
          )
        ''');
      },
    );
  }

  // ─── Per-second event logging ───

  static Future<void> logEvent({
    required String sessionId,
    required PostureStatus status,
  }) async {
    final db = await database;
    await db.insert('posture_events', {
      'session_id': sessionId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'status': status.value,
    });
  }

  // ─── Session summary computation ───

  static Future<SessionSummary> endSession(String sessionId) async {
    final db = await database;

    final events = await db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    final totalRecords = events.length;
    if (totalRecords == 0) {
      final summary = SessionSummary(
        sessionId: sessionId,
        date: DateTime.now(),
        durationSeconds: 0,
        goodPosturePercent: 0,
        longestStreakSeconds: 0,
      );
      await _saveSession(summary);
      return summary;
    }

    // Duration
    final firstTs = events.first['timestamp'] as int;
    final lastTs = events.last['timestamp'] as int;
    final durationSeconds = ((lastTs - firstTs) / 1000).round().clamp(1, 999999);

    // Good posture percentage
    final goodCount = events.where((e) => e['status'] == 0).length;
    final goodPercent = (goodCount / totalRecords) * 100;

    // Longest consecutive good streak (in seconds)
    int longestStreak = 0;
    int currentStreak = 0;
    for (final event in events) {
      if (event['status'] == 0) {
        currentStreak++;
        if (currentStreak > longestStreak) longestStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }

    // Worst moment: start of the longest consecutive bad streak
    int longestBadStreak = 0;
    int currentBadStreak = 0;
    int worstMomentIdx = 0;
    for (int i = 0; i < events.length; i++) {
      if (events[i]['status'] == 2) {
        currentBadStreak++;
        if (currentBadStreak > longestBadStreak) {
          longestBadStreak = currentBadStreak;
          worstMomentIdx = i - currentBadStreak + 1;
        }
      } else {
        currentBadStreak = 0;
      }
    }

    DateTime? worstMoment;
    if (longestBadStreak > 0) {
      worstMoment = DateTime.fromMillisecondsSinceEpoch(
        events[worstMomentIdx]['timestamp'] as int,
      );
    }

    final summary = SessionSummary(
      sessionId: sessionId,
      date: DateTime.now(),
      durationSeconds: durationSeconds,
      goodPosturePercent: goodPercent,
      longestStreakSeconds: longestStreak,
      worstMomentTimestamp: worstMoment,
    );

    await _saveSession(summary);
    return summary;
  }

  static Future<void> _saveSession(SessionSummary summary) async {
    final db = await database;
    await db.insert(
      'sessions',
      summary.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── Query methods ───

  static Future<List<SessionSummary>> getAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC');
    return rows.map((r) => SessionSummary.fromMap(r)).toList();
  }

  static Future<SessionSummary?> getLatestSession() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return SessionSummary.fromMap(rows.first);
  }

  /// Get per-second status events for a session (for heatmap chart).
  static Future<List<Map<String, dynamic>>> getSessionEvents(
      String sessionId) async {
    final db = await database;
    return db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }
}
