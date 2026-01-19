import 'package:flutter/material.dart';
import 'package:vigil_app/features/dashboard/data/camera_repository.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/onvif_scanner_screen.dart';

class AddCameraScreen extends StatefulWidget {
  const AddCameraScreen({super.key});

  @override
  State<AddCameraScreen> createState() => _AddCameraScreenState();
}

class _AddCameraScreenState extends State<AddCameraScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = CameraRepository();
  bool _isLoading = false;

  // Controllers
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '554');
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _mainPathController = TextEditingController(text: '/stream1');
  final _subPathController = TextEditingController(text: '/stream2');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // 1. Construct the Full RTSP URL for the Player
      // Format: rtsp://user:pass@ip:port/path
      final user = _userController.text.trim();
      final pass = _passController.text.trim();
      final ip = _ipController.text.trim();
      final port = _portController.text.trim();
      final path = _mainPathController.text.trim();

      String fullUrl;
      if (user.isNotEmpty && pass.isNotEmpty) {
        fullUrl = 'rtsp://$user:$pass@$ip:$port$path';
      } else {
        fullUrl = 'rtsp://$ip:$port$path';
      }

      // 2. Save to DB
      await _repository.addCamera(
        name: _nameController.text.trim(),
        streamUrl: fullUrl,
        ipAddress: ip,
        port: int.parse(port),
        username: user,
        password: pass,
        subStreamPath: _subPathController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera Added Successfully')),
        );
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Camera (Manual)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scanner Entry Point
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const OnvifScannerScreen(),
                      ),
                    );
                    if (mounted) Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.radar),
                  label: const Text('Scan Local Network (ONVIF)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 24),

              const Text(
                'Manual Device Details',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Camera Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        border: OutlineInputBorder(),
                        hintText: '192.168.1.X',
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Credentials (Optional)',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _userController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
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
              const SizedBox(height: 24),
              const Text(
                'Stream Paths',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mainPathController,
                decoration: const InputDecoration(
                  labelText: 'Main Stream Path',
                  border: OutlineInputBorder(),
                  hintText: '/stream1',
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subPathController,
                decoration: const InputDecoration(
                  labelText: 'Sub Stream Path (Optional)',
                  border: OutlineInputBorder(),
                  hintText: '/stream2',
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Add Camera',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
