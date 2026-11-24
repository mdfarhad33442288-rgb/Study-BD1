import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/models.dart';

class ContentRepository {
  ContentRepository(this._db, this._storage);
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('content');

  /// Equality-only filters => no composite index needed. Sorted client-side.
  Stream<List<ContentItem>> watch({required String section, String? group, String? category, int limit = 300}) {
    Query<Map<String, dynamic>> q = _col.where('section', isEqualTo: section);
    if (group != null && group != 'all') q = q.where('group', isEqualTo: group);
    if (category != null) q = q.where('category', isEqualTo: category);
    return q.limit(limit).snapshots().map((s) {
      final list = s.docs.map(ContentItem.fromDoc).toList();
      list.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        return (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000));
      });
      return list;
    });
  }

  Stream<List<ContentItem>> watchLatest(String section, String category, {int limit = 5}) =>
      watch(section: section, category: category, limit: 50).map((l) => l.take(limit).toList());

  Future<List<ContentItem>> search(String term) async {
    final t = term.trim().toLowerCase();
    if (t.length < 2) return [];
    final key = t.split(RegExp(r'\s+')).first;
    final s = await _col.where('searchKeywords', arrayContains: key.length > 12 ? key.substring(0, 12) : key).limit(60).get();
    final list = s.docs.map(ContentItem.fromDoc).toList();
    return list.where((c) => '${c.title} ${c.titleBn}'.toLowerCase().contains(t)).toList();
  }

  Future<void> add(ContentItem c) => _col.add({...c.toMap(), 'createdAt': FieldValue.serverTimestamp()});

  Future<void> delete(ContentItem c) async {
    await _col.doc(c.id).delete();
    if (c.storagePath.isNotEmpty) {
      try {
        await _storage.ref(c.storagePath).delete();
      } catch (_) {}
    }
  }

  /// Uploads to Firebase Storage and returns (downloadUrl, storagePath, size).
  Future<(String, String, int)> upload(File file, String folder, String fileName, {void Function(double)? onProgress}) async {
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final ref = _storage.ref(path);
    final task = ref.putFile(file);
    task.snapshotEvents.listen((e) {
      if (e.totalBytes > 0) onProgress?.call(e.bytesTransferred / e.totalBytes);
    });
    await task;
    return (await ref.getDownloadURL(), path, await file.length());
  }

  /// Question bank for the Daily Quiz (`quizBank/{id}`: q, options, answer, explanation).
  Future<List<Question>> quizBank() async {
    final s = await _db.collection('quizBank').limit(200).get();
    return s.docs.map((d) => Question.fromMap(d.data())).where((q) => q.options.length >= 2 && q.answerIndex >= 0).toList();
  }

  /// Vocabulary list for Daily Vocabulary + Flashcards (`vocabulary/{id}`: word, meaningBn, meaningEn, example).
  Future<List<Map<String, dynamic>>> vocabulary() async {
    final s = await _db.collection('vocabulary').limit(500).get();
    return s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  // ---- Admin-defined categories -------------------------------------------
  Stream<List<Map<String, dynamic>>> watchCustomCategories(String section) => _db
      .collection('categories')
      .where('section', isEqualTo: section)
      .snapshots()
      .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());

  Future<void> addCategory(String section, String en, String bn) =>
      _db.collection('categories').add({'section': section, 'nameEn': en, 'nameBn': bn});

  Future<void> deleteCategory(String id) => _db.collection('categories').doc(id).delete();

  // ---- Config / stats -------------------------------------------------------
  Stream<Map<String, dynamic>> watchConfig() =>
      _db.collection('config').doc('app').snapshots().map((d) => d.data() ?? {});

  Future<void> saveConfig(Map<String, dynamic> m) => _db.collection('config').doc('app').set(m, SetOptions(merge: true));

  Future<void> bumpStat(String field) {
    final d = DateTime.now();
    final id = 'daily_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return _db.collection('stats').doc(id).set({field: FieldValue.increment(1)}, SetOptions(merge: true)).catchError((_) {});
  }
}
