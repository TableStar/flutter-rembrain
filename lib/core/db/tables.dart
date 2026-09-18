import 'package:drift/drift.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text()();
  TextColumn get title => text().nullable()();
  TextColumn get aiTitle => text().nullable()(); // reserved for AI phase
  TextColumn get aiContent => text().nullable()(); // reserved for AI phase
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get resurfaceCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastResurfacedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class NoteTags extends Table {
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
