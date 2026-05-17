import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String latestTag;
  final int latestBuild;
  final int currentBuild;
  final String ipaUrl;
  final bool hasUpdate;

  const UpdateInfo({
    required this.latestTag,
    required this.latestBuild,
    required this.currentBuild,
    required this.ipaUrl,
    required this.hasUpdate,
  });
}

class UpdateService {
  static const _owner = 'duynguyendao';
  static const _repo = 'pokemon_ct';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static Future<UpdateInfo> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    final resp = await http.get(
      Uri.parse(_apiUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('GitHub API error: ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String? ?? '';

    // Tag format: v1.0.0-b42 → parse build number after "b"
    final buildMatch = RegExp(r'-b(\d+)$').firstMatch(tag);
    final latestBuild = int.tryParse(buildMatch?.group(1) ?? '') ?? 0;

    // Find IPA asset download URL
    final assets = json['assets'] as List? ?? [];
    final ipaAsset = assets.firstWhere(
      (a) => (a['name'] as String).endsWith('.ipa'),
      orElse: () => null,
    );
    final ipaUrl = ipaAsset?['browser_download_url'] as String? ?? '';

    return UpdateInfo(
      latestTag: tag,
      latestBuild: latestBuild,
      currentBuild: currentBuild,
      ipaUrl: ipaUrl,
      hasUpdate: latestBuild > currentBuild,
    );
  }
}
