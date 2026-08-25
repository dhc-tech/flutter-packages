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
      title: 'attachment_engine_linux example',
      home: Scaffold(
        appBar: AppBar(title: const Text('attachment_engine_linux example')),
        body: const Center(child: Text('attachment_engine_linux example')),
      ),
    );
  }
}
