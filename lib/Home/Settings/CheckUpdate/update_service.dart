// update_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _repoOwner = 'kyy-95631488';
  static const String _repoName = 'Vydra-Flutter-Android-For-Youtube-Stream';
  static const String _releasesUrl = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  Future<Map<String, dynamic>> checkForUpdate() async {
    try {
      final response = await http.get(Uri.parse(_releasesUrl)).timeout(
        const Duration(seconds: 5),
        onTimeout: () => http.Response('Timeout', 408),
      );

      if (response.statusCode != 200) {
        return {
          'hasUpdate': false,
          'error': 'Failed to check for updates: ${response.statusCode}',
        };
      }

      final data = jsonDecode(response.body);
      final latestVersion = data['tag_name']?.toString().replaceFirst('v', '') ?? '0.0.0';
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final hasUpdate = _isNewerVersion(latestVersion, currentVersion);

      return {
        'hasUpdate': hasUpdate,
        'latestVersion': latestVersion,
        'currentVersion': currentVersion,
        'releaseUrl': data['html_url'] ?? '',
        'error': null,
      };
    } catch (e) {
      return {
        'hasUpdate': false,
        'error': 'Error checking for updates: $e',
      };
    }
  }

  bool _isNewerVersion(String latest, String current) {
    final latestParts = latest.split('.').map(int.parse).toList();
    final currentParts = current.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }
    return false;
  }

  Future<void> launchUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }
}