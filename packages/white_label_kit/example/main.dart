import 'package:flutter/material.dart';
import 'package:white_label_kit/white_label_kit.dart';

void main() {
  // Access the compiled tenant runtime metadata
  final runtime = whiteLabelRuntime;

  runApp(ExampleApp(runtime: runtime));
}

class ExampleApp extends StatelessWidget {
  final WhiteLabelRuntime runtime;

  const ExampleApp({super.key, required this.runtime});

  @override
  Widget build(BuildContext context) {
    // Parse hex primary color from tenant configuration safely
    final primaryColor = Color(
      int.parse(runtime.primaryColor.replaceFirst('#', '0xFF')),
    );

    return MaterialApp(
      title: runtime.name,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(runtime.name),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Active Tenant: ${runtime.id}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text('API Base URL: ${runtime.apiBaseUrl}'),
              const SizedBox(height: 12),
              Text(
                'Push Notifications: ${runtime.featureEnabled("enable_push_notifications") ? "Enabled" : "Disabled"}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
