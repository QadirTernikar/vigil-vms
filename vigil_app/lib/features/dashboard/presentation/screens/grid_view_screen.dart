import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vigil_app/features/dashboard/data/camera_repository.dart';
import 'package:vigil_app/features/dashboard/domain/camera_model.dart';
import 'package:vigil_app/features/dashboard/presentation/widgets/stream_player.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/add_camera_screen.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/camera_settings_screen.dart';
import 'package:vigil_app/features/dashboard/data/snapshot_service.dart';

class GridViewScreen extends ConsumerStatefulWidget {
  const GridViewScreen({super.key});

  @override
  ConsumerState<GridViewScreen> createState() => _GridViewScreenState();
}

class _GridViewScreenState extends ConsumerState<GridViewScreen> {
  final _repository = CameraRepository();
  final _snapshotService = SnapshotService();
  late Future<List<Camera>> _camerasFuture;

  // Map to store GlobalKeys for each camera's StreamPlayer
  final Map<String, GlobalKey<ConsumerState<StreamPlayer>>> _playerKeys = {};

  Timer? _connectivityTimer;
  bool _isOffline = false;

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
      // Simple check: Look for any non-loopback IPv4 interface
      // Or we could try to resolve a known host, but interface check is local and fast
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
      // If listing interfaces fails, assume offline or weird state
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

  Future<void> _takeSnapshot(Camera cam) async {
    try {
      // Get the StreamPlayer widget for this camera
      final playerKey = _playerKeys[cam.id];
      if (playerKey == null || playerKey.currentState == null) {
        throw Exception('Stream player not found');
      }

      debugPrint('📸 Requesting snapshot from StreamPlayer for ${cam.name}');

      // Capture from the renderer - cast to dynamic to access the method
      final state = playerKey.currentState as dynamic;
      final bytes = await state.captureSnapshot() as Uint8List?;

      if (bytes != null) {
        await _snapshotService.uploadSnapshot(cam.id, bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Snapshot saved for ${cam.name}')),
          );
        }
      } else {
        throw Exception('Renderer returned null image');
      }
    } catch (e) {
      debugPrint('❌ Snapshot failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Snapshot Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCameras,
            tooltip: 'Refresh Grid',
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, // 2x2 Grid
                    childAspectRatio: 16 / 9,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: cameras.length,
                  itemBuilder: (context, index) {
                    final cam = cameras[index];
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade800),
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 1. Stream Player
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: StreamPlayer(
                              key: _playerKeys.putIfAbsent(
                                cam.id,
                                () => GlobalKey<ConsumerState<StreamPlayer>>(),
                              ),
                              streamName: cam.streamUrl,
                              host: defaultHost,
                            ),
                          ),

                          // 2. Camera Label Overlay (Top Left)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: _isOffline
                                        ? Colors.red
                                        : Colors.green,
                                    size: 8,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    cam.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 3. Settings Icon (Top Right, Left of Menu)
                          Positioned(
                            top: 8,
                            right: 48,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          CameraSettingsScreen(camera: cam),
                                    ),
                                  );
                                  if (result == true) {
                                    _refreshCameras();
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.settings,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 4. Menu Actions (Top Right)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white70,
                                size: 20,
                              ),
                              onSelected: (value) async {
                                if (value == 'snapshot') {
                                  await _takeSnapshot(cam);
                                } else if (value == 'delete') {
                                  try {
                                    await _repository.deleteCamera(cam.id);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Camera Deleted'),
                                        ),
                                      );
                                    }
                                    _refreshCameras();
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Delete Failed: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'snapshot',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.camera_alt,
                                        color: Colors.black54,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Take Snapshot'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text(
                                        'Delete Camera',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
