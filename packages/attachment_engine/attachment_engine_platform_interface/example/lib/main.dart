// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// The example app's root widget.
class MyApp extends StatelessWidget {
  /// Creates the example app.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attachment Engine Platform Interface Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

/// Example home page showing the platform interface contract.
class ExampleHomePage extends StatelessWidget {
  /// Creates the example home page.
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attachment Engine Platform Interface'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'This package defines the pure-Dart platform interface contract '
            'implemented by platform-specific packages (Android, iOS, macOS, Windows, Linux, Web).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
