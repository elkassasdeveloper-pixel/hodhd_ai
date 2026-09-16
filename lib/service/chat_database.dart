import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:hodhd_ai/dash_chat.dart';

class ChatDatabase {
  static final ChatDatabase _instance = ChatDatabase._internal();
  factory ChatDatabase() => _instance;
  ChatDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'chat_history.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  /// Insert or update a message
  Future<void> saveMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'data': jsonEncode(message.toJson()),
        'createdAt': message.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load all messages, ordered oldest to newest
  Future<List<ChatMessage>> loadMessages() async {
    final db = await database;
    final rows = await db.query('messages', orderBy: 'createdAt ASC');

    return rows.map((row) {
      final json = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      return ChatMessage.fromJson(json);
    }).toList();
  }

  /// Delete a single message
  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  /// Clear all chat history
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
  }
}