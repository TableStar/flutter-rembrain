import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final darkThemeProvider = Provider<ThemeData>(
  (ref) => ThemeData(useMaterial3: true, brightness: Brightness.dark),
);

final lightThemeProvider = Provider<ThemeData>(
  (ref) => ThemeData(useMaterial3: true, brightness: Brightness.light),
);
