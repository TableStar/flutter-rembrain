import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/core/theme/app_theme.dart';

class RembrainApp extends ConsumerWidget {
  const RembrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Rembrain',
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
