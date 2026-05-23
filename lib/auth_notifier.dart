import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthNotifier extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final StreamSubscription<User?> _authSubscription;
  User? _user;

  AuthNotifier() {
    _user = _auth.currentUser;
    if (_user != null) {
      _checkAndCreateUserDocument(_user!);
    }
    _authSubscription = _auth.userChanges().listen((User? user) {
      final oldUid = _user?.uid;
      _user = user;
      notifyListeners();

      if (user != null && user.uid != oldUid) {
        _checkAndCreateUserDocument(user);
      } else if (user != null) {
        // If the same user's verification status or other details changed, update it.
        _checkAndCreateUserDocument(user);
      }
    });
  }

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isEmailVerified => _user?.emailVerified ?? false;

  /// Trigger a manual refresh by reloading the current user from Firebase.
  /// This is useful on the Email Verification screen to check if the user
  /// has verified their email.
  Future<void> refreshUser() async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      await currentUser.reload();
      // userChanges stream will automatically capture the reloaded user state.
    }
  }

  /// Automatically checks if the /users/uid document exists in Firestore.
  /// If it doesn't, creates it with email, display name, photo URL, and emailVerified status.
  Future<void> _checkAndCreateUserDocument(User user) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        final Map<String, dynamic> userData = {
          'uid': user.uid,
          'email': user.email,
          'emailVerified': user.emailVerified,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (user.displayName != null && user.displayName!.isNotEmpty) {
          userData['displayName'] = user.displayName;
        }

        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          userData['photoUrl'] = user.photoURL;
        }

        await docRef.set(userData);
      } else {
        // Ensure emailVerified is always kept in sync
        await docRef.update({
          'emailVerified': user.emailVerified,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error syncing user document to Firestore: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
