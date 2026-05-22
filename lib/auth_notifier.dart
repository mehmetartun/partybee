import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthNotifier extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final StreamSubscription<User?> _authSubscription;
  User? _user;

  AuthNotifier() {
    _user = _auth.currentUser;
    _authSubscription = _auth.userChanges().listen((User? user) {
      _user = user;
      notifyListeners();
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

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
