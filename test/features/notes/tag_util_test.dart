import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/notes/data/tag_util.dart';

void main() {
  test('extracts tags, lowercased, deduped', () {
    expect(parseTags('hello #World and #flutter #World'), {'world', 'flutter'});
  });

  test('ignores bare # and trailing #', () {
    expect(parseTags('# and stuff #'), isEmpty);
  });

  test('allows underscore and digits, caps at 32 chars', () {
    expect(parseTags('#snake_case_1'), {'snake_case_1'});
    expect(parseTags('#${'a' * 33}'), isEmpty);
    expect(parseTags('#${'a' * 32}'), {'a' * 32});
  });

  test('no tags when none present', () {
    expect(parseTags('plain note'), isEmpty);
  });
}
