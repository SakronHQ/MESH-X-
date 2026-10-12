import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Database? _instance;
  static const String _dbName = 'mesh_x_local.db';
  static const int _dbVersion = 3;

  static Future<Database> get instance async {
    if (_instance != null) return _instance!;
    _instance = await _initDatabase();
    return _instance!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            peer_node_id INTEGER NOT NULL,
            last_message_text TEXT,
            last_message_timestamp INTEGER,
            unread_count INTEGER DEFAULT 0,
            is_pinned INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            packet_id INTEGER NOT NULL,
            conversation_id TEXT NOT NULL,
            sender_node_id INTEGER NOT NULL,
            recipient_node_id INTEGER NOT NULL,
            text_content TEXT NOT NULL,
            delivery_status TEXT NOT NULL,
            is_incoming INTEGER NOT NULL,
            is_encrypted INTEGER DEFAULT 0,
            retry_count INTEGER DEFAULT 0,
            rssi INTEGER,
            snr REAL,
            hop_count INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL,
            delivered_at INTEGER,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE nodes (
            node_id INTEGER PRIMARY KEY,
            alias TEXT,
            hop_distance INTEGER DEFAULT 1,
            last_rssi INTEGER,
            last_snr REAL,
            last_seen_at INTEGER NOT NULL,
            public_key TEXT,
            is_verified INTEGER DEFAULT 0
          );
        ''');

        await db.execute('CREATE INDEX idx_messages_conv ON messages(conversation_id);');
        await db.execute('CREATE INDEX idx_messages_packet_id ON messages(packet_id);');

        // Insert default Broadcast conversation
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.insert('conversations', {
          'id': 'broadcast',
          'title': 'Public Mesh Broadcast',
          'peer_node_id': 0xFFFFFFFF,
          'last_message_text': 'Welcome to MESH-X offline mesh.',
          'last_message_timestamp': now,
          'unread_count': 0,
          'is_pinned': 1,
          'created_at': now,
          'updated_at': now,
        });
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS nodes (
              node_id INTEGER PRIMARY KEY,
              alias TEXT,
              hop_distance INTEGER DEFAULT 1,
              last_rssi INTEGER,
              last_snr REAL,
              last_seen_at INTEGER NOT NULL,
              public_key TEXT,
              is_verified INTEGER DEFAULT 0
            );
          ''');
        }
        if (oldVersion < 3) {
          // Add crypto columns if migrating from version 2
          try {
            await db.execute('ALTER TABLE nodes ADD COLUMN public_key TEXT;');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE nodes ADD COLUMN is_verified INTEGER DEFAULT 0;');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE messages ADD COLUMN is_encrypted INTEGER DEFAULT 0;');
          } catch (_) {}
        }
      },
    );
  }
}
