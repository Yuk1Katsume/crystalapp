import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

/// Supabase Storage bucket where APKs and version metadata are uploaded
const _kBucket = 'app-updates';
const _kVersionFile = 'latest.json';

class UpdateService {
  static SupabaseClient get _supabase => SupabaseConfig.client;

  /// Check if a newer version is available and return update info, or null if up to date
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // Fetch latest.json from Supabase Storage with cache busting timestamp
      final baseUrl = _supabase.storage.from(_kBucket).getPublicUrl(_kVersionFile);
      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> json = jsonDecode(response.body);
      final latestBuild = int.tryParse(json['build_number']?.toString() ?? '0') ?? 0;
      final latestVersion = json['version_name']?.toString() ?? '';
      final apkUrl = json['apk_url']?.toString() ?? '';
      final releaseNotes = json['release_notes']?.toString() ?? 'Nueva versión disponible';

      if (latestBuild > currentBuild && apkUrl.isNotEmpty) {
        return UpdateInfo(
          currentVersion: info.version,
          latestVersion: latestVersion,
          buildNumber: latestBuild,
          apkUrl: apkUrl,
          releaseNotes: releaseNotes,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Download the APK and trigger system installer, then delete old APK files
  static Future<void> downloadAndInstall(
    UpdateInfo update, {
    required void Function(double progress) onProgress,
    required void Function(String error) onError,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/crystalapp_update.apk';

      // Delete any previously downloaded APK to free space
      await _cleanOldApks(dir);

      // Download with progress
      final response = await http.Client().send(http.Request('GET', Uri.parse(update.apkUrl)));
      final contentLength = response.contentLength ?? 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (contentLength > 0) {
          onProgress(bytes.length / contentLength);
        }
      }

      final file = File(apkPath);
      await file.writeAsBytes(bytes);

      // Open installer
      final result = await OpenFile.open(apkPath, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        onError('No se pudo abrir el instalador: ${result.message}');
      }
    } catch (e) {
      onError('Error al descargar la actualización: $e');
    }
  }

  /// Remove old downloaded APK files from temp directory
  static Future<void> _cleanOldApks(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.apk')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  /// Minimal JSON parser for flat key-value pairs (no external dependency)
  static Map<String, String> _parseSimpleJson(String json) {
    final result = <String, String>{};
    final pattern = RegExp(r'"(\w+)"\s*:\s*"([^"]*)"');
    for (final match in pattern.allMatches(json)) {
      result[match.group(1)!] = match.group(2)!;
    }
    return result;
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
  });
}

/// Shows the in-app update dialog — call this after checkForUpdate() returns non-null
Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) async {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo update;
  const _UpdateDialog({required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Text('🌸', style: TextStyle(fontSize: 24)),
          SizedBox(width: 8),
          Text(
            'Actualización disponible',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${widget.update.currentVersion} → v${widget.update.latestVersion}',
            style: const TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            widget.update.releaseNotes,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white12,
                color: const Color(0xFFFF1744),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: _downloading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Más tarde', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF1744),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Actualizar ahora'),
                onPressed: _startDownload,
              ),
            ],
    );
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
    });

    await UpdateService.downloadAndInstall(
      widget.update,
      onProgress: (p) => setState(() => _progress = p),
      onError: (e) => setState(() {
        _error = e;
        _downloading = false;
      }),
    );
  }
}
