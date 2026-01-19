// ============================================================================
// RTSP URL Templates for Known Brands
// ============================================================================

class RtspTemplate {
  final String label;
  final String path;
  final String description;

  const RtspTemplate({
    required this.label,
    required this.path,
    required this.description,
  });
}

class RtspTemplateService {
  static List<RtspTemplate> getTemplates(String manufacturer) {
    final manufacturerLower = manufacturer.toLowerCase();

    if (manufacturerLower.contains('hikvision')) {
      return [
        const RtspTemplate(
          label: 'Main Stream',
          path: '/Streaming/Channels/101',
          description: 'High quality stream',
        ),
        const RtspTemplate(
          label: 'Sub Stream',
          path: '/Streaming/Channels/102',
          description: 'Low bandwidth',
        ),
      ];
    } else if (manufacturerLower.contains('dahua') ||
        manufacturerLower.contains('cp plus') ||
        manufacturerLower.contains('cpplus')) {
      return [
        const RtspTemplate(
          label: 'Main Stream',
          path: '/cam/realmonitor?channel=1&subtype=0',
          description: 'High quality',
        ),
        const RtspTemplate(
          label: 'Sub Stream',
          path: '/cam/realmonitor?channel=1&subtype=1',
          description: 'Low bandwidth',
        ),
      ];
    } else if (manufacturerLower.contains('uniview')) {
      return [
        const RtspTemplate(
          label: 'Main Stream',
          path: '/media/video1',
          description: 'High quality',
        ),
      ];
    }

    // Generic fallback if manufacturer is unknown or no specific templates
    return [
      const RtspTemplate(
        label: 'Generic Stream 1',
        path: '/stream1',
        description: 'Common generic path',
      ),
      const RtspTemplate(
        label: 'Generic Live',
        path: '/live',
        description: 'Common generic path',
      ),
    ];
  }
}
