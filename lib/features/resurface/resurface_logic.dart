import 'dart:math';

T pickWeighted<T>(
  List<T> items,
  List<DateTime> createdAt,
  DateTime now,
  Random rng,
) {
  if (items.isEmpty || items.length != createdAt.length) {
    throw ArgumentError(
      'items and createdAt must be non-empty and same length',
    );
  }
  final weights = createdAt
      .map((c) => now.difference(c).inDays + 1)
      .map((w) => w < 1 ? 1 : w)
      .toList();
  final total = weights.reduce((a, b) => a + b);
  var roll = rng.nextInt(total);
  for (var i = 0; i < items.length; i++) {
    roll -= weights[i];
    if (roll < 0) return items[i];
  }
  return items.last;
}
