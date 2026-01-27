import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vigil_app/features/dashboard/data/camera_repository.dart';
import 'package:vigil_app/features/dashboard/domain/camera_model.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/add_camera_screen.dart';
import 'package:vigil_app/features/dashboard/presentation/widgets/camera_tile.dart';
import 'package:vigil_app/features/playback/presentation/screens/playback_screen.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/snapshot_gallery_screen.dart';
import 'package:vigil_app/features/scheduler/presentation/screens/scheduler_screen.dart';

class GridViewScreen extends ConsumerStatefulWidget {
  const GridViewScreen({super.key});

  // ... rest matches
  @override
  ConsumerState<GridViewScreen> createState() => _GridViewScreenState();
}

class _GridViewScreenState extends ConsumerState<GridViewScreen> {
  final _repository = CameraRepository();
  late Future<List<Camera>> _camerasFuture;

  Timer? _connectivityTimer;
  bool _isOffline = false;
  int _gridSize = 2; // Default 2x2, options: 2-7

  @override
  void initState() {
    super.initState();
    _refreshCameras();
    _startConnectivityCheck();
  }

  void _startConnectivityCheck() {
    // Initial check
    _checkStatus();
    // Poll every 5 seconds (more reliable than streams on desktop)
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStatus(),
    );
  }

  Future<void> _checkStatus() async {
    try {
      final interfaces = await NetworkInterface.list();
      final hasNetwork = interfaces.any(
        (i) => i.addresses.any(
          (a) => !a.isLoopback && a.type == InternetAddressType.IPv4,
        ),
      );

      final isOffline = !hasNetwork;

      if (mounted && isOffline != _isOffline) {
        setState(() => _isOffline = isOffline);
        if (!isOffline)
          _refreshCameras(); // Auto-reload when network comes back
      }
    } catch (e) {
      debugPrint('Network Check Error: $e');
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  void _refreshCameras() {
    setState(() {
      _camerasFuture = _repository.getCameras();
    });
  }

  // Temporary helper to add a test camera
  Future<void> _addTestCamera() async {
    try {
      await _repository.addCamera(
        name: 'Test Cam ${DateTime.now().second}',
        streamUrl: 'bunny',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Test Camera Added')));
        _refreshCameras();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine default host
    String defaultHost = '127.0.0.1'; // Default for Windows/Linux
    if (Platform.isAndroid) {
      defaultHost = '192.168.1.8'; // Update this to your PC's IP
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vigil VMS'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SnapshotGalleryScreen(),
                ),
              );
            },
            tooltip: 'Evidence Gallery',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddCameraScreen(),
                ),
              );
              if (result == true) {
                _refreshCameras();
              }
            },
            tooltip: 'Add Camera',
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PlaybackScreen()),
              );
            },
            tooltip: 'Playback & Timeline',
          ),
          IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SchedulerScreen()),
              );
            },
            tooltip: 'Recording Schedules',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCameras,
            tooltip: 'Refresh Grid',
          ),
          // Grid Size Selector
          PopupMenuButton<int>(
            icon: const Icon(Icons.grid_view),
            tooltip: 'Grid Size',
            onSelected: (size) => setState(() => _gridSize = size),
            itemBuilder: (_) => [2, 3, 4, 5, 6, 7]
                .map((n) => PopupMenuItem(value: n, child: Text('${n}x$n')))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Camera>>(
              future: _camerasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final cameras = snapshot.data ?? [];

                if (cameras.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Cameras Configured',
                          style: TextStyle(color: Colors.grey, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap + to add a camera',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _addTestCamera,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Demo Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Responsive Grid Layout
                return GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridSize,
                    childAspectRatio: 16 / 9,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: cameras.length,
                  itemBuilder: (context, index) {
                    final cam = cameras[index];
                    return CameraTile(
                      key: ValueKey(cam.id), // Preserve state
                      camera: cam,
                      host: defaultHost,
                      onRefresh: _refreshCameras,
                      onDelete: (id) async {
                        // Delete Logic
                        try {
                          await _repository.deleteCamera(id);
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Camera Deleted')),
                            );
                          _refreshCameras();
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Delete Failed: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Offline Banner
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Text(
                '⚠ Offline Mode - Caching Active',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
