import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/models.dart';

class AuthRepository {
  AuthRepository(this._auth, this._db);
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Stream<AppUser?> watchUser(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((d) => d.exists ? AppUser.fromDoc(d) : null);

  Future<void> signIn(String email, String password) async {
    final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    await _ensureUserDoc(c.user!);
  }

  Future<void> signUp(String name, String email, String password) async {
    final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await c.user!.updateDisplayName(name.trim());
    await _ensureUserDoc(c.user!, name: name.trim());
  }

  Future<void> signInWithGoogle() async {
    final g = await GoogleSignIn().signIn();
    if (g == null) return; // user cancelled
    final a = await g.authentication;
    final cred = GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken);
    final c = await _auth.signInWithCredential(cred);
    await _ensureUserDoc(c.user!);
  }

  Future<void> continueAsGuest() async {
    final c = await _auth.signInAnonymously();
    await _ensureUserDoc(c.user!, name: 'Guest');
  }

  Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> updateProfile({required String uid, required String name}) async {
    await _auth.currentUser?.updateDisplayName(name);
    await _db.collection('users').doc(uid).update({'name': name});
  }

  Future<void> _ensureUserDoc(User u, {String? name}) async {
    final ref = _db.collection('users').doc(u.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      // Security rules force role=student and isPremium=false on create.
      await ref.set({
        'name': name ?? u.displayName ?? '',
        'email': u.email ?? '',
        'photoUrl': u.photoURL ?? '',
        'role': 'student',
        'isPremium': false,
        'isGuest': u.isAnonymous,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update({'lastActiveAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> touchActive(String uid) =>
      _db.collection('users').doc(uid).update({'lastActiveAt': FieldValue.serverTimestamp()}).catchError((_) {});
}
