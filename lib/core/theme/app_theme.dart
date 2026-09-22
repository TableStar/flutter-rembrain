import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_theme.g.dart';

@riverpod
ThemeData darkTheme(Ref ref) =>
    ThemeData(useMaterial3: true, brightness: Brightness.dark);

@riverpod
ThemeData lightTheme(Ref ref) =>
    ThemeData(useMaterial3: true, brightness: Brightness.light);
