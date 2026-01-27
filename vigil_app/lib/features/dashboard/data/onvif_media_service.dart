import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:vigil_app/features/dashboard/data/onvif_service.dart';

// ============================================================================
// ONVIF Error Classification (Sprint 1)
// ============================================================================

/// Base class for all ONVIF exceptions with error classification
abstract class OnvifException implements Exception {
  final String message;
  final String? details;

  const OnvifException(this.message, [this.details]);

  @override
  String toString() => details != null ? '$message: $details' : message;
}

/// Authentication failed - wrong username/password
class OnvifAuthenticationException extends OnvifException {
  const OnvifAuthenticationException([String? details])
    : super('Authentication Failed', details);
}

/// Authorization failed - user doesn't have permission
class OnvifAuthorizationException extends OnvifException {
  const OnvifAuthorizationException([String? details])
    : super('Authorization Denied', details);
}

/// Service error - camera returned SOAP fault
class OnvifServiceException extends OnvifException {
  final String? faultCode;
  final String? faultReason;

  const OnvifServiceException(
    String message, {
    this.faultCode,
    this.faultReason,
  }) : super(message, faultReason);
}

/// Network timeout
class OnvifTimeoutException extends OnvifException {
  const OnvifTimeoutException([String? details])
    : super('Connection Timed Out', details);
}

/// Network unreachable
class OnvifNetworkException extends OnvifException {
  const OnvifNetworkException([String? details])
    : super('Camera Unreachable', details);
}

// ============================================================================
// ONVIF Models
// ============================================================================

class OnvifProfile {
  final String token;
  final String name;
  final String encoding;
  final int width;
  final int height;

  OnvifProfile({
    required this.token,
    required this.name,
    required this.encoding,
    required this.width,
    required this.height,
  });
}

/// Result of authentication test
class OnvifAuthResult {
  final bool success;
  final String message;
  final List<OnvifProfile>? profiles;
  final OnvifException? error;

  const OnvifAuthResult({
    required this.success,
    required this.message,
    this.profiles,
    this.error,
  });

  factory OnvifAuthResult.authenticated(List<OnvifProfile> profiles) {
    return OnvifAuthResult(
      success: true,
      message: 'Authentication Verified',
      profiles: profiles,
    );
  }

  factory OnvifAuthResult.failed(OnvifException error) {
    return OnvifAuthResult(
      success: false,
      message: error.message,
      error: error,
    );
  }
}

// ============================================================================
// ONVIF Media Service with WS-Security PasswordDigest (Sprint 1)
// ============================================================================

class OnvifMediaService {
  static const Duration _requestTimeout = Duration(seconds: 10);

  /// Test authentication and return result with classification
  Future<OnvifAuthResult> testAuthentication(
    String serviceUrl,
    String username,
    String password,
  ) async {
    try {
      final profiles = await getProfiles(serviceUrl, username, password);

      if (profiles.isEmpty) {
        // Empty profiles is a valid but notable result
        return OnvifAuthResult(
          success: true,
          message: 'Authenticated (No Profiles)',
          profiles: profiles,
        );
      }

      return OnvifAuthResult.authenticated(profiles);
    } on OnvifException catch (e) {
      // Already classified exception
      return OnvifAuthResult.failed(e);
    } catch (e) {
      // Catch ANY other exceptions and classify them
      debugPrint('❌ testAuthentication: Unexpected error: $e');
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('timeout')) {
        return OnvifAuthResult.failed(const OnvifTimeoutException());
      } else if (errorStr.contains('host lookup') ||
          errorStr.contains('connection refused') ||
          errorStr.contains('socket')) {
        return OnvifAuthResult.failed(OnvifNetworkException(e.toString()));
      } else {
        return OnvifAuthResult.failed(
          OnvifServiceException('Unexpected Error', faultReason: e.toString()),
        );
      }
    }
  }

  Future<String?> getDefaultStreamUrl(
    OnvifDevice device,
    String username,
    String password,
  ) async {
    try {
      String serviceUrl = device.xaddr;

      final profiles = await getProfiles(serviceUrl, username, password);
      if (profiles.isEmpty) {
        debugPrint('⚠️ ONVIF: No profiles found for ${device.ip}');
        return null;
      }

      final mainProfile = profiles.first;

      debugPrint(
        '✅ ONVIF: Selected profile ${mainProfile.name} (${mainProfile.token})',
      );

      final streamUri = await getStreamUri(
        serviceUrl,
        mainProfile.token,
        username,
        password,
      );

      return streamUri;
    } on OnvifException {
      rethrow;
    } catch (e) {
      debugPrint('❌ ONVIF Media Error: $e');
      throw OnvifNetworkException(e.toString());
    }
  }

  Future<List<OnvifProfile>> getProfiles(
    String serviceUrl,
    String username,
    String password,
  ) async {
    final soapBody = '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" 
            xmlns:trt="http://www.onvif.org/ver10/media/wsdl">
  <s:Body>
    <trt:GetProfiles/>
  </s:Body>
</s:Envelope>''';

    final response = await _sendSoapRequest(
      serviceUrl,
      soapBody,
      username,
      password,
    );

    if (response == null) return [];

    return _parseProfiles(response);
  }

  Future<String?> getStreamUri(
    String serviceUrl,
    String profileToken,
    String username,
    String password,
  ) async {
    final soapBody =
        '''
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" 
            xmlns:trt="http://www.onvif.org/ver10/media/wsdl"
            xmlns:tt="http://www.onvif.org/ver10/schema">
  <s:Body>
    <trt:GetStreamUri>
      <trt:StreamSetup>
        <tt:Stream>RTP-Unicast</tt:Stream>
        <tt:Transport>
          <tt:Protocol>RTSP</tt:Protocol>
        </tt:Transport>
      </trt:StreamSetup>
      <trt:ProfileToken>$profileToken</trt:ProfileToken>
    </trt:GetStreamUri>
  </s:Body>
</s:Envelope>''';

    final response = await _sendSoapRequest(
      serviceUrl,
      soapBody,
      username,
      password,
    );

    if (response == null) return null;

    final uri = _extractTag(response, 'Uri');
    return uri;
  }

  // =========================================================================
  // SOAP Helper Methods with WS-Security PasswordDigest
  // =========================================================================

  Future<String?> _sendSoapRequest(
    String url,
    String body,
    String username,
    String password,
  ) async {
    try {
      // Generate WS-Security header with PasswordDigest (ONVIF standard)
      final authHeader = _generateWSSecurityHeader(username, password);

      // Inject Header into Envelope
      final signedBody = body.replaceFirst('<s:Body>', '$authHeader<s:Body>');

      // Also add HTTP Basic Auth as fallback for cameras that support it
      final basicAuth =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';

      debugPrint('🔐 ONVIF: Sending authenticated SOAP request to $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type':
                  'application/soap+xml; charset=utf-8; action="http://www.onvif.org/ver10/media/wsdl/GetProfiles"',
              'Authorization': basicAuth,
            },
            body: signedBody,
          )
          .timeout(_requestTimeout);

      // Check HTTP status first
      if (response.statusCode == 401) {
        debugPrint('❌ ONVIF: HTTP 401 Unauthorized');
        throw const OnvifAuthenticationException('Invalid credentials');
      } else if (response.statusCode == 403) {
        debugPrint('❌ ONVIF: HTTP 403 Forbidden');
        throw const OnvifAuthorizationException('Access denied');
      } else if (response.statusCode != 200) {
        debugPrint('❌ ONVIF: HTTP ${response.statusCode}');
        throw OnvifServiceException(
          'HTTP ${response.statusCode}',
          faultReason: response.body.length > 200
              ? response.body.substring(0, 200)
              : response.body,
        );
      }

      // CRITICAL: Check for SOAP Fault even on HTTP 200
      // Many cameras return HTTP 200 with SOAP Fault in body
      final soapFault = _detectSoapFault(response.body);
      if (soapFault != null) {
        final faultInfo = soapFault is OnvifServiceException
            ? soapFault.faultCode ?? 'unknown'
            : soapFault.message;
        debugPrint('❌ ONVIF: SOAP Fault detected: $faultInfo');
        throw soapFault;
      }

      debugPrint('✅ ONVIF: SOAP request successful');
      return response.body;
    } on TimeoutException {
      debugPrint(
        '❌ ONVIF: Request timed out after ${_requestTimeout.inSeconds}s',
      );
      throw const OnvifTimeoutException('SOAP request timed out');
    } on OnvifException {
      rethrow;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      // Classify network errors
      if (errorStr.contains('host lookup') ||
          errorStr.contains('socketexception') ||
          errorStr.contains('connection refused')) {
        debugPrint('❌ ONVIF: Network error - $e');
        throw OnvifNetworkException(e.toString());
      }

      debugPrint('❌ ONVIF: Unexpected error - $e');
      throw OnvifServiceException('Request failed', faultReason: e.toString());
    }
  }

  // =========================================================================
  // WS-Security PasswordDigest Implementation (ONVIF Standard)
  // =========================================================================

  /// Generates WS-Security UsernameToken with PasswordDigest
  ///
  /// PasswordDigest = Base64(SHA1(nonce + created + password))
  /// This is REQUIRED by most enterprise ONVIF cameras (Hikvision, Dahua, etc.)
  String _generateWSSecurityHeader(String username, String password) {
    // Generate cryptographic nonce (16 random bytes)
    final random = Random.secure();
    final nonceBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final nonceBase64 = base64Encode(nonceBytes);

    // Generate timestamp in UTC ISO 8601 format
    final created = DateTime.now().toUtc().toIso8601String();

    // Calculate PasswordDigest: Base64(SHA1(nonce + created + password))
    final digestInput = [
      ...nonceBytes,
      ...utf8.encode(created),
      ...utf8.encode(password),
    ];
    final sha1Digest = sha1.convert(digestInput);
    final passwordDigest = base64Encode(sha1Digest.bytes);

    debugPrint('🔐 ONVIF: Generated WS-Security PasswordDigest');

    return '''
  <s:Header>
    <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" 
                   xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
                   s:mustUnderstand="1">
      <wsse:UsernameToken wsu:Id="UsernameToken-1">
        <wsse:Username>$username</wsse:Username>
        <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$passwordDigest</wsse:Password>
        <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonceBase64</wsse:Nonce>
        <wsu:Created>$created</wsu:Created>
      </wsse:UsernameToken>
    </wsse:Security>
  </s:Header>''';
  }

  // =========================================================================
  // SOAP Fault Detection (Critical for HTTP 200 with embedded faults)
  // =========================================================================

  /// Detects SOAP Faults in response body, even when HTTP 200
  ///
  /// Returns typed exception based on fault code:
  /// - ter:NotAuthorized / ter:NotAuthenticated → OnvifAuthenticationException
  /// - ter:ActionNotSupported → OnvifServiceException
  /// - Other faults → OnvifServiceException with details
  OnvifException? _detectSoapFault(String responseBody) {
    // Check for various SOAP fault patterns
    final faultPatterns = [
      '<Fault>',
      '<SOAP-ENV:Fault>',
      '<s:Fault>',
      '<soap:Fault>',
      ':Fault>',
    ];

    final hasFault = faultPatterns.any(
      (pattern) => responseBody.contains(pattern),
    );

    if (!hasFault) return null;

    debugPrint('⚠️ ONVIF: SOAP Fault detected in HTTP 200 response');

    // Extract fault code and reason
    String? faultCode =
        _extractTag(responseBody, 'Value') ??
        _extractTag(responseBody, 'faultcode') ??
        _extractTag(responseBody, 'Code');
    String? faultReason =
        _extractTag(responseBody, 'Reason') ??
        _extractTag(responseBody, 'faultstring') ??
        _extractTag(responseBody, 'Text');

    // Normalize fault code
    faultCode = faultCode?.toLowerCase() ?? 'unknown';
    faultReason = faultReason ?? 'SOAP Fault';

    debugPrint('   Fault Code: $faultCode');
    debugPrint('   Fault Reason: $faultReason');

    // Classify fault type
    if (faultCode.contains('notauthorized') ||
        faultCode.contains('notauthenticated') ||
        faultCode.contains('sender') &&
            faultReason.toLowerCase().contains('auth') ||
        faultReason.toLowerCase().contains('authentication') ||
        faultReason.toLowerCase().contains('unauthorized') ||
        faultReason.toLowerCase().contains('invalid username') ||
        faultReason.toLowerCase().contains('password')) {
      return OnvifAuthenticationException(faultReason);
    }

    if (faultCode.contains('action') || faultCode.contains('notsupported')) {
      return OnvifServiceException(
        'Action Not Supported',
        faultCode: faultCode,
        faultReason: faultReason,
      );
    }

    // Generic service error
    return OnvifServiceException(
      'Camera Error',
      faultCode: faultCode,
      faultReason: faultReason,
    );
  }

  // =========================================================================
  // Parsing Helpers
  // =========================================================================

  List<OnvifProfile> _parseProfiles(String xml) {
    final profiles = <OnvifProfile>[];

    final profileRegex = RegExp(
      r'(<[\w:]*Profiles.*?<\/.*?Profiles>)',
      dotAll: true,
    );
    final matches = profileRegex.allMatches(xml);

    for (final match in matches) {
      final profileXml = match.group(1)!;

      final token = _extractAttribute(profileXml, 'token');
      final name = _extractTag(profileXml, 'Name');

      final videoConfig = _extractTag(profileXml, 'VideoEncoderConfiguration');
      final encoding = videoConfig != null
          ? _extractTag(videoConfig, 'Encoding')
          : 'Unknown';

      final resolution = _extractTag(videoConfig ?? '', 'Resolution');
      final width = resolution != null
          ? int.tryParse(_extractTag(resolution, 'Width') ?? '0')
          : 0;
      final height = resolution != null
          ? int.tryParse(_extractTag(resolution, 'Height') ?? '0')
          : 0;

      if (token != null && name != null) {
        profiles.add(
          OnvifProfile(
            token: token,
            name: name,
            encoding: encoding ?? 'Unknown',
            width: width ?? 0,
            height: height ?? 0,
          ),
        );
      }
    }

    return profiles;
  }

  String? _extractTag(String xml, String tag) {
    final regExp = RegExp(
      '<[a-zA-Z0-9:]*$tag[^>]*>(.*?)</[a-zA-Z0-9:]*$tag>',
      dotAll: true,
    );
    final match = regExp.firstMatch(xml);
    return match?.group(1)?.trim();
  }

  String? _extractAttribute(String xml, String attribute) {
    final regExp = RegExp('$attribute="([^"]*)"');
    final match = regExp.firstMatch(xml);
    return match?.group(1);
  }
}
