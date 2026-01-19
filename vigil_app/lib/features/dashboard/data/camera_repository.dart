import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vigil_app/features/dashboard/domain/camera_model.dart';

class CameraRepository {
  final _client = Supabase.instance.client;
  final _storage = const FlutterSecureStorage();
  static const _cacheKey = 'cameras_cache';

  // Fetch cameras (Supabase -> Cache Fallback)
  Future<List<Camera>> getCameras() async {
    try {
      final response = await _client
          .from('cameras')
          .select()
          .order('created_at', ascending: true);

      final cameras = (response as List)
          .map((json) => Camera.fromJson(json))
          .toList();

      // Update Cache (Fire and Forget)
      _cacheCameras(cameras);

      return cameras;
    } catch (e) {
      debugPrint('Supabase Error (Offline?): $e');
      debugPrint('Falling back to local cache...');
      return await _getCachedCameras();
    }
  }

  Future<void> _cacheCameras(List<Camera> cameras) async {
    try {
      final jsonList = cameras.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await _storage.write(key: _cacheKey, value: jsonString);
    } catch (e) {
      debugPrint('Cache Write Error: $e');
    }
  }

  Future<List<Camera>> _getCachedCameras() async {
    try {
      final jsonString = await _storage.read(key: _cacheKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        return jsonList.map((json) => Camera.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Cache Read Error: $e');
    }
    return [];
  }

  // Add a new camera (VMS Style)
  Future<void> addCamera({
    required String name,
    required String streamUrl,
    String? ipAddress,
    int? port,
    String? username,
    String? password,
    String? subStreamPath,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('cameras').insert({
      'user_id': userId,
      'name': name,
      'stream_url': streamUrl, // Computed full URL
      'status': 'online',
      'ip_address': ipAddress,
      'port': port,
      'username': username,
      'password': password,
      'sub_stream_path': subStreamPath,
    });
  }

  // Update existing camera settings
  // Update existing camera settings
  // Update existing camera settings
  Future<Camera> updateCamera({
    required String id,
    required String name,
    required String streamUrl,
    String? ipAddress,
    String? username,
    String? password,
  }) async {
    // 0. DIAGNOSTIC: Check if camera is visible/exists before update
    // This helps confirm if RLS prevents visibility or just update
    final check = await _client
        .from('cameras')
        .select('id, user_id')
        .eq('id', id)
        .maybeSingle();

    if (check == null) {
      debugPrint("❌ updateCamera: Camera $id not found in DB (RLS hidden?)");
      throw Exception("Camera not found on server. Cannot update.");
    }
    debugPrint("✅ updateCamera: Camera found. Owner: ${check['user_id']}");

    // 1. Attempt Update
    // Using maybeSingle() to avoid PGRST116 crash if 0 rows updated
    final response = await _client
        .from('cameras')
        .update({
          'name': name,
          'stream_url': streamUrl,
          'ip_address': ipAddress,
          'username': username,
          'password': password,
        })
        .eq('id', id)
        .select()
        .maybeSingle(); // <--- SAFE GUARD

    if (response == null) {
      debugPrint(
        "❌ updateCamera: Update command returned 0 rows! RLS 'UPDATE' policy likely missing.",
      );
      throw Exception(
        "Database update failed. Check 'UPDATE' policy in Supabase for 'cameras' table.",
      );
    }

    final updatedCamera = Camera.fromJson(response);

    // 2. Update Cache Optimistically (Consistency)
    await _updateCacheItem(updatedCamera);

    return updatedCamera;
  }

  Future<void> _updateCacheItem(Camera camera) async {
    try {
      final currentList = await _getCachedCameras();
      // Remove old version if exists, then add new
      final newList = currentList.where((c) => c.id != camera.id).toList();
      newList.add(camera);
      // Sort to maintain order if needed (optional)
      // newList.sort((a,b) => ...);
      await _cacheCameras(newList);
    } catch (e) {
      debugPrint("Cache Item Update Error: $e");
    }
  }

  // Delete camera with Full Diagnostics
  Future<void> deleteCamera(String id) async {
    final currentUserId = _client.auth.currentUser?.id;
    debugPrint("--- DELETE DIAGNOSTICS ---");
    debugPrint("Camera ID to delete: $id");
    debugPrint("Current User ID: $currentUserId");

    // Step 1: Check if camera exists on server and who owns it
    final existing = await _client
        .from('cameras')
        .select('id, user_id, name')
        .eq('id', id)
        .maybeSingle();

    debugPrint("Camera on Server: $existing");

    if (existing == null) {
      // Camera is NOT on server - it's a ghost in cache only
      debugPrint("Camera NOT found on server. Removing from local cache only.");
      await _removeFromCache(id);
      return;
    }

    // Step 2: Verify ownership before delete
    if (existing['user_id'] != currentUserId) {
      debugPrint(
        "OWNERSHIP MISMATCH! Camera user_id: ${existing['user_id']}, Your ID: $currentUserId",
      );
      throw Exception("Cannot delete: You don't own this camera.");
    }

    // Step 3: Perform actual delete
    await _client.from('cameras').delete().eq('id', id);

    // Step 4: Verify camera is actually gone
    final stillExists = await _client
        .from('cameras')
        .select('id')
        .eq('id', id)
        .maybeSingle();

    if (stillExists != null) {
      debugPrint("DELETE FAILED! Camera still exists after delete command.");
      throw Exception("Delete command failed. Check RLS policies in Supabase.");
    }

    debugPrint("Camera successfully deleted from server.");
    await _removeFromCache(id);
    debugPrint("--- DELETE COMPLETE ---");
  }

  Future<void> _removeFromCache(String id) async {
    try {
      final currentList = await _getCachedCameras();
      final newList = currentList.where((c) => c.id != id).toList();
      await _cacheCameras(newList);
    } catch (e) {
      debugPrint("Cache Update Error: $e");
    }
  }
}
