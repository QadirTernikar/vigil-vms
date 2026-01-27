import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class SnapshotGalleryScreen extends StatefulWidget {
  const SnapshotGalleryScreen({super.key});

  @override
  State<SnapshotGalleryScreen> createState() => _SnapshotGalleryScreenState();
}

class _SnapshotGalleryScreenState extends State<SnapshotGalleryScreen> {
  // Gateway URL (Hardcoded for M6 Local Dev)
  static const String _gatewayBase = 'http://127.0.0.1:8090/snapshot';

  bool _isLoading = true;
  Map<String, List<dynamic>> _galleryData = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSnapshots();
  }

  Future<void> _fetchSnapshots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse('$_gatewayBase/list'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawMap = data['cameras'] as Map<String, dynamic>;

        // Cast to correct type
        final Map<String, List<dynamic>> typedMap = {};
        rawMap.forEach((key, value) {
          typedMap[key] = value as List<dynamic>;
        });

        setState(() {
          _galleryData = typedMap;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load list: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSnapshot(String path) async {
    // Optimistic UI update could be tricky with Map structure, so just reload or confirm first.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Evidence?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final uri = Uri.parse('$_gatewayBase?path=$path');
      final response = await http.delete(uri);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('🗑️ Evidence Deleted')));
        _fetchSnapshots(); // Reload
      } else {
        throw Exception('Delete failed: ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showFullScreen(String path, String timestamp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(timestamp), backgroundColor: Colors.black),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                '$_gatewayBase?path=$path',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forensic Snapshots'),
        actions: [
          IconButton(
            onPressed: _fetchSnapshots,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : _buildList(),
    );
  }

  Widget _buildList() {
    if (_galleryData.isEmpty) {
      return const Center(child: Text('No evidence collected yet.'));
    }

    final cameraNames = _galleryData.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _fetchSnapshots,
      child: ListView.builder(
        itemCount: cameraNames.length,
        itemBuilder: (context, index) {
          final camName = cameraNames[index];
          final snapshots = _galleryData[camName]!;

          return ExpansionTile(
            title: Text(
              '$camName (${snapshots.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: true,
            children: [_buildGrid(snapshots)],
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<dynamic> snapshots) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: snapshots.length,
      itemBuilder: (context, index) {
        final snap = snapshots[index];
        final path = snap['path'] as String;
        final timeIso = snap['time'] as String;
        final date = DateTime.parse(
          timeIso,
        ).toLocal(); // Show local time to user
        final timeStr = DateFormat('MM/dd HH:mm:ss').format(date);

        return GestureDetector(
          onTap: () => _showFullScreen(path, timeStr),
          onLongPress: () => _deleteSnapshot(path),
          child: GridTile(
            footer: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(2),
              child: Text(
                timeStr,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
            child: Image.network(
              '$_gatewayBase?path=$path',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[900],
                child: const Icon(Icons.error),
              ),
            ),
          ),
        );
      },
    );
  }
}
