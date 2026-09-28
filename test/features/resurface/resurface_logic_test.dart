import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/resurface/resurface_logic.dart';

void main() {
  final now = DateTime(2026, 9, 28);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  test('throw on empty or mismatched input', () {
    expect(() => pickWeighted([], [], now, Random(1)), throwsArgumentError);
    expect(
      () => pickWeighted(['a'], [daysAgo(1), daysAgo(2)], now, Random(1)),
      throwsArgumentError,
    );
  });

  test('always returns a member of items', () {
    final items = ['a', 'b', 'c'];
    final picked = {
      for (var i = 0; i < 200; i++)
        pickWeighted(
          items,
          [daysAgo(1), daysAgo(10), daysAgo(100)],
          now,
          Random(i),
        ),
    };
    expect(picked.difference(items.toSet()), isEmpty);
  });

  test('older notes picked more often (fixed clock, seeded rng)', () {
    final items = ['young', 'old'];
    var oldPicks = 0;
    for (var i = 0; i < 1000; i++) {
      final pick = pickWeighted(
        items,
        [daysAgo(1), daysAgo(99)],
        now,
        Random(i),
      );
      if (pick == 'old') oldPicks++;
    }
    expect(oldPicks, greaterThan(900));
  });

  test('single candidate returns it', () {
    expect(pickWeighted(['only'], [daysAgo(5)], now, Random(1)), 'only');
  });
}
