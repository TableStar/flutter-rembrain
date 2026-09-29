import 'package:flutter/material.dart';
import 'package:rembrain/features/notes/ui/quick_dump_box.dart';
import 'package:rembrain/features/resurface/ui/resurface_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [ResurfaceCard(), QuickDumpBox()]),
        ),
      ),
    );
  }
}
