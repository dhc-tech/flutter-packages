import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import '../version_helper.dart';

class VersionUtils {
  /// Returns the latest stable (non-prerelease) version from pub.dev.
  static Future<String?> getLatestStableVersion() async {
    try {
      final url = Uri.parse('https://pub.dev/api/packages/dig_cli');
      final response = await http.get(url).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final latestVersion = json['latest']['version'] as String;
        return latestVersion;
      }
    } catch (_) {}
    return null;
  }

  static bool isNewer(String latest, String current) {
    try {
      return Version.parse(latest) > Version.parse(current);
    } catch (_) {
      return false;
    }
  }

  /// Returns the latest pre-release (dev/beta) version from pub.dev.
  static Future<String?> getLatestPreReleaseVersion() async {
    try {
      final url = Uri.parse('https://pub.dev/api/packages/dig_cli');
      final response = await http.get(url).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final versions = json['versions'] as List<dynamic>;

        Version? latestPre;
        String? latestPreStr;

        for (final v in versions) {
          final vStr = v['version'] as String;
          final parsed = Version.parse(vStr);
          if (parsed.isPreRelease) {
            if (latestPre == null || parsed > latestPre) {
              latestPre = parsed;
              latestPreStr = vStr;
            }
          }
        }
        return latestPreStr;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> isUpdateAvailable() async {
    final latest = await getLatestStableVersion();
    if (latest != null) {
      return isNewer(latest, kDigCliVersion);
    }
    return false;
  }

  static Future<bool> isBetaUpdateAvailable() async {
    final latest = await getLatestPreReleaseVersion();
    if (latest != null) {
      return isNewer(latest, kDigCliVersion);
    }
    return false;
  }
}
