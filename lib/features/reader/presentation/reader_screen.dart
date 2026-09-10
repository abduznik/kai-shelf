import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen(
      {super.key, required this.mangaId, required this.chapterId});

  final String mangaId;
  final String chapterId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Reader ($mangaId / $chapterId) — coming in M3'),
      ),
    );
  }
}
