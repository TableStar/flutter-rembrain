import 'package:flutter/material.dart';
import 'package:rembrain/features/notes/ui/quick_dump_box.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: Column(children: [QuickDumpBox()])),
    );
  }
}
