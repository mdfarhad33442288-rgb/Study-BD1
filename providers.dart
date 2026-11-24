import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/content_repository.dart';
import '../data/repositories/exam_repository.dart';
import 'services/download_service.dart';

final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError('override in main()'));

final authRepoProvider = Provider((_) => AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance));
final contentRepoProvider = Provider((_) => ContentRepository(FirebaseFirestore.instance, FirebaseStorage.instance));
final examRepoProvider = Provider((_) => ExamRepository(FirebaseFirestore.instance));
final functionsProvider = Provider((_) => FirebaseFunctions.instanceFor(region: 'asia-south1'));
final downloadServiceProvider = Provider((ref) => DownloadService(ref.watch(prefsProvider)));

final authStateProvider = StreamProvider<User?>((ref) => ref.watch(authRepoProvider).authChanges());

final appUserProvider = StreamProvider<AppUser?>((ref) {
  final u = ref.watch(authStateProvider).valueOrNull;
  if (u == null) return const Stream.empty();
  return ref.watch(authRepoProvider).watchUser(u.uid);
});

final isAdminProvider = Provider((ref) => ref.watch(appUserProvider).valueOrNull?.isAdmin ?? false);
final isPremiumProvider = Provider((ref) => ref.watch(appUserProvider).valueOrNull?.isPremium ?? false);

/// Firestore rules require a signed-in user, so only listen once logged in.
final remoteConfigProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.watch(contentRepoProvider).watchConfig();
});

// ---- Theme & language (persisted) -------------------------------------------
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(this._p) : super(ThemeMode.values[_p.getInt('theme') ?? 0]);
  final SharedPreferences _p;
  void set(ThemeMode m) {
    state = m;
    _p.setInt('theme', m.index);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) => ThemeNotifier(ref.watch(prefsProvider)));

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier(this._p) : super(Locale(_p.getString('lang') ?? 'bn'));
  final SharedPreferences _p;
  void set(String code) {
    state = Locale(code);
    _p.setString('lang', code);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier(ref.watch(prefsProvider)));

// ---- Bookmarks (local, instant; mirrored to Firestore when signed in) -------
class BookmarksNotifier extends StateNotifier<List<ContentItem>> {
  BookmarksNotifier(this._p, this._uid) : super(_load(_p));
  final SharedPreferences _p;
  final String? _uid;

  static List<ContentItem> _load(SharedPreferences p) {
    final raw = p.getStringList('bookmarks') ?? [];
    return raw.map((s) => ContentItem.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map))).toList();
  }

  bool has(String id) => state.any((c) => c.id == id);

  void toggle(ContentItem c) {
    final adding = !has(c.id);
    state = adding ? [...state, c] : state.where((e) => e.id != c.id).toList();
    _p.setStringList('bookmarks', state.map((e) => jsonEncode(e.toJson())).toList());
    final uid = _uid;
    if (uid != null) {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid).collection('bookmarks').doc(c.id);
      (adding ? ref.set({'contentId': c.id, 'at': FieldValue.serverTimestamp()}) : ref.delete()).catchError((_) {});
    }
  }
}

final bookmarksProvider = StateNotifierProvider<BookmarksNotifier, List<ContentItem>>(
    (ref) => BookmarksNotifier(ref.watch(prefsProvider), ref.watch(authStateProvider).valueOrNull?.uid));

