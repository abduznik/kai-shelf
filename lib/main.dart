import 'package:flutter/material.dart';

void main() {
  runApp(const KaiShelfApp());
}

class KaiShelfApp extends StatelessWidget {
  const KaiShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kai-Shelf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: Center(
          child: Text('Kai-Shelf — Coming Soon'),
        ),
      ),
    );
  }
}
