import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vigil_app/features/dashboard/data/camera_repository.dart';
import 'package:vigil_app/features/dashboard/data/onvif_service.dart';

class OnvifScannerScreen extends StatefulWidget {
  const OnvifScannerScreen({super.key});

  @override
  State<OnvifScannerScreen> createState() => _OnvifScannerScreenState();
}

class _OnvifScannerScreenState extends State<OnvifScannerScreen> {
  final _onvifService = OnvifDiscoveryService();
  final _repository = CameraRepository();

  List<OnvifDevice> _devices = [];
  ONVIFDiscoveryState _state = ONVIFDiscoveryState.idle;
  String? _statusMessage;
  ONVIFDiagnostics? _diagnostics;
  bool _showDiagnostics = false;
  int _titleTapCount = 0;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _onvifService.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Scan Control
  // ===========================================================================

  Future<void> _startScan() async {
    setState(() {
      _state = ONVIFDiscoveryState.scanning;
      _devices.clear();
      _statusMessage = null;
    });

    // Listen to discovery stream
    _onvifService.discoveryStream.listen((progress) {
      if (mounted) {
        setState(() {
          _state = progress.state;
          _devices = progress.devicesFound;
          _statusMessage = progress.message;
          _diagnostics = progress.diagnostics;
        });
      }
    });

    // Start discovery
    final results = await _onvifService.discover(
      timeout: const Duration(seconds: 10),
      enableDiagnostics: _showDiagnostics,
    );

    if (mounted) {
      setState(() {
        _devices = results;
      });
    }
  }

  void _cancelScan() {
    _onvifService.cancel();
    setState(() {
      _statusMessage = 'Scan cancelled';
    });
  }

  // ===========================================================================
  // Add Device
  // ===========================================================================

  Future<void> _addDevice(OnvifDevice device) async {
    final userController = TextEditingController(text: 'admin');
    final passController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connect to ${device.manufacturer}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('IP: ${device.ip}'),
            const SizedBox(height: 16),
            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final user = userController.text;
              final pass = passController.text;
              final streamUrl = 'rtsp://$user:$pass@${device.ip}:554/stream1';

              await _repository.addCamera(
                name: '${device.manufacturer} Cam',
                streamUrl: streamUrl,
                ipAddress: device.ip,
                username: user,
                password: pass,
                port: 554,
              );

              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Camera Added!')));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Diagnostics Toggle (Triple-tap)
  // ===========================================================================

  void _onTitleTap() {
    _titleTapCount++;
    if (_titleTapCount >= 3) {
      setState(() {
        _showDiagnostics = !_showDiagnostics;
        _titleTapCount = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _showDiagnostics
                ? 'Diagnostic mode enabled'
                : 'Diagnostic mode disabled',
          ),
        ),
      );
    }
    Future.delayed(const Duration(seconds: 2), () {
      _titleTapCount = 0;
    });
  }

  void _showDiagnosticsDialog() {
    if (_diagnostics == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 ONVIF Diagnostics'),
        content: SingleChildScrollView(
          child: SelectableText(_diagnostics!.summary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _diagnostics!.summary));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Diagnostics copied to clipboard'),
                ),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // UI State Builders
  // ===========================================================================

  Widget _buildStateUI() {
    switch (_state) {
      case ONVIFDiscoveryState.idle:
        return _buildIdleState();

      case ONVIFDiscoveryState.checkingNetwork:
        return _buildCheckingNetworkState();

      case ONVIFDiscoveryState.scanning:
        return _buildScanningState();

      case ONVIFDiscoveryState.complete:
        return _devices.isEmpty ? _buildNoDevicesFound() : _buildDeviceList();

      case ONVIFDiscoveryState.partial:
        return _buildPartialResults();

      case ONVIFDiscoveryState.networkError:
        return _buildNetworkError();

      case ONVIFDiscoveryState.firewallBlocked:
        return _buildFirewallBlocked();

      case ONVIFDiscoveryState.timeout:
        return _buildTimeout();

      case ONVIFDiscoveryState.cancelled:
        return _buildCancelled();
    }
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radar, size: 80, color: Colors.deepPurple),
          const SizedBox(height: 24),
          const Text(
            'ONVIF Camera Discovery',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Scan your network for ONVIF cameras'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.search),
            label: const Text('Start Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckingNetworkState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_statusMessage ?? 'Checking network connectivity...'),
        ],
      ),
    );
  }

  Widget _buildScanningState() {
    return Column(
      children: [
        // Progress Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.deepPurple.shade50,
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scanning for devices...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _statusMessage ?? 'Found ${_devices.length} device(s)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: _cancelScan, child: const Text('Cancel')),
            ],
          ),
        ),

        // Device List (real-time updates)
        Expanded(
          child: _devices.isEmpty
              ? const Center(child: Text('Waiting for responses...'))
              : _buildDeviceList(),
        ),
      ],
    );
  }

  Widget _buildPartialResults() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.orange.shade50,
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan Incomplete',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Showing ${_devices.length} device(s) found'),
                    const SizedBox(height: 4),
                    const Text(
                      'Some devices may not have responded',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildDeviceList()),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Scan'),
          ),
        ),
      ],
    );
  }

  Widget _buildNoDevicesFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radar, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No ONVIF Cameras Found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'No ONVIF devices responded on your network',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add Camera Manually'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Network Unreachable',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Please check your Wi-Fi connection\nand try again',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildFirewallBlocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'ONVIF Discovery Blocked',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'No devices responded. This is usually caused by:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Firewall blocking UDP port 3702'),
                Text('• Cameras on different subnet'),
                Text('• ONVIF not enabled on cameras'),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'You can still add cameras manually',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Add Manually'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeout() {
    return _buildPartialResults();
  }

  Widget _buildCancelled() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.stop_circle, color: Colors.grey),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan Stopped',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Showing ${_devices.length} device(s) found'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _devices.isEmpty
              ? const Center(
                  child: Text('No devices found before cancellation'),
                )
              : _buildDeviceList(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh),
            label: const Text('Start New Scan'),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return ListTile(
          leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
          title: Text(
            device.manufacturer.isEmpty
                ? 'Unknown Camera'
                : device.manufacturer,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${device.hardware} (${device.ip})'),
              if (_showDiagnostics)
                Text(
                  'Response: ${device.responseTime.inMilliseconds}ms',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
          trailing: ElevatedButton(
            onPressed: () => _addDevice(device),
            child: const Text('Add'),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // Main Build
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          child: const Text('ONVIF Discovery'),
        ),
        actions: [
          if (_showDiagnostics && _diagnostics != null)
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: _showDiagnosticsDialog,
              tooltip: 'Show Diagnostics',
            ),
          if (_state == ONVIFDiscoveryState.complete ||
              _state == ONVIFDiscoveryState.partial ||
              _state == ONVIFDiscoveryState.cancelled)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Rescan',
            ),
        ],
      ),
      body: _buildStateUI(),
    );
  }
}
