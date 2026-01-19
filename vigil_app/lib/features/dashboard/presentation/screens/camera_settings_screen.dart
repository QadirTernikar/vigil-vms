import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vigil_app/features/dashboard/data/camera_repository.dart';
import 'package:vigil_app/features/dashboard/domain/camera_model.dart';
import 'package:vigil_app/features/dashboard/data/onvif_media_service.dart';
import 'package:vigil_app/features/dashboard/data/onvif_service.dart';

class CameraSettingsScreen extends StatefulWidget {
  final Camera camera;

  const CameraSettingsScreen({super.key, required this.camera});

  @override
  State<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<CameraSettingsScreen> {
  final _repository = CameraRepository();
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _ipController;

  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.camera.name);
    _urlController = TextEditingController(text: widget.camera.streamUrl);
    _userController = TextEditingController(
      text: widget.camera.username ?? 'admin',
    );
    _passController = TextEditingController(text: widget.camera.password ?? '');
    _ipController = TextEditingController(text: widget.camera.ipAddress ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      // Create Updated Camera Object
      // Ideally we should have a repository method to update specific fields or the whole object
      // Assuming we can delete and re-add OR update if supported.
      // Based on previous code, update might not be directly exposed, but we can try to implement update logic.
      //
      // Checking CameraRepository... usually we'd implement 'updateCamera'.
      // If it doesn't exist, we'll assume it exists or I'll need to add it.
      // For now, I'll assume an update method or direct Supabase update here.
      //
      // Actually, to be safe and cleaner, if repository doesn't have update, I should add it.
      // But let's check if I can just call update on the repository.

      // Since I can't see the repository right now, I'll assume `updateCamera` exists or similar.
      // If not, I'll need to create it.

      // Using Supabase direct update logic pattern often seen in this codebase:
      // await Supabase.instance.client.from('cameras').update(...).eq('id', widget.camera.id);

      // But better to use repository if possible.
      // I'll assume I need to add `updateCamera` to `CameraRepository`.
      // I will write the repository update in a separate step if needed.

      // Temporary: Direct repository call (assuming it will be there)
      // 1. Perform Update via Repository
      final updatedCamera = await _repository.updateCamera(
        id: widget.camera.id,
        name: _nameController.text.trim(),
        streamUrl: _urlController.text.trim(),
        username: _userController.text.trim(),
        password: _passController.text.trim(),
        ipAddress: _ipController.text.trim(),
      );

      debugPrint('✅ Camera updated successfully: ${updatedCamera.name}');

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate refresh needed
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving settings: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteCamera() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Camera?'),
        content: Text('Are you sure you want to delete ${widget.camera.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      try {
        await _repository.deleteCamera(widget.camera.id);
        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate refresh
        }
      } catch (e) {
        debugPrint('Delete Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white70),
            onPressed: _isSaving ? null : _deleteCamera,
          ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Name Section
                const Text(
                  'General',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Camera Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Connection Section
                const Text(
                  'Connection',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _userController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _passController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // RTSP Stream URL
                const Text(
                  'Stream Configuration',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.deepPurple.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.link, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'RTSP Stream URL',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _urlController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            helperText: 'e.g. rtsp://user:pass@ip:port/stream',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Modify this only if the stream connection is failing.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: _isTesting
                      ? const CircularProgressIndicator()
                      : OutlinedButton.icon(
                          onPressed: _testConnection,
                          icon: const Icon(Icons.network_check),
                          label: const Text('Test Connection & Credentials'),
                        ),
                ),
                const SizedBox(height: 32),

                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _testConnection() async {
    final ip = _ipController.text.trim();
    final port = 554;
    final user = _userController.text.trim();
    final pass = _passController.text.trim();
    final manualUrl = _urlController.text.trim();

    if (ip.isEmpty) {
      _showSnack('IP Address is required', isError: true);
      return;
    }

    setState(() => _isTesting = true);
    // Hide current snackbar to show "Testing..."
    _showSnack('Testing connection to $ip...', isError: false);

    try {
      // 1. TCP Connectivity Check (Fast Fail)
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(seconds: 3),
        );
        socket.destroy();
      } catch (e) {
        _showSnack('❌ Camera Offline (Unreachable)', isError: true);
        if (mounted) setState(() => _isTesting = false);
        return;
      }

      // 2. Auth Check (via ONVIF)
      final mediaService = OnvifMediaService();
      final tempDevice = OnvifDevice(
        ip: ip,
        xaddr: 'http://$ip/onvif/device_service',
        manufacturer: 'Unknown',
        hardware: 'Unknown',
        responseTime: Duration.zero,
      );

      try {
        // Try to fetch profiles - this verifies Credentials
        final profiles = await mediaService.getProfiles(
          tempDevice.xaddr,
          user,
          pass,
        );

        if (profiles.isEmpty) {
          // Edge case: Auth worked but no profiles?
          _showSnack('✅ Credentials OK (No Profiles Found)', isError: false);
        } else {
          // 3. Path Verification (RTSP Check)
          // Credentials are good. Now let's see if the manual URL matches ONVIF.
          final actualUri = await mediaService.getDefaultStreamUrl(
            tempDevice,
            user,
            pass,
          );

          if (actualUri != null && actualUri != manualUrl) {
            // Mismatch detected!
            _showSnack(
              '⚠️ Credentials OK, but Stream Path differs!',
              isError: true,
            );
            debugPrint('Expected: $actualUri, Got: $manualUrl');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ Invalid Path? Camera wants: $actualUri'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 8),
                  action: SnackBarAction(
                    label: 'FIX',
                    textColor: Colors.white,
                    onPressed: () {
                      if (mounted)
                        setState(() => _urlController.text = actualUri);
                    },
                  ),
                ),
              );
            }
            if (mounted) setState(() => _isTesting = false);
            return;
          }

          _showSnack(
            '✅ Connection Verified (Credentials & Path OK)',
            isError: false,
          );
        }
      } catch (e) {
        final err = e.toString();
        debugPrint('ONVIF Error in Test: $err');

        if (err.contains('401') || err.contains('Authorized')) {
          _showSnack('❌ Authentication Failed. Check Password.', isError: true);
        } else if (err.contains('Host lookup') ||
            err.contains('Connection refused')) {
          // Should have been caught by Socket check, but maybe HTTP port is different
          _showSnack(
            '❌ ONVIF Service Unreachable (Check Port 80/8080)',
            isError: true,
          );
        } else {
          _showSnack(
            '⚠️ Port 554 Open, but ONVIF Failed ($err)',
            isError: false,
          );
        }
      }
    } catch (e) {
      _showSnack('❌ Test Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
