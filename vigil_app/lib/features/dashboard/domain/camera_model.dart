class Camera {
  final String id;
  final String name;
  final String streamUrl; // Main Stream (High Res)
  final String? subStreamUrl; // Sub Stream (Low Res)
  final String status;
  final String? ipAddress;
  final String? username;
  final String? password;
  final String? snapshotUrl;

  Camera({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.subStreamUrl,
    required this.status,
    this.ipAddress,
    this.username,
    this.password,
    this.snapshotUrl,
  });

  factory Camera.fromJson(Map<String, dynamic> json) {
    return Camera(
      id: json['id'] as String,
      name: json['name'] as String,
      streamUrl: json['stream_url'] as String,
      subStreamUrl: json['sub_stream_path'] as String?,
      status: json['status'] as String? ?? 'offline',
      ipAddress: json['ip_address'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      snapshotUrl: json['snapshot_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'stream_url': streamUrl,
      'sub_stream_path': subStreamUrl,
      'status': status,
      'ip_address': ipAddress,
      'username': username,
      'password': password,
      'snapshot_url': snapshotUrl,
    };
  }
}
