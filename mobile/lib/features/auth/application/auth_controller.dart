import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/user_profile_repository.dart';

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

class AuthController extends AsyncNotifier<void> {
  late final UserProfileRepository _userProfileRepository;

  @override
  FutureOr<void> build() {
    _userProfileRepository = ref.read(userProfileRepositoryProvider);
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _syncUserProfile(credential.user);
    });
  }

  Future<void> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final normalizedName = fullName?.trim() ?? '';
      if (normalizedName.isNotEmpty) {
        await credential.user?.updateDisplayName(normalizedName);
      }

      await _syncUserProfile(FirebaseAuth.instance.currentUser);
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      late final UserCredential credential;

      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters(<String, String>{
            'prompt': 'select_account',
          });
        credential = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleSignIn = GoogleSignIn(scopes: <String>['email']);
        final googleUser = await _signInWithGoogleOnDevice(googleSignIn);
        if (googleUser == null) {
          throw FirebaseAuthException(
            code: 'aborted-by-user',
            message: 'Google sign-in was cancelled.',
          );
        }

        final googleAuth = await googleUser.authentication;
        final authCredential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        credential =
            await FirebaseAuth.instance.signInWithCredential(authCredential);
      }

      await _syncUserProfile(credential.user);
    });
  }

  Future<GoogleSignInAccount?> _signInWithGoogleOnDevice(
    GoogleSignIn googleSignIn,
  ) async {
    try {
      return await googleSignIn.signIn();
    } on PlatformException catch (error) {
      final message = (error.message ?? '').toLowerCase();
      final isAndroidConfigError =
          error.code == 'sign_in_failed' &&
          (message.contains('10') ||
              message.contains('developer_error') ||
              message.contains('12500'));

      if (isAndroidConfigError) {
        throw FirebaseAuthException(
          code: 'google-sign-in-not-configured',
          message:
              'Google sign-in is not configured for this Android app '
              '(missing SHA-1/SHA-256 or stale google-services.json).',
        );
      }
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!kIsWeb) {
        await GoogleSignIn().signOut();
      }
      await FirebaseAuth.instance.signOut();
    });
  }

  Future<void> _syncUserProfile(User? user) async {
    if (user == null) {
      return;
    }
    try {
      await _userProfileRepository.ensureUserProfile(user);
    } on FirebaseException catch (error) {
      if (_isRecoverableFirestoreError(error.code)) {
        debugPrint('User profile sync skipped: ${error.code}');
        return;
      }
      rethrow;
    }
  }

  bool _isRecoverableFirestoreError(String code) {
    return code == 'failed-precondition' ||
        code == 'permission-denied' ||
        code == 'unavailable' ||
        code == 'unauthenticated';
  }
}
