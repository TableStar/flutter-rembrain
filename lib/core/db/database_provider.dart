import 'database.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDb appDb(Ref ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return db;
}
