import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'account_ai_consent.dart';

/// The real [AiConsentCache]: one small JSON file in the app support
/// directory, an entry per user id.
///
/// A file, matching `FileBackupConsent` and `FileDisclaimerStore`: a handful of
/// bytes, never queried in bulk, readable before anything else is open.
///
/// **Throws on failure, deliberately**, unlike those two. They return a safe
/// default themselves; this one's caller has to know whether a decision was
/// kept, because a withdrawal that silently failed to save would leave the
/// coach sending. `AccountAiConsent` catches and decides.
///
/// Imports `dart:io`, so reach it through `createAiConsentStore()`.
class FileAiConsentCache implements AiConsentCache {
  FileAiConsentCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const _fileName = 'ai_consent.json';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  Future<Map<String, Object?>> _all(File file) async {
    if (!await file.exists()) return <String, Object?>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return <String, Object?>{};
    return decoded;
  }

  @override
  Future<Map<String, Object?>?> read(String userId) async {
    final entry = (await _all(await _file()))[userId];
    return entry is Map<String, Object?> ? entry : null;
  }

  @override
  Future<void> write(String userId, Map<String, Object?>? entry) async {
    final file = await _file();
    final all = await _all(file);
    if (entry == null) {
      all.remove(userId);
    } else {
      all[userId] = entry;
    }
    if (all.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all), flush: true);
  }
}
