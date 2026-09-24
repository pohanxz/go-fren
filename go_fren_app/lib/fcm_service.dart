import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Future<void> initialize() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    if (!Platform.isAndroid) {
      _initialized = true;
      return;
    }

    if (!_initialized) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((
        token,
      ) async {
        await _saveToken(token);
      });

      _initialized = true;
    }

    await _registerCurrentToken();
  }

  Future<void> _registerCurrentToken() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        return;
      }

      await _saveToken(token);
    } catch (_) {
      // FCM registration failure must not interrupt app startup.
    }
  }

  Future<void> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || token.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client.from('user_push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,token');
    } catch (_) {
      // Token storage failure must not interrupt the main app.
    }
  }

  Future<void> removeCurrentToken() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        return;
      }

      await Supabase.instance.client
          .from('user_push_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('token', token);
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _initialized = false;
  }

  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }
}
