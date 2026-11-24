import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';

/// Offline downloads. Files live in the app documents dir; an index of
/// id -> {path,title} is kept in SharedPreferences.
class DownloadService {
  DownloadService(this._p);
  final SharedPreferences _p;
  final _dio = Dio();

  static const freeDailyLimit = 5; // premium users are unlimited

  Map<String, dynamic> get _index => jsonDecode(_p.getString('downloads') ?? '{}') as Map<String, dynamic>;
  Future<void> _save(Map<String, dynamic> m) => _p.setString('downloads', jsonEncode(m));

  String? localPath(String id) {
    final e = _index[id];
    if (e == null) return null;
    final path = e['path'] as String;
    return File(path).existsSync() ? path : null;
  }

  bool isDownloaded(String id) => localPath(id) != null;

  List<Map<String, dynamic>> all() =>
      _index.entries.map((e) => {...Map<String, dynamic>.from(e.value), 'id': e.key}).toList();

  int get _todayCount {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _p.getString('dl_day') == today ? (_p.getInt('dl_count') ?? 0) : 0;
  }

  bool canDownload(bool premium) => premium || _todayCount < freeDailyLimit;

  Future<String> download(ContentItem c, {void Function(double)? onProgress}) async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/downloads')..createSync(recursive: true);
    final path = '${dir.path}/${c.id}.${c.fileExt}';
    await _dio.download(c.url, path, onReceiveProgress: (r, t) {
      if (t > 0) onProgress?.call(r / t);
    });
    final m = _index
      ..[c.id] = {'path': path, 'title': c.title, 'kind': c.kind, 'section': c.section};
    await _save(m);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _p.setString('dl_day', today);
    await _p.setInt('dl_count', _todayCount + 1);
    return path;
  }

  Future<void> remove(String id) async {
    final m = _index;
    final e = m.remove(id);
    if (e != null) {
      final f = File(e['path']);
      if (f.existsSync()) f.deleteSync();
    }
    await _save(m);
  }

  /// Downloads to cache (not indexed) so a PDF can be opened without saving.
  Future<String> cacheTemp(ContentItem c) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${c.id}.${c.fileExt}';
    if (!File(path).existsSync()) await _dio.download(c.url, path);
    return path;
  }
}
