import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

// ============================================================================
// ONVIF Discovery State Machine
// ============================================================================

enum ONVIFDiscoveryState {
  idle,
  checkingNetwork,
  scanning,
  partial,
  complete,
  networkError,
  firewallBlocked,
  timeout,
  cancelled,
}

// ============================================================================
// ONVIF Device Model
// ============================================================================

class OnvifDevice {
  final String ip;
  final String xaddr;
  final String hardware;
  final String manufacturer;
  final Duration responseTime;

  OnvifDevice({
    required this.ip,
    required this.xaddr,
    required this.hardware,
    required this.manufacturer,
    required this.responseTime,
  });

  @override
  String toString() => '$manufacturer $hardware ($ip)';
}

// ============================================================================
// ONVIF Diagnostics Data
// ============================================================================

class ONVIFDiagnostics {
  int udpPacketsSent = 0;
  int udpResponsesReceived = 0;
  String ipRangeScanned = '';
  List<int> scanPorts = [3702];
  Duration scanDuration = Duration.zero;
  List<String> failureReasons = [];
  DateTime? scanStartTime;

  void addFailureReason(String reason) {
    if (!failureReasons.contains(reason)) {
      failureReasons.add(reason);
    }
  }

  String get summary {
    return '''
📊 ONVIF Scan Diagnostics

UDP Packets Sent: $udpPacketsSent
Responses Received: $udpResponsesReceived
Scan Duration: ${scanDuration.inMilliseconds}ms
Ports Scanned: ${scanPorts.join(', ')}
${failureReasons.isNotEmpty ? '\nFailure Reasons:\n${failureReasons.map((r) => '• $r').join('\n')}' : ''}
''';
  }
}

// ============================================================================
// ONVIF Discovery Progress Event
// ============================================================================

class ONVIFDiscoveryProgress {
  final ONVIFDiscoveryState state;
  final List<OnvifDevice> devicesFound;
  final String? message;
  final ONVIFDiagnostics? diagnostics;

  ONVIFDiscoveryProgress({
    required this.state,
    this.devicesFound = const [],
    this.message,
    this.diagnostics,
  });
}

// ============================================================================
// ONVIF Discovery Service with State Machine
// ============================================================================

class OnvifDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _port = 3702;

  final _stateController = StreamController<ONVIFDiscoveryProgress>.broadcast();
  final _diagnostics = ONVIFDiagnostics();

  Stream<ONVIFDiscoveryProgress> get discoveryStream => _stateController.stream;
  ONVIFDiagnostics get diagnostics => _diagnostics;

  bool _isCancelled = false;

  // =========================================================================
  // Network Connectivity Pre-Check
  // =========================================================================

  Future<bool> _checkNetworkConnectivity() async {
    try {
      _emitState(
        ONVIFDiscoveryState.checkingNetwork,
        message: 'Checking network...',
      );

      // Get network interfaces directly (more reliable than connectivity_plus on desktop)
      final interfaces = await NetworkInterface.list();

      // Look for active IPv4 interface (non-loopback)
      final validInterfaces = interfaces
          .where(
            (interface) => interface.addresses.any(
              (addr) =>
                  addr.type == InternetAddressType.IPv4 &&
                  !addr.isLoopback &&
                  addr.address != '0.0.0.0',
            ),
          )
          .toList();

      if (validInterfaces.isEmpty) {
        _diagnostics.addFailureReason('No valid IPv4 network interface');
        debugPrint('❌ ONVIF: No valid network interface found');
        return false;
      }

      // Get local IP for diagnostics
      final localAddr = validInterfaces
          .expand((i) => i.addresses)
          .firstWhere(
            (addr) => addr.type == InternetAddressType.IPv4 && !addr.isLoopback,
          );

      _diagnostics.ipRangeScanned = localAddr.address;
      debugPrint('✅ ONVIF: Network OK - Local IP: ${localAddr.address}');

      return true;
    } catch (e) {
      _diagnostics.addFailureReason('Network check failed: $e');
      debugPrint('❌ ONVIF: Network check error: $e');
      return false;
    }
  }

  // =========================================================================
  // Main Discovery Method with State Machine
  // =========================================================================

  Future<List<OnvifDevice>> discover({
    Duration timeout = const Duration(seconds: 10),
    bool enableDiagnostics = false,
  }) async {
    _isCancelled = false;
    _diagnostics.scanStartTime = DateTime.now();
    final devices = <OnvifDevice>[];
    RawDatagramSocket? socket;

    try {
      // Step 1: Network Pre-Check
      if (!await _checkNetworkConnectivity()) {
        _emitState(
          ONVIFDiscoveryState.networkError,
          message: 'Network unreachable',
          devices: devices,
        );
        return devices;
      }

      if (_isCancelled) {
        _emitState(ONVIFDiscoveryState.cancelled, devices: devices);
        return devices;
      }

      // Step 2: Begin Scanning
      _emitState(
        ONVIFDiscoveryState.scanning,
        message: 'Scanning for devices...',
      );

      // Bind UDP Socket on ONVIF discovery port
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: true,
      );

      // CRITICAL: Join multicast group to receive responses
      socket.joinMulticast(InternetAddress(_multicastAddress));
      socket.broadcastEnabled = true;

      if (enableDiagnostics) {
        debugPrint('📡 ONVIF: Socket bound to port $_port');
        debugPrint('📡 ONVIF: Joined multicast group $_multicastAddress');
      }

      // Send Probe
      final uuid = DateTime.now().millisecondsSinceEpoch.toString();
      final probeData = utf8.encode(_buildProbe(uuid));
      socket.send(probeData, InternetAddress(_multicastAddress), _port);

      _diagnostics.udpPacketsSent++;
      if (enableDiagnostics) {
        debugPrint('📡 ONVIF: Sent probe to $_multicastAddress:$_port');
      }

      // Listen for responses
      final completer = Completer<List<OnvifDevice>>();
      final scanStart = DateTime.now();

      socket.listen((RawSocketEvent event) {
        if (_isCancelled) return;

        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            _diagnostics.udpResponsesReceived++;
            final response = utf8.decode(datagram.data);
            final responseTime = DateTime.now().difference(scanStart);

            try {
              final device = _parseResponse(
                response,
                datagram.address.address,
                responseTime,
              );
              if (device != null) {
                // Avoid duplicates
                if (!devices.any((d) => d.xaddr == device.xaddr)) {
                  devices.add(device);

                  if (enableDiagnostics) {
                    debugPrint(
                      '✅ ONVIF: Found ${device.manufacturer} ${device.hardware} '
                      'at ${device.ip} (${responseTime.inMilliseconds}ms)',
                    );
                  }

                  // Emit progress update
                  _emitState(
                    ONVIFDiscoveryState.scanning,
                    message: 'Found ${devices.length} device(s)...',
                    devices: List.from(devices),
                  );
                }
              }
            } catch (e) {
              if (enableDiagnostics) {
                debugPrint('⚠️ ONVIF: Failed to parse response: $e');
              }
            }
          }
        }
      });

      // Timeout Handler
      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          _diagnostics.scanDuration = DateTime.now().difference(
            _diagnostics.scanStartTime!,
          );

          if (_isCancelled) {
            _emitState(ONVIFDiscoveryState.cancelled, devices: devices);
          } else if (devices.isEmpty &&
              _diagnostics.udpResponsesReceived == 0) {
            // No responses at all - likely firewall blocked
            _diagnostics.addFailureReason('No responses received (firewall?)');
            _emitState(
              ONVIFDiscoveryState.firewallBlocked,
              message: 'No devices responded',
              devices: devices,
            );
          } else if (devices.isNotEmpty) {
            // Found some devices
            _emitState(
              ONVIFDiscoveryState.complete,
              message: 'Found ${devices.length} device(s)',
              devices: devices,
            );
          } else {
            // Responses received but no valid devices
            _emitState(
              ONVIFDiscoveryState.complete,
              message: 'No ONVIF devices found',
              devices: devices,
            );
          }

          completer.complete(devices);
        }
      });

      return await completer.future;
    } catch (e) {
      _diagnostics.addFailureReason('Discovery error: $e');
      _diagnostics.scanDuration = DateTime.now().difference(
        _diagnostics.scanStartTime!,
      );
      debugPrint('❌ ONVIF Discovery Error: $e');

      _emitState(
        ONVIFDiscoveryState.networkError,
        message: 'Discovery failed',
        devices: devices,
      );

      return devices;
    } finally {
      // Clean up socket
      Future.delayed(timeout, () {
        socket?.close();
      });
    }
  }

  // =========================================================================
  // Cancellation Support
  // =========================================================================

  void cancel() {
    _isCancelled = true;
    debugPrint('🛑 ONVIF: Scan cancelled by user');
  }

  // =========================================================================
  // State Emission Helper
  // =========================================================================

  void _emitState(
    ONVIFDiscoveryState state, {
    String? message,
    List<OnvifDevice> devices = const [],
  }) {
    _stateController.add(
      ONVIFDiscoveryProgress(
        state: state,
        devicesFound: devices,
        message: message,
        diagnostics: _diagnostics,
      ),
    );
  }

  // =========================================================================
  // WS-Discovery Probe Message Builder
  // =========================================================================

  String _buildProbe(String uuid) {
    return '''
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" 
            xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" 
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" 
            xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <e:Header>
    <w:MessageID>uuid:$uuid</w:MessageID>
    <w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action a:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
  </e:Header>
  <e:Body>
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>''';
  }

  // =========================================================================
  // XML Response Parser (Naive but functional)
  // =========================================================================

  OnvifDevice? _parseResponse(
    String xml,
    String senderIp,
    Duration responseTime,
  ) {
    if (!xml.contains('ProbeMatches')) return null;

    final xaddr = _extractTag(xml, 'XAddrs');
    final scopes = _extractTag(xml, 'Scopes');

    String manufacturer = 'Unknown';
    String hardware = 'Camera';

    if (scopes != null) {
      final parts = scopes.split(' ');
      for (final p in parts) {
        if (p.contains('onvif.org/name/')) {
          manufacturer = Uri.decodeComponent(p.split('/').last);
        }
        if (p.contains('onvif.org/hardware/')) {
          hardware = Uri.decodeComponent(p.split('/').last);
        }
      }
    }

    if (xaddr != null) {
      return OnvifDevice(
        ip: senderIp,
        xaddr: xaddr,
        hardware: hardware,
        manufacturer: manufacturer,
        responseTime: responseTime,
      );
    }
    return null;
  }

  String? _extractTag(String xml, String tag) {
    final regExp = RegExp(
      '<[a-zA-Z0-9:]*$tag[^>]*>(.*?)</[a-zA-Z0-9:]*$tag>',
      dotAll: true,
    );
    final match = regExp.firstMatch(xml);
    return match?.group(1)?.trim();
  }

  // =========================================================================
  // Cleanup
  // =========================================================================

  void dispose() {
    _stateController.close();
  }
}
