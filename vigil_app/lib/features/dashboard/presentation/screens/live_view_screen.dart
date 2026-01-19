import 'package:flutter/material.dart';
import 'package:vigil_app/features/dashboard/presentation/widgets/stream_player.dart';
import 'dart:io';

class LiveViewScreen extends StatelessWidget {
  const LiveViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Determine default host based on platform
    String defaultHost = '127.0.0.1';
    if (Platform.isAndroid) {
      defaultHost = '10.0.2.2'; // Emulator localhost
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live View (M1: Single Stream)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Settings placeholder
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    // Main Player Area
                    Container(
                      color: Colors.black,
                      height:
                          constraints.maxHeight *
                          0.6, // Take 60% of screen height
                      child: StreamPlayer(
                        streamName: 'bunny',
                        host: defaultHost,
                      ),
                    ),

                    // Info Area
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.center,
                        child: Text(
                          'Stream "bunny" from Go2RTC\nHost: $defaultHost\n\n'
                          'Troubleshooting:\n'
                          '1. Open browser to http://127.0.0.1:1984\n'
                          '2. Check if "bunny" stream is listed\n'
                          '3. Ensure no firewall blocks port 8555',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
