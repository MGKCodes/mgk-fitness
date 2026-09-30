import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cached_standing_plan_store.dart';

/// [PlanCache] as a file beside the database, written through a temporary file
/// and a rename so a crash mid-write leaves the previous plan rather than half
/// of one.
///
/// Imports `dart:io`, so only `main.dart` constructs it.
class FilePlanCache implements PlanCache {
  FilePlanCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const String _fileName = 'standing_plan.json';

  Future<File> _file() async =>
      File(p.join((await _directory()).path, _fileName));

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.tmp');
      await pending.writeAsString(json, flush: true);
      await pending.rename(file.path);
    } on Object {
      // The next load that reaches the server writes it again.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // A plan nobody can read is treated as no plan anyway.
    }
  }
}
