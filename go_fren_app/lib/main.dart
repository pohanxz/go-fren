import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  
  await NotificationService.instance.initialize();

  runApp(const GoFrenApp());
}

class GoFrenApp extends StatefulWidget {
  const GoFrenApp({super.key});

  @override
  State<GoFrenApp> createState() => _GoFrenAppState();
}

class _GoFrenAppState extends State<GoFrenApp> {
  StreamSubscription<AuthState>? authSubscription;
  final navigatorKey = GlobalKey<NavigatorState>();
  bool isPasswordRecovery = false;

  RealtimeChannel? _globalMatchesChannel;
  String? _globalMatchesUserId;
  RealtimeChannel? _globalMessagesChannel;
  String? _globalMessagesUserId;
  final Set<String> _notifiedMatchKeys = <String>{};
  final Set<String> _notifiedMessageIds = <String>{};

  @override
  void initState() {
    super.initState();

    authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        isPasswordRecovery = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const UpdatePasswordScreen(),
            ),
            (route) => false,
          );
        });
      }

      if (data.event == AuthChangeEvent.initialSession ||
          data.event == AuthChangeEvent.signedIn) {
        updateCurrentUserLocation();

        final user = Supabase.instance.client.auth.currentUser;

        if (user != null) {
          _subscribeToGlobalMatchNotifications(user.id);
          _subscribeToGlobalMessageNotifications(user.id);
        }
      }

      if (data.event == AuthChangeEvent.signedOut) {
        _unsubscribeFromGlobalMatchNotifications();
        _unsubscribeFromGlobalMessageNotifications();
      }
    });
  }

  void _subscribeToGlobalMatchNotifications(String userId) {
    if (_globalMatchesUserId == userId &&
        _globalMatchesChannel != null) {
      return;
    }

    _unsubscribeFromGlobalMatchNotifications();

    _globalMatchesUserId = userId;

    _globalMatchesChannel = Supabase.instance.client
        .channel('global-matches-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            await _handleGlobalMatchNotification(
              payload,
              userId,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'matched_user_id',
            value: userId,
          ),
          callback: (payload) async {
            await _handleGlobalMatchNotification(
              payload,
              userId,
            );
          },
        )
        .subscribe();
  }

  void _unsubscribeFromGlobalMatchNotifications() {
    final channel = _globalMatchesChannel;

    _globalMatchesChannel = null;
    _globalMatchesUserId = null;
    _notifiedMatchKeys.clear();

    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
  }

  void _subscribeToGlobalMessageNotifications(String userId) {
    if (_globalMessagesUserId == userId &&
        _globalMessagesChannel != null) {
      return;
    }

    _unsubscribeFromGlobalMessageNotifications();

    _globalMessagesUserId = userId;

    _globalMessagesChannel = Supabase.instance.client
        .channel('global-messages-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            await _handleGlobalMessageNotification(
              payload,
              userId,
            );
          },
        )
        .subscribe();
  }

  void _unsubscribeFromGlobalMessageNotifications() {
    final channel = _globalMessagesChannel;

    _globalMessagesChannel = null;
    _globalMessagesUserId = null;
    _notifiedMessageIds.clear();

    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
  }

  Future<void> _handleGlobalMessageNotification(
    PostgresChangePayload payload,
    String userId,
  ) async {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != userId) {
      return;
    }

    final record = payload.newRecord;

    final messageId = record['id']?.toString();
    final senderId = record['sender_id']?.toString();
    final matchId = record['match_id']?.toString();
    final message = record['message']?.toString();

    if (messageId == null ||
        senderId == null ||
        matchId == null ||
        message == null) {
      return;
    }

    if (senderId == userId) {
      return;
    }

    if (_notifiedMessageIds.contains(messageId)) {
      return;
    }

    _notifiedMessageIds.add(messageId);

    try {
      final settingResponse = await Supabase.instance.client
          .from('notification_settings')
          .select('enabled')
          .eq('user_id', userId)
          .maybeSingle();

      final notificationsEnabled =
          settingResponse?['enabled'] as bool? ?? true;

      if (!notificationsEnabled) {
        return;
      }

      final matchResponse = await Supabase.instance.client
          .from('matches')
          .select('user_id, matched_user_id')
          .eq('id', matchId)
          .maybeSingle();

      if (matchResponse == null) {
        return;
      }

      final matchUserId =
          matchResponse['user_id']?.toString();
      final matchedUserId =
          matchResponse['matched_user_id']?.toString();

      if (matchUserId == null || matchedUserId == null) {
        return;
      }

      final isUserInMatch =
          matchUserId == userId || matchedUserId == userId;

      if (!isUserInMatch) {
        return;
      }

      final senderIsMatchParticipant =
          matchUserId == senderId || matchedUserId == senderId;

      if (!senderIsMatchParticipant) {
        return;
      }

      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('name')
          .eq('id', senderId)
          .maybeSingle();

      if (profileResponse == null) {
        return;
      }

      final name =
          profileResponse['name'] as String? ?? 'Someone';

      await NotificationService.instance.showMessageNotification(
        name: name,
        message: message,
      );
    } catch (_) {
      // Notification errors must not interrupt the main app flow.
    }
  }

  Future<void> _handleGlobalMatchNotification(
    PostgresChangePayload payload,
    String userId,
  ) async {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null || currentUser.id != userId) {
      return;
    }

    final record = payload.newRecord;

    final matchUserId = record['user_id'] as String?;
    final matchedUserId = record['matched_user_id'] as String?;

    if (matchUserId == null || matchedUserId == null) {
      return;
    }

    final otherUserId =
        matchUserId == userId ? matchedUserId : matchUserId;

    final pair = [userId, otherUserId]..sort();

    final matchKey = pair.join(':');

    if (_notifiedMatchKeys.contains(matchKey)) {
      return;
    }

    _notifiedMatchKeys.add(matchKey);

    try {
      final settingResponse = await Supabase.instance.client
          .from('notification_settings')
          .select('enabled')
          .eq('user_id', userId)
          .maybeSingle();

      final notificationsEnabled =
          settingResponse?['enabled'] as bool? ?? true;

      if (!notificationsEnabled) {
        return;
      }

      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('name')
          .eq('id', otherUserId)
          .maybeSingle();

      if (profileResponse == null) {
        return;
      }

      final name =
          profileResponse['name'] as String? ?? 'Someone';

      await NotificationService.instance.showMatchNotification(
        name: name,
      );
    } catch (_) {
      // Notification errors must not interrupt the main app flow.
    }
  }

  @override
  void dispose() {
    _unsubscribeFromGlobalMatchNotifications();
    _unsubscribeFromGlobalMessageNotifications();
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Go Fren',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.grey.shade200,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF6C5CE7),
              width: 2,
            ),
          ),
        ),
      ),
      home: isPasswordRecovery
          ? const UpdatePasswordScreen()
          : const SplashScreen(),
    );
  }
}

Future<void> updateCurrentUserLocation() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      await Supabase.instance.client.from('user_locations').upsert({
        'user_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Location is optional and should not interrupt the app.
    }
}

// ============================================================
// UPDATE PASSWORD
// ============================================================

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isSaving = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> updatePassword() async {
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match.'),
        ),
      );
      return;
    }

    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully.'),
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update password. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set New Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 35),
              const Center(
                child: Icon(
                  Icons.lock_reset_rounded,
                  size: 75,
                  color: Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Set a new password',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a new password for your Go Fren account.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                    icon: Icon(
                      obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isSaving ? null : updatePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    isSaving ? 'UPDATING...' : 'UPDATE PASSWORD',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DATA MODEL
// ============================================================

class Profile {
  final String? id;
  final String name;
  final int age;
  final String city;
  final String bio;
  final String imageUrl;
  final List<String> interests;
  final double? distanceKm;

  const Profile({
    this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.bio,
    required this.imageUrl,
    required this.interests,
    this.distanceKm,
  });
}



// ============================================================
// SPLASH
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<AuthState>? authSubscription;
  bool isPasswordRecovery = false;

  @override
  void initState() {
    super.initState();

    authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery && mounted) {
        isPasswordRecovery = true;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const UpdatePasswordScreen(),
          ),
        );
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || isPasswordRecovery) return;

      final session = Supabase.instance.client.auth.currentSession;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AgeGateScreen(
            isLoggedIn: session != null,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF6C5CE7),
              Color(0xFF8E7CFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  size: 55,
                  color: Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Go Fren',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Meet. Match. Connect.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AgeGateScreen extends StatelessWidget {
  final bool isLoggedIn;

  const AgeGateScreen({
    super.key,
    required this.isLoggedIn,
  });

  void continueToApp(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const MainNavigation() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 55,
                  color: Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                'Go Fren is 18+',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Go Fren is intended only for adults aged 18 and older.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'By continuing, you confirm that you are 18 years old or older.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () => continueToApp(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'I AM 18 OR OLDER',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text(
                    'EXIT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MainNavigation(),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login failed. Please try again.'),
        ),
      );
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email first.'),
        ),
      );
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'gofren://reset-password',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent. Check your inbox.'),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send password reset email.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 45),
              const Icon(
                Icons.people_alt_rounded,
                size: 58,
                color: Color(0xFF6C5CE7),
              ),
              const SizedBox(height: 25),
              const Text(
                'Welcome back!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue to Go Fren.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 35),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'LOG IN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text('Create account'),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Center(
                child: Text(
                  'Go Fren is for users 18+ only.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REGISTER
// ============================================================

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final cityController = TextEditingController();

  DateTime? birthDate;
  String? gender;
  bool is18Plus = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    cityController.dispose();
    super.dispose();
  }

  Future<void> selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (selected != null) {
      setState(() {
        birthDate = selected;
      });
    }
  }

  Future<void> continueRegistration() async {
    if (!is18Plus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must confirm that you are 18 or older.'),
        ),
      );
      return;
    }

    if (birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your date of birth.'),
        ),
      );
      return;
    }

    final today = DateTime.now();
    var age = today.year - birthDate!.year;

    if (today.month < birthDate!.month ||
        (today.month == birthDate!.month &&
            today.day < birthDate!.day)) {
      age--;
    }

    if (age < 18) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be 18 years old or older.'),
        ),
      );
      return;
    }

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final user = response.user;

      if (user == null) {
        throw const AuthException('Registration failed.');
      }

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'name': nameController.text.trim(),
        'bio': '',
        'gender': gender,
        'birth_date': birthDate!.toIso8601String().split('T').first,
        'city': cityController.text.trim(),
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileSetupScreen(
            name: nameController.text,
            city: cityController.text,
            birthDate: birthDate!,
            gender: gender,
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration failed. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Join Go Fren',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create your account and start connecting.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cake_outlined),
                title: Text(
                  birthDate == null
                      ? 'Date of birth'
                      : '${birthDate!.day}/${birthDate!.month}/${birthDate!.year}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: selectDate,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: Icon(Icons.wc_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Male',
                    child: Text('Male'),
                  ),
                  DropdownMenuItem(
                    value: 'Female',
                    child: Text('Female'),
                  ),
                  DropdownMenuItem(
                    value: 'Other',
                    child: Text('Other'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    gender = value;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: is18Plus,
                title: const Text(
                  'I confirm that I am 18 years old or older.',
                ),
                onChanged: (value) {
                  setState(() {
                    is18Plus = value ?? false;
                  });
                },
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: is18Plus ? continueRegistration : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    'CONTINUE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Log in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PROFILE SETUP
// ============================================================

class ProfileSetupScreen extends StatefulWidget {
  final String name;
  final String city;
  final DateTime birthDate;
  final String? gender;

  const ProfileSetupScreen({
    super.key,
    required this.name,
    required this.city,
    required this.birthDate,
    required this.gender,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController cityController;
  final bioController = TextEditingController();

  XFile? selectedImage;
  bool isSaving = false;

  final interests = [
    'Music',
    'Movies',
    'Travel',
    'Sports',
    'Gaming',
    'Books',
    'Food',
    'Photography',
  ];

  final selectedInterests = <String>{};

  @override
  void initState() {
    super.initState();
    cityController = TextEditingController(text: widget.city);
  }

  @override
  void dispose() {
    cityController.dispose();
    bioController.dispose();
    super.dispose();
  }

  Future<void> pickImage(ImageSource source) async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (image == null || !mounted) return;

    setState(() {
      selectedImage = image;
    });
  }

  Future<void> showImageSourcePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> saveProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session not found. Please log in again.'),
        ),
      );
      return;
    }

    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a profile photo before continuing.'),
        ),
      );
      return;
    }

    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      final filePath = '${user.id}/profile.jpg';

      await Supabase.instance.client.storage
          .from('avatars')
          .upload(
            filePath,
            File(selectedImage!.path),
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final avatarUrl =
          '${Supabase.instance.client.storage.from('avatars').getPublicUrl(filePath)}?v=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'name': widget.name.trim(),
        'bio': bioController.text.trim(),
        'gender': widget.gender,
        'birth_date': widget.birthDate.toIso8601String().split('T').first,
        'city': cityController.text.trim(),
        'avatar_url': avatarUrl,
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigation()),
        (route) => false,
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete Your Profile',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tell people a little about yourself.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 25),
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: showImageSourcePicker,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: const Color(0xFFE8E5FF),
                        backgroundImage: selectedImage != null
                            ? FileImage(File(selectedImage!.path))
                            : null,
                        child: selectedImage == null
                            ? const Icon(
                                Icons.person,
                                size: 65,
                                color: Color(0xFF6C5CE7),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF6C5CE7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              Text(
                'Your name',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.name.isEmpty ? 'Your Name' : widget.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bioController,
                maxLength: 160,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell people something about you...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your interests',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: interests.map((interest) {
                  final selected =
                      selectedInterests.contains(interest);

                  return FilterChip(
                    label: Text(interest),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          selectedInterests.add(interest);
                        } else {
                          selectedInterests.remove(interest);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isSaving ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    isSaving ? 'SAVING...' : 'SAVE PROFILE',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN NAVIGATION
// ============================================================

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int currentIndex = 0;
  int matchCount = 0;

  RealtimeChannel? _matchesBadgeChannel;

  final pages = const [
    DiscoveryScreen(),
    MatchesScreen(),
    ChatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    loadMatchCount();
    _subscribeToMatchCount();
  }

  Future<void> loadMatchCount() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('matches')
          .select('id')
          .or('user_id.eq.${user.id},matched_user_id.eq.${user.id}');

      if (!mounted) return;

      setState(() {
        matchCount = (response as List).length;
      });
    } catch (_) {
      // Badge count is optional and should not interrupt navigation.
    }
  }

  void _subscribeToMatchCount() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    _matchesBadgeChannel = Supabase.instance.client
        .channel('matches-badge-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (_) {
            loadMatchCount();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'matched_user_id',
            value: user.id,
          ),
          callback: (_) {
            loadMatchCount();
          },
        )
        .subscribe();
  }

  Widget _matchBadgeIcon(IconData icon) {
    return Badge(
      isLabelVisible: matchCount > 0,
      label: Text(
        matchCount > 99 ? '99+' : '$matchCount',
      ),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: _matchBadgeIcon(Icons.favorite_border),
            selectedIcon: _matchBadgeIcon(Icons.favorite),
            label: 'Matches',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_matchesBadgeChannel != null) {
      Supabase.instance.client.removeChannel(_matchesBadgeChannel!);
    }
    super.dispose();
  }
}

// ============================================================
// DISCOVERY
// ============================================================

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  int currentProfile = 0;
  List<Profile> profiles = [];
  bool isLoading = true;

  double swipeOffset = 0;
  double swipeRotation = 0;

  final List<Profile> skippedProfiles = [];
  final Set<String> incomingSuperLikeIds = {};
  bool showIncomingSuperLikeBanner = false;
  int _superLikeBannerToken = 0;

  String showMe = 'both';
  double minAge = 18;
  double maxAge = 100;
  double maxDistanceKm = 50;

  @override
  void initState() {
    super.initState();
    _initializeDiscovery();
    _subscribeToIncomingSuperLikes();
  }

  void _subscribeToIncomingSuperLikes() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    Supabase.instance.client
        .channel('incoming-super-likes-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'likes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'liked_user_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = payload.newRecord;

            if (record['is_super_like'] != true) {
              return;
            }

            final senderId = record['user_id'] as String?;

            if (senderId == null || !mounted) {
              return;
            }

            final bannerToken = ++_superLikeBannerToken;

            setState(() {
              incomingSuperLikeIds.add(senderId);
              showIncomingSuperLikeBanner = true;
            });

            Future.delayed(const Duration(milliseconds: 2500), () {
              if (!mounted || bannerToken != _superLikeBannerToken) {
                return;
              }

              setState(() {
                showIncomingSuperLikeBanner = false;
              });
            });
          },
        )
        .subscribe();
  }

  Future<void> _initializeDiscovery() async {
    await loadDiscoveryPreferences();
    await updateCurrentUserLocation();
    await loadProfiles();
  }

  Future<void> loadDiscoveryPreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('discovery_preferences')
          .select('show_me, min_age, max_age, max_distance_km')
          .eq('user_id', user.id)
          .maybeSingle();

      if (response == null) return;

      if (!mounted) return;

      setState(() {
        showMe = response['show_me'] as String? ?? 'both';
        minAge = (response['min_age'] as num?)?.toDouble() ?? 18;
        maxAge = (response['max_age'] as num?)?.toDouble() ?? 100;
        maxDistanceKm =
            (response['max_distance_km'] as num?)?.toDouble() ?? 50;
      });
    } catch (_) {
      // Use defaults if preferences cannot be loaded.
    }
  }

  Future<void> loadIncomingSuperLikes() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('likes')
          .select('user_id')
          .eq('liked_user_id', user.id)
          .eq('is_super_like', true);

      incomingSuperLikeIds
        ..clear()
        ..addAll(
          (response as List).map(
            (item) => item['user_id'] as String,
          ),
        );
    } catch (_) {
      // Incoming Super Like indicator is optional.
    }
  }

  Future<void> loadProfiles() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .rpc('get_discoverable_profiles');

      await loadIncomingSuperLikes();

      final loadedProfiles = <Profile>[];

      for (final item in response as List) {
        final id = item['id'] as String;

        final birthDateText = item['birth_date'] as String?;
        final birthDate = birthDateText != null
            ? DateTime.tryParse(birthDateText)
            : null;

        if (birthDate == null) continue;

        final now = DateTime.now();
        var age = now.year - birthDate.year;

        if (now.month < birthDate.month ||
            (now.month == birthDate.month && now.day < birthDate.day)) {
          age--;
        }

        final distanceValue = item['distance_km'];
        final distanceKm = distanceValue is num
            ? distanceValue.toDouble()
            : null;

        loadedProfiles.add(
          Profile(
            id: id,
            name: item['name'] as String? ?? 'Unknown',
            age: age,
            city: item['city'] as String? ?? '',
            bio: item['bio'] as String? ?? '',
            imageUrl: item['avatar_url'] as String? ?? '',
            interests: const [],
            distanceKm: distanceKm,
          ),
        );
      }

      final superLikedProfiles = loadedProfiles
          .where((profile) => incomingSuperLikeIds.contains(profile.id))
          .toList();

      final regularProfiles = loadedProfiles
          .where((profile) => !incomingSuperLikeIds.contains(profile.id))
          .toList();

      loadedProfiles
        ..clear()
        ..addAll(superLikedProfiles)
        ..addAll(regularProfiles);

      if (!mounted) return;

      setState(() {
        profiles = loadedProfiles;
        currentProfile = 0;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load profiles.'),
        ),
      );
    }
  }

  void skip() {
    if (profiles.isEmpty) {
      return;
    }

    setState(() {
      skippedProfiles.add(profiles[currentProfile]);

      if (currentProfile < profiles.length - 1) {
        currentProfile++;
      } else {
        currentProfile = 0;
      }
    });
  }

  void rewind() {
    if (skippedProfiles.isEmpty || profiles.isEmpty) {
      return;
    }

    setState(() {
      final previousProfile = skippedProfiles.removeLast();
      final existingIndex = profiles.indexWhere(
        (profile) => profile.id == previousProfile.id,
      );

      if (existingIndex >= 0) {
        currentProfile = existingIndex;
      }
    });
  }

  Future<void> superLike() async {
    final user = Supabase.instance.client.auth.currentUser;
    final profile = profiles[currentProfile];

    if (user == null || profile.id == null) {
      return;
    }

    try {
      await Supabase.instance.client.from('likes').insert({
        'user_id': user.id,
        'liked_user_id': profile.id,
        'is_super_like': true,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You super liked ${profile.name}!'),
          duration: const Duration(milliseconds: 900),
        ),
      );

      setState(() {
        if (currentProfile < profiles.length - 1) {
          currentProfile++;
        } else {
          currentProfile = 0;
        }
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      if (e.code == '23505') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already liked this profile.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to super like: ${e.message}'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to super like.'),
        ),
      );
    }
  }

  Future<void> like() async {
    final user = Supabase.instance.client.auth.currentUser;
    final profile = profiles[currentProfile];

    if (user == null || profile.id == null) {
      return;
    }

    try {
      await Supabase.instance.client.from('likes').insert({
        'user_id': user.id,
        'liked_user_id': profile.id,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You liked ${profile.name}!'),
          duration: const Duration(milliseconds: 900),
        ),
      );

      setState(() {
        if (currentProfile < profiles.length - 1) {
          currentProfile++;
        } else {
          currentProfile = 0;
        }
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      if (e.code == '23505') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already liked this profile.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send like. Please try again.'),
        ),
      );
    }
  }


  Future<void> saveDiscoveryPreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('discovery_preferences')
          .upsert({
        'user_id': user.id,
        'show_me': showMe,
        'min_age': minAge.round(),
        'max_age': maxAge.round(),
        'max_distance_km': maxDistanceKm,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      rethrow;
    }
  }

  Future<void> refreshDiscovery() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    try {
      await updateCurrentUserLocation();
      await loadProfiles();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to refresh discovery.'),
        ),
      );
    }
  }

  Future<void> showDiscoveryFilters() async {
    var selectedShowMe = showMe;
    var selectedMinAge = minAge;
    var selectedMaxAge = maxAge;
    var selectedDistance = maxDistanceKm;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Discovery Filters',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Show me',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'male',
                            label: Text('Male'),
                            icon: Icon(Icons.male),
                          ),
                          ButtonSegment(
                            value: 'female',
                            label: Text('Female'),
                            icon: Icon(Icons.female),
                          ),
                          ButtonSegment(
                            value: 'both',
                            label: Text('Both'),
                            icon: Icon(Icons.people_alt_outlined),
                          ),
                        ],
                        selected: {selectedShowMe},
                        onSelectionChanged: (selection) {
                          setSheetState(() {
                            selectedShowMe = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 25),
                      Text(
                        'Age: ${selectedMinAge.round()} - ${selectedMaxAge.round()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      RangeSlider(
                        min: 18,
                        max: 100,
                        divisions: 82,
                        values: RangeValues(
                          selectedMinAge,
                          selectedMaxAge,
                        ),
                        labels: RangeLabels(
                          selectedMinAge.round().toString(),
                          selectedMaxAge.round().toString(),
                        ),
                        onChanged: (values) {
                          setSheetState(() {
                            selectedMinAge = values.start;
                            selectedMaxAge = values.end;
                          });
                        },
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'Maximum distance: ${selectedDistance.round()} km',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Slider(
                        min: 1,
                        max: 500,
                        divisions: 499,
                        value: selectedDistance,
                        label: '${selectedDistance.round()} km',
                        onChanged: (value) {
                          setSheetState(() {
                            selectedDistance = value;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            true,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C5CE7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'APPLY FILTERS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          onPressed: () {
                            selectedShowMe = 'both';
                            selectedMinAge = 18;
                            selectedMaxAge = 100;
                            selectedDistance = 50;
                            Navigator.pop(
                              sheetContext,
                              true,
                            );
                          },
                          child: const Text(
                            'RESET FILTERS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (applied != true || !mounted) return;

    setState(() {
      showMe = selectedShowMe;
      minAge = selectedMinAge;
      maxAge = selectedMaxAge;
      maxDistanceKm = selectedDistance;
      isLoading = true;
    });

    try {
      await saveDiscoveryPreferences();
      await updateCurrentUserLocation();
      await loadProfiles();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save discovery filters.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (profiles.isEmpty) {
      return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_alt_rounded,
                    color: Color(0xFF6C5CE7),
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Go Fren',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: refreshDiscovery,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh discovery',
                  ),
                  IconButton(
                    onPressed: showDiscoveryFilters,
                    icon: const Icon(Icons.tune),
                    tooltip: 'Discovery filters',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 17,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${showMe == 'both' ? 'Everyone' : showMe == 'male' ? 'Male' : 'Female'} · '
                      '${minAge.round()}–${maxAge.round()} · '
                      '≤ ${maxDistanceKm.round()} km',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 72,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No profiles available right now.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try refreshing Discovery or adjusting your filters.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: refreshDiscovery,
                        icon: const Icon(Icons.refresh),
                        label: const Text('REFRESH DISCOVERY'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C5CE7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final profile = profiles[currentProfile];

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF6C5CE7),
                  size: 32,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Go Fren',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: refreshDiscovery,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh discovery',
                ),
                IconButton(
                  onPressed: showDiscoveryFilters,
                  icon: const Icon(Icons.tune),
                  tooltip: 'Discovery filters',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 17,
                  color: Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${showMe == 'both' ? 'Everyone' : showMe == 'male' ? 'Male' : 'Female'} · '
                    '${minAge.round()}–${maxAge.round()} · '
                    '≤ ${maxDistanceKm.round()} km',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${currentProfile + 1}/${profiles.length}',
                  style: const TextStyle(
                    color: Color(0xFF6C5CE7),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (showIncomingSuperLikeBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFFC107).withValues(alpha: 0.45),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC107),
                      size: 26,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Someone Super Liked You!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 15),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileDetailScreen(
                        profile: profile,
                      ),
                    ),
                  );
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    swipeOffset += details.delta.dx;
                    swipeRotation = swipeOffset / 900;
                  });
                },
                onHorizontalDragEnd: (details) {
                  if (swipeOffset > 120) {
                    setState(() {
                      swipeOffset = 500;
                      swipeRotation = 0.15;
                    });

                    Future.delayed(
                      const Duration(milliseconds: 180),
                      () {
                        if (!mounted) return;
                        like();
                        setState(() {
                          swipeOffset = 0;
                          swipeRotation = 0;
                        });
                      },
                    );
                  } else if (swipeOffset < -120) {
                    setState(() {
                      swipeOffset = -500;
                      swipeRotation = -0.15;
                    });

                    Future.delayed(
                      const Duration(milliseconds: 180),
                      () {
                        if (!mounted) return;
                        skip();
                        setState(() {
                          swipeOffset = 0;
                          swipeRotation = 0;
                        });
                      },
                    );
                  } else {
                    setState(() {
                      swipeOffset = 0;
                      swipeRotation = 0;
                    });
                  }
                },
                child: Transform.translate(
                  offset: Offset(swipeOffset, 0),
                  child: Transform.rotate(
                    angle: swipeRotation,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      elevation: 5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (swipeOffset > 20)
                            Positioned(
                              top: 35,
                              left: 25,
                              child: Opacity(
                                opacity: (swipeOffset / 180).clamp(0.0, 1.0),
                                child: Transform.rotate(
                                  angle: -0.12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.greenAccent,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.black45,
                                    ),
                                    child: const Text(
                                      'LIKE ❤️',
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (swipeOffset < -20)
                            Positioned(
                              top: 35,
                              right: 25,
                              child: Opacity(
                                opacity: (-swipeOffset / 180).clamp(0.0, 1.0),
                                child: Transform.rotate(
                                  angle: 0.12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.redAccent,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.black45,
                                    ),
                                    child: const Text(
                                      'SKIP ✕',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          profile.imageUrl.isNotEmpty
                              ? Image.network(
                                  profile.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFFE8E5FF),
                                            Color(0xFFD6D0FF),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.person_rounded,
                                          size: 110,
                                          color: Color(0xFF6C5CE7),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFE8E5FF),
                                        Color(0xFFD6D0FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.person_rounded,
                                      size: 110,
                                      color: Color(0xFF6C5CE7),
                                    ),
                                  ),
                                ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black87,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.48, 1],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 25,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${profile.name}, ${profile.age}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 29,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (incomingSuperLikeIds.contains(
                                      profile.id,
                                    )) ...[
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFFFC107),
                                        size: 28,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    if (profile.city.isNotEmpty) ...[
                                      const Icon(
                                        Icons.location_on,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        profile.city,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                    if (profile.city.isNotEmpty &&
                                        profile.distanceKm != null)
                                      const SizedBox(width: 12),
                                    if (profile.distanceKm != null) ...[
                                      const Icon(
                                        Icons.near_me,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${profile.distanceKm!.toStringAsFixed(1)} km away',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  profile.bio,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  children: profile.interests
                                      .map(
                                        (item) => Chip(
                                          label: Text(
                                            item,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionButton(
                  icon: Icons.undo_rounded,
                  color: skippedProfiles.isEmpty
                      ? Colors.grey
                      : const Color(0xFFFFA726),
                  onTap: skippedProfiles.isEmpty ? () {} : rewind,
                ),
                const SizedBox(width: 20),
                _actionButton(
                  icon: Icons.close,
                  color: Colors.red,
                  onTap: skip,
                ),
                const SizedBox(width: 18),
                _actionButton(
                  icon: Icons.star_rounded,
                  color: const Color(0xFFFFC107),
                  onTap: superLike,
                ),
                const SizedBox(width: 18),
                _actionButton(
                  icon: Icons.favorite,
                  color: const Color(0xFF6C5CE7),
                  size: 70,
                  onTap: like,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 60,
  }) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: color.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.12),
        highlightColor: color.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: size * .48,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PROFILE DETAIL
// ============================================================

class ProfileDetailScreen extends StatelessWidget {
  final Profile profile;

  const ProfileDetailScreen({
    super.key,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: const Color(0xFF6C5CE7),
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                profile.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.person, size: 100),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${profile.name}, ${profile.age}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFF6C5CE7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        profile.city,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'About',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.bio,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    'Interests',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: profile.interests
                        .map((item) => Chip(label: Text(item)))
                        .toList(),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final user =
                            Supabase.instance.client.auth.currentUser;

                        if (user == null || profile.id == null) return;

                        try {
                          await Supabase.instance.client.from('likes').insert({
                            'user_id': user.id,
                            'liked_user_id': profile.id,
                          });

                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('You liked ${profile.name}!'),
                              duration: const Duration(milliseconds: 900),
                            ),
                          );

                          Navigator.pop(context);
                        } on PostgrestException catch (e) {
                          if (!context.mounted) return;

                          if (e.code == '23505') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'You already liked this profile.',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message)),
                            );
                          }
                        } catch (_) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to like profile.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.favorite),
                      label: const Text('LIKE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final user = Supabase.instance.client.auth.currentUser;

                  if (user == null || profile.id == null) return;

                  try {
                    await Supabase.instance.client.from('blocks').insert({
                      'blocker_id': user.id,
                      'blocked_id': profile.id,
                    });

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile blocked.'),
                      ),
                    );

                    Navigator.pop(context);
                  } on PostgrestException catch (e) {
                    if (!context.mounted) return;

                    if (e.code == '23505') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('This profile is already blocked.'),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  } catch (_) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to block profile.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.block),
                label: const Text('BLOCK'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final user = Supabase.instance.client.auth.currentUser;

                  if (user == null || profile.id == null) return;

                  final reasonController = TextEditingController();
                  String selectedReason = 'Inappropriate behavior';

                  final shouldReport = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return StatefulBuilder(
                        builder: (context, setDialogState) {
                          return AlertDialog(
                            title: const Text('Report Profile'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: selectedReason,
                                  decoration: const InputDecoration(
                                    labelText: 'Reason',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Inappropriate behavior',
                                      child: Text('Inappropriate behavior'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Fake profile',
                                      child: Text('Fake profile'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Harassment',
                                      child: Text('Harassment'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Spam',
                                      child: Text('Spam'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Other',
                                      child: Text('Other'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setDialogState(() {
                                        selectedReason = value;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: reasonController,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Details (optional)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext, false);
                                },
                                child: const Text('CANCEL'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext, true);
                                },
                                child: const Text('REPORT'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );

                  final details = reasonController.text.trim();
                  reasonController.dispose();

                  if (shouldReport != true) return;

                  try {
                    await Supabase.instance.client.from('reports').insert({
                      'reporter_id': user.id,
                      'reported_user_id': profile.id,
                      'reason': selectedReason,
                      'details': details,
                    });

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report submitted.'),
                      ),
                    );
                  } on PostgrestException catch (e) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  } catch (_) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to submit report.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('REPORT'),
              ),
            ),

                ],
              ),
            ),
          ),
        ],
      ),
    );

  }

}

// ============================================================
// MATCHES
// ============================================================

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  List<Profile> matches = [];
  bool isLoading = true;

  RealtimeChannel? _matchesChannel;

  @override
  void initState() {
    super.initState();
    loadMatches();
    _subscribeToMatches();
  }

  void _subscribeToMatches() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    _matchesChannel = Supabase.instance.client
        .channel('matches-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) async {
            await loadMatches();
            await _showNewMatchNotification(payload);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'matched_user_id',
            value: user.id,
          ),
          callback: (payload) async {
            await loadMatches();
            await _showNewMatchNotification(payload);
          },
        )
        .subscribe();
  }

  Future<void> loadMatches() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('matches')
          .select('user_id, matched_user_id')
          .or('user_id.eq.${user.id},matched_user_id.eq.${user.id}');

      final matchIds = <String>[];

      for (final item in response as List) {
        final matchUserId = item['user_id'] == user.id
            ? item['matched_user_id'] as String
            : item['user_id'] as String;

        matchIds.add(matchUserId);
      }
        final blockedResponse = await Supabase.instance.client
            .from('blocks')
            .select('blocker_id, blocked_id')
            .or('blocker_id.eq.${user.id},blocked_id.eq.${user.id}');

        final blockedIds = <String>{};

        for (final item in blockedResponse as List) {
          final blockerId = item['blocker_id'] as String;
          final blockedId = item['blocked_id'] as String;

          if (blockerId == user.id) {
            blockedIds.add(blockedId);
          } else if (blockedId == user.id) {
            blockedIds.add(blockerId);
          }
        }

        matchIds.removeWhere((id) => blockedIds.contains(id));


      if (matchIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          matches = [];
          isLoading = false;
        });
        return;
      }

      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, name, bio, birth_date, city, avatar_url')
          .inFilter('id', matchIds);

      final loadedMatches = <Profile>[];

      for (final item in profileResponse as List) {
        final birthDateText = item['birth_date'] as String?;
        final birthDate = birthDateText != null
            ? DateTime.tryParse(birthDateText)
            : null;

        if (birthDate == null) continue;

        final now = DateTime.now();
        var age = now.year - birthDate.year;

        if (now.month < birthDate.month ||
            (now.month == birthDate.month && now.day < birthDate.day)) {
          age--;
        }

        loadedMatches.add(
          Profile(
            id: item['id'] as String,
            name: item['name'] as String? ?? 'Unknown',
            age: age,
            city: item['city'] as String? ?? '',
            bio: item['bio'] as String? ?? '',
            imageUrl: item['avatar_url'] as String? ?? '',
            interests: const [],
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        matches = loadedMatches;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load matches.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_matchesChannel != null) {
      Supabase.instance.client.removeChannel(_matchesChannel!);
    }

    super.dispose();
  }

  Future<void> _showNewMatchNotification(
    PostgresChangePayload payload,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || !mounted) return;

    final record = payload.newRecord;

    final userId = record['user_id'] as String?;
    final matchedUserId = record['matched_user_id'] as String?;

    if (userId == null || matchedUserId == null) return;

    final otherUserId =
        userId == user.id ? matchedUserId : userId;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, name, bio, birth_date, city, avatar_url')
          .eq('id', otherUserId)
          .maybeSingle();

      if (response == null || !mounted) return;

      final birthDateText = response['birth_date'] as String?;
      final birthDate = birthDateText != null
          ? DateTime.tryParse(birthDateText)
          : null;

      if (birthDate == null) return;

      final now = DateTime.now();
      var age = now.year - birthDate.year;

      if (now.month < birthDate.month ||
          (now.month == birthDate.month &&
              now.day < birthDate.day)) {
        age--;
      }

      final profile = Profile(
        id: response['id'] as String,
        name: response['name'] as String? ?? 'Unknown',
        age: age,
        city: response['city'] as String? ?? '',
        bio: response['bio'] as String? ?? '',
        imageUrl: response['avatar_url'] as String? ?? '',
        interests: const [],
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              24,
              28,
              24,
              20,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "IT'S A MATCH! 🎉",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6C5CE7),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You both liked each other.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 22),
                CircleAvatar(
                  radius: 52,
                  backgroundImage: profile.imageUrl.isNotEmpty
                      ? NetworkImage(profile.imageUrl)
                      : null,
                  child: profile.imageUrl.isEmpty
                      ? const Icon(
                          Icons.person,
                          size: 52,
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                Text(
                  '${profile.name}, ${profile.age}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (profile.city.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.city,
                    style: const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            profile: profile,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'CHAT NOW',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text(
                      'KEEP DISCOVERING',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      // Match exists even if the popup profile cannot be loaded.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (matches.isEmpty) {
      return const Center(
        child: Text(
          'No matches yet.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Matches',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: matches.length,
        itemBuilder: (context, index) {
          return matchCard(context, matches[index]);
        },
      ),
    );
  }

  Widget matchCard(BuildContext context, Profile profile) {
    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: CircleAvatar(
          radius: 30,
          backgroundImage: profile.imageUrl.isNotEmpty
              ? NetworkImage(profile.imageUrl)
              : null,
          child: profile.imageUrl.isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(
          '${profile.name}, ${profile.age}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(profile.city),
        trailing: IconButton(
          icon: const Icon(
            Icons.chat_bubble,
            color: Color(0xFF6C5CE7),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(profile: profile),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<Map<String, dynamic>> chats = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadChats();
  }

  Future<void> loadChats() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    try {
      final blockedResponse = await Supabase.instance.client
          .from('blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.${user.id},blocked_id.eq.${user.id}');

      final blockedIds = <String>{};

      for (final item in blockedResponse as List) {
        final blockerId = item['blocker_id'] as String;
        final blockedId = item['blocked_id'] as String;

        if (blockerId == user.id) {
          blockedIds.add(blockedId);
        } else if (blockedId == user.id) {
          blockedIds.add(blockerId);
        }
      }

      final matchResponse = await Supabase.instance.client
          .from('matches')
          .select('id, user_id, matched_user_id, created_at')
          .or(
            'user_id.eq.${user.id},matched_user_id.eq.${user.id}',
          )
          .order('created_at', ascending: false);

      final matchIds = <String>[];
      final otherUserIds = <String>[];
      final matchRows = <Map<String, dynamic>>[];

      for (final item in matchResponse as List) {
        final row = Map<String, dynamic>.from(item);

        final otherUserId = row['user_id'] == user.id
            ? row['matched_user_id'] as String
            : row['user_id'] as String;

        if (blockedIds.contains(otherUserId)) continue;

        matchIds.add(row['id'] as String);
        otherUserIds.add(otherUserId);
        matchRows.add(row);
      }

      if (matchRows.isEmpty) {
        if (!mounted) return;

        setState(() {
          chats = [];
          isLoading = false;
        });
        return;
      }

      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, name, bio, birth_date, city, avatar_url')
          .inFilter('id', otherUserIds);

      final profileMap = <String, Map<String, dynamic>>{};

      for (final item in profileResponse as List) {
        final profile = Map<String, dynamic>.from(item);
        profileMap[profile['id'] as String] = profile;
      }

      final messageResponse = await Supabase.instance.client
          .from('messages')
          .select('match_id, sender_id, message, created_at, read_at')
          .inFilter('match_id', matchIds)
          .order('created_at', ascending: false);

      final lastMessageMap = <String, Map<String, dynamic>>{};
      final unreadCountMap = <String, int>{};

      for (final item in messageResponse as List) {
        final message = Map<String, dynamic>.from(item);
        final id = message['match_id'] as String;

        if (!lastMessageMap.containsKey(id)) {
          lastMessageMap[id] = message;
        }

        final senderId = message['sender_id']?.toString();
        final readAt = message['read_at'];

        if (senderId != user.id && readAt == null) {
          unreadCountMap[id] = (unreadCountMap[id] ?? 0) + 1;
        }
      }

      final loadedChats = <Map<String, dynamic>>[];

      for (final match in matchRows) {
        final matchId = match['id'] as String;

        final otherUserId = match['user_id'] == user.id
            ? match['matched_user_id'] as String
            : match['user_id'] as String;

        final profile = profileMap[otherUserId];

        if (profile == null) continue;

        loadedChats.add({
          'match_id': matchId,
          'profile': profile,
          'last_message': lastMessageMap[matchId]?['message'] as String?,
          'last_message_at':
              lastMessageMap[matchId]?['created_at'] as String?,
          'unread_count': unreadCountMap[matchId] ?? 0,
        });
      }

      if (!mounted) return;

      setState(() {
        chats = loadedChats;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load chats.'),
        ),
      );
    }
  }

  String formatChatTime(String value) {
    final date = DateTime.tryParse(value)?.toLocal();

    if (date == null) return '';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    if (difference.inDays < 7) {
      const days = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ];
      return days[date.weekday - 1];
    }

    return '${date.day}/${date.month}';
  }

  Profile profileFromMap(Map<String, dynamic> item) {
    final birthDateText = item['birth_date'] as String?;
    final birthDate = birthDateText != null
        ? DateTime.tryParse(birthDateText)
        : null;

    var age = 0;

    if (birthDate != null) {
      final now = DateTime.now();
      age = now.year - birthDate.year;

      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
    }

    return Profile(
      id: item['id'] as String,
      name: item['name'] as String? ?? 'Unknown',
      age: age,
      city: item['city'] as String? ?? '',
      bio: item['bio'] as String? ?? '',
      imageUrl: item['avatar_url'] as String? ?? '',
      interests: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (chats.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Chats',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Text(
            'No chats yet.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadChats,
        child: ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final item = chats[index];
            final profile = profileFromMap(
              item['profile'] as Map<String, dynamic>,
            );

            final lastMessage = item['last_message'] as String?;
            final unreadCount = item['unread_count'] as int? ?? 0;
            final lastMessageAt = item['last_message_at'] as String?;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: CircleAvatar(
                radius: 28,
                backgroundImage: profile.imageUrl.isNotEmpty
                    ? NetworkImage(profile.imageUrl)
                    : null,
                child: profile.imageUrl.isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${profile.name}${profile.age > 0 ? ', ${profile.age}' : ''}',
                      style: TextStyle(
                        fontWeight:
                            unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (lastMessageAt != null)
                    Text(
                      formatChatTime(lastMessageAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: unreadCount > 0
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade600,
                        fontWeight:
                            unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      lastMessage == null || lastMessage.isEmpty
                          ? 'No messages yet.'
                          : lastMessage.startsWith('image:')
                              ? '📷 Photo'
                              : lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: unreadCount > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      profile: profile,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// CHAT
// ============================================================

class ChatScreen extends StatefulWidget {
  final Profile profile;

  const ChatScreen({
    super.key,
    required this.profile,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final scrollController = ScrollController();
  final messages = <Map<String, dynamic>>[];

  String? matchId;
  RealtimeChannel? messagesChannel;
  RealtimeChannel? typingChannel;
  bool isLoading = true;
  bool isSendingImage = false;
  bool showEmojiPicker = false;
  bool isOtherUserTyping = false;

  final emojis = const [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '😂',
    '🤣',
    '😊',
    '😇',
    '🙂',
    '🙃',
    '😉',
    '😌',
    '😍',
    '🥰',
    '😘',
    '😎',
    '🤩',
    '🤔',
    '😅',
    '😢',
    '😭',
    '😡',
    '😱',
    '👍',
    '👎',
    '❤️',
    '💕',
    '🔥',
    '🎉',
    '🙏',
  ];

  @override
  void initState() {
    super.initState();
    loadChat();
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    _setTyping(false);
    messageController.dispose();
    scrollController.dispose();
    messagesChannel?.unsubscribe();
    typingChannel?.unsubscribe();
    super.dispose();
  }

  void scrollToLatest({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;

      final target = scrollController.position.maxScrollExtent;

      if (animated) {
        scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        scrollController.jumpTo(target);
      }
    });
  }

  Future<void> loadChat() async {
    final user = Supabase.instance.client.auth.currentUser;
    final otherUserId = widget.profile.id;

    if (user == null || otherUserId == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('matches')
          .select('id, user_id, matched_user_id')
          .or(
            'and(user_id.eq.${user.id},matched_user_id.eq.$otherUserId),'
            'and(user_id.eq.$otherUserId,matched_user_id.eq.${user.id})',
          )
          .maybeSingle();

      if (response == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      matchId = response['id'] as String;

      typingChannel = Supabase.instance.client
          .channel('typing-$matchId')
          .onPresenceSync((payload) {
            if (!mounted) return;

            final currentUserId =
                Supabase.instance.client.auth.currentUser?.id;

            if (currentUserId == null) return;

            final presenceState = typingChannel!.presenceState();

            var otherUserTyping = false;

            for (final state in presenceState) {
              for (final presence in state.presences) {
                final data = presence.payload;

                if (data['user_id']?.toString() != currentUserId &&
                    data['typing'] == true) {
                  otherUserTyping = true;
                }
              }
            }

            if (isOtherUserTyping != otherUserTyping) {
              setState(() {
                isOtherUserTyping = otherUserTyping;
              });
            }
          })
          .subscribe((status, error) async {
            if (status == RealtimeSubscribeStatus.subscribed) {
              await _setTyping(false);
            }
          });

      messagesChannel = Supabase.instance.client
          .channel('messages-$matchId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: matchId!,
            ),
            callback: (payload) async {

              final newMessage =
                  Map<String, dynamic>.from(payload.newRecord);

              final messageId = newMessage['id'];

              if (messages.any((item) => item['id'] == messageId)) {
                return;
              }

              setState(() {
                messages.add(newMessage);
              });

              scrollToLatest();

              final currentUser =
                  Supabase.instance.client.auth.currentUser;

              if (currentUser != null &&
                  newMessage['sender_id']?.toString() != currentUser.id) {
                try {
                  await Supabase.instance.client
                      .from('messages')
                      .update({
                    'delivered_at':
                        DateTime.now().toUtc().toIso8601String(),
                  })
                      .eq('id', messageId)
                      .isFilter('delivered_at', null);
                } catch (_) {
                  // Delivery status should not interrupt the chat.
                }

                await markMessagesAsRead();
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: matchId!,
            ),
            callback: (payload) {

              final updatedMessage =
                  Map<String, dynamic>.from(payload.newRecord);
              final messageId = updatedMessage['id'];

              final index = messages.indexWhere(
                (item) => item['id'] == messageId,
              );

              if (index == -1) return;

              setState(() {
                messages[index] = updatedMessage;
              });
            },
          )
          .subscribe();

      final messageResponse = await Supabase.instance.client
          .from('messages')
          .select('id, sender_id, message, created_at, delivered_at, read_at')
          .eq('match_id', matchId!)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        messages
          ..clear()
          ..addAll(
            (messageResponse as List)
                .map((item) => Map<String, dynamic>.from(item)),
          );
        isLoading = false;
      });

      scrollToLatest(animated: false);

      await markMessagesAsRead();
    } catch (_) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load chat.'),
        ),
      );
    }
  }

  Future<void> markMessagesAsRead() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || matchId == null) return;

    try {
      await Supabase.instance.client
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('match_id', matchId!)
          .neq('sender_id', user.id)
          .isFilter('read_at', null);
    } catch (_) {
      // Marking messages as read should not interrupt the chat.
    }
  }

  Timer? typingTimer;

  void _handleTypingChanged(String value) {
    typingTimer?.cancel();

    if (value.trim().isEmpty) {
      _setTyping(false);
      return;
    }

    _setTyping(true);

    typingTimer = Timer(const Duration(seconds: 2), () {
      _setTyping(false);
    });
  }

  Future<void> _setTyping(bool typing) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || typingChannel == null) return;

    try {
      await typingChannel!.track({
        'user_id': user.id,
        'typing': typing,
      });
    } catch (_) {
      // Typing status is optional and should not interrupt the chat.
    }
  }

  Future<void> blockUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    final blockedUserId = widget.profile.id;

    if (user == null || blockedUserId == null) return;

    try {
      await Supabase.instance.client.from('blocks').upsert({
        'blocker_id': user.id,
        'blocked_id': blockedUserId,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User blocked.'),
        ),
      );

      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to block user. Please try again.'),
        ),
      );
    }
  }

  Future<void> unmatchUser() async {
    if (matchId == null) return;

    try {
      await Supabase.instance.client
          .from('matches')
          .delete()
          .eq('id', matchId!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Match removed.'),
        ),
      );

      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to remove match. Please try again.'),
        ),
      );
    }
  }

  Future<void> reportUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    final reportedUserId = widget.profile.id;

    if (user == null || reportedUserId == null) return;

    String selectedReason = 'Spam or scam';
    final detailsController = TextEditingController();

    final shouldReport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Report user'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Spam or scam',
                          child: Text('Spam or scam'),
                        ),
                        DropdownMenuItem(
                          value: 'Harassment',
                          child: Text('Harassment'),
                        ),
                        DropdownMenuItem(
                          value: 'Inappropriate behavior',
                          child: Text('Inappropriate behavior'),
                        ),
                        DropdownMenuItem(
                          value: 'Fake profile',
                          child: Text('Fake profile'),
                        ),
                        DropdownMenuItem(
                          value: 'Other',
                          child: Text('Other'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedReason = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Details (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('REPORT'),
                ),
              ],
            );
          },
        );
      },
    );

    final details = detailsController.text.trim();
    detailsController.dispose();

    if (shouldReport != true) return;

    try {
      await Supabase.instance.client.from('reports').insert({
        'reporter_id': user.id,
        'reported_user_id': reportedUserId,
        'reason': selectedReason,
        'details': details,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit report. Please try again.'),
        ),
      );
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    final user = Supabase.instance.client.auth.currentUser;

    if (text.isEmpty || user == null || matchId == null) return;

    try {
      await Supabase.instance.client.from('messages').insert({
        'match_id': matchId,
        'sender_id': user.id,
        'message': text,
      });

      messageController.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message.'),
        ),
      );
    }
  }

  Future<void> sendImage() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || matchId == null || isSendingImage) return;

    try {
      setState(() {
        isSendingImage = true;
        showEmojiPicker = false;
      });

      final picker = ImagePicker();

      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );

      if (image == null) {
        if (mounted) {
          setState(() => isSendingImage = false);
        }
        return;
      }

      final bytes = await image.readAsBytes();
      final extension =
          image.name.contains('.') ? image.name.split('.').last : 'jpg';

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.$extension';

      final filePath = '${user.id}/$fileName';

      await Supabase.instance.client.storage
          .from('chat-images')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(extension),
              upsert: false,
            ),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('chat-images')
          .getPublicUrl(filePath);

      await Supabase.instance.client.from('messages').insert({
        'match_id': matchId,
        'sender_id': user.id,
        'message': 'image:$imageUrl',
      });
    } on StorageException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send image.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSendingImage = false);
      }
    }
  }

  String _contentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  void addEmoji(String emoji) {
    final text = messageController.text;
    final selection = messageController.selection;

    if (!selection.isValid) {
      messageController.text = '$text$emoji';
      messageController.selection = TextSelection.collapsed(
        offset: messageController.text.length,
      );
      return;
    }

    final start = selection.start;
    final end = selection.end;

    final newText = text.replaceRange(
      start,
      end,
      emoji,
    );

    messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + emoji.length,
      ),
    );
  }

  bool isImageMessage(String text) {
    return text.startsWith('image:');
  }

  String imageUrlFromMessage(String text) {
    return text.substring(6);
  }

  String formatTime(dynamic value) {
    if (value == null) return '';

    final date = DateTime.tryParse(value.toString());

    if (date == null) return '';

    final local = date.toLocal();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  Widget buildMessageBubble(
    Map<String, dynamic> item,
    String? currentUserId,
  ) {
    final senderId = item['sender_id']?.toString();
    final isMe = senderId != null && senderId == currentUserId;
    final text = item['message'] as String? ?? '';
    final isImage = isImageMessage(text);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          left: isMe ? 60 : 8,
          right: isMe ? 8 : 60,
          bottom: 8,
        ),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFF6C5CE7)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: isImage
            ? GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        body: Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Image.network(
                              imageUrlFromMessage(text),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                      imageUrlFromMessage(text),
                    width: 230,
                    height: 230,
                    fit: BoxFit.cover,
                    loadingBuilder:
                        (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;

                      return const SizedBox(
                      width: 230,
                      height: 230,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        width: 230,
                        height: 230,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            : Column(
                crossAxisAlignment:
                    isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatTime(item['created_at']),
                        style: TextStyle(
                          color: isMe
                              ? Colors.white70
                              : Colors.black45,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          item['read_at'] != null
                              ? Icons.done_all
                              : item['delivered_at'] != null
                                  ? Icons.done_all
                                  : Icons.done,
                          size: 14,
                          color: item['read_at'] != null
                              ? Colors.lightBlueAccent
                              : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget buildEmojiPicker() {
    return Container(
      height: 230,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: emojis.length,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () => addEmoji(emojis[index]),
            child: Center(
              child: Text(
                emojis[index],
                style: const TextStyle(fontSize: 27),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileDetailScreen(
                      profile: widget.profile,
                    ),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage: widget.profile.imageUrl.isNotEmpty
                    ? NetworkImage(widget.profile.imageUrl)
                    : null,
                child: widget.profile.imageUrl.isEmpty
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.profile.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'report') {
                await reportUser();
              } else if (value == 'unmatch') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Unmatch user?'),
                      content: Text(
                        'Your match and chat history with ${widget.profile.name} will be removed.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Unmatch'),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed == true) {
                  await unmatchUser();
                }
              } else if (value == 'block') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Block user?'),
                      content: Text(
                        'You will no longer see ${widget.profile.name} in Discover, Matches, or Chats.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Block'),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed == true) {
                  await blockUser();
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'unmatch',
                child: Row(
                  children: [
                    Icon(Icons.heart_broken_outlined),
                    SizedBox(width: 10),
                    Text('Unmatch'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block),
                    SizedBox(width: 10),
                    Text('Block user'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined),
                    SizedBox(width: 10),
                    Text('Report user'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet.\nSay hello 👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          reverse: false,
                          padding: const EdgeInsets.fromLTRB(
                            12,
                            16,
                            12,
                            12,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];

                            return buildMessageBubble(
                              message,
                              currentUserId,
                            );
                          },
                        ),
                ),
                if (isOtherUserTyping)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${widget.profile.name} is typing...',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                if (isSendingImage)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Sending image...'),
                      ],
                    ),
                  ),
                if (showEmojiPicker) buildEmojiPicker(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      8,
                      6,
                      8,
                      8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Emoji',
                          onPressed: () {
                            setState(() {
                              showEmojiPicker = !showEmojiPicker;
                            });
                          },
                          icon: Icon(
                            showEmojiPicker
                                ? Icons.keyboard
                                : Icons.emoji_emotions_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Send image',
                          onPressed:
                              isSendingImage ? null : sendImage,
                          icon: const Icon(
                            Icons.image_outlined,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            onChanged: _handleTypingChanged,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onTap: () {
                              if (showEmojiPicker) {
                                setState(() {
                                  showEmojiPicker = false;
                                });
                              }
                            },
                            onSubmitted: (_) => sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CircleAvatar(
                          backgroundColor:
                              const Color(0xFF6C5CE7),
                          child: IconButton(
                            onPressed: sendMessage,
                            color: Colors.white,
                            icon: const Icon(Icons.send),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => BlockedUsersScreenState();
}

class BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> blockedUsers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadBlockedUsers();
  }

  Future<void> loadBlockedUsers() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      final blockResponse = await Supabase.instance.client
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', user.id);

      final blockedIds = (blockResponse as List)
          .map((item) => item['blocked_id'] as String)
          .toList();

      if (blockedIds.isEmpty) {
        if (!mounted) return;

        setState(() {
          blockedUsers = [];
          isLoading = false;
        });

        return;
      }

      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, name, city, avatar_url')
          .inFilter('id', blockedIds);

      if (!mounted) return;

      setState(() {
        blockedUsers = (profileResponse as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        isLoading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load blocked users.'),
        ),
      );
    }
  }

  Future<void> unblockUser(String blockedId) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('blocks')
          .delete()
          .eq('blocker_id', user.id)
          .eq('blocked_id', blockedId);

      if (!mounted) return;

      await loadBlockedUsers();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User unblocked.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to unblock user.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blocked Users',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : blockedUsers.isEmpty
              ? const Center(
                  child: Text('You have not blocked anyone.'),
                )
              : ListView.separated(
                  itemCount: blockedUsers.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = blockedUsers[index];
                    final name = user['name'] as String? ?? 'Unknown';
                    final city = user['city'] as String? ?? '';
                    final avatarUrl = user['avatar_url'] as String?;

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: city.isEmpty ? null : Text(city),
                      trailing: OutlinedButton(
                        onPressed: () => unblockUser(user['id'] as String),
                        child: const Text('UNBLOCK'),
                      ),
                    );
                  },
                ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _notificationLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _notificationLoading = false;
        });
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('notification_settings')
          .select('enabled')
          .eq('user_id', user.id)
          .maybeSingle();

      bool enabled = true;

      if (response != null) {
        enabled = response['enabled'] as bool? ?? true;
      } else {
        await Supabase.instance.client
            .from('notification_settings')
            .insert({
          'user_id': user.id,
          'enabled': true,
        });
      }

      if (!mounted) return;

      setState(() {
        _notificationsEnabled = enabled;
        _notificationLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _notificationLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal memuat pengaturan notifikasi.'),
        ),
      );
    }
  }

  Future<void> _updateNotificationSetting(bool value) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final previousValue = _notificationsEnabled;

    setState(() {
      _notificationsEnabled = value;
    });

    try {
      if (value) {
        final permissionGranted =
            await NotificationService.instance.requestPermission();

        if (!permissionGranted) {
          if (!mounted) return;

          setState(() {
            _notificationsEnabled = false;
          });

          await Supabase.instance.client
              .from('notification_settings')
              .upsert({
            'user_id': user.id,
            'enabled': false,
            'updated_at': DateTime.now().toIso8601String(),
          });

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Izin notifikasi belum diberikan.',
              ),
            ),
          );

          return;
        }
      }

      await Supabase.instance.client
          .from('notification_settings')
          .upsert({
        'user_id': user.id,
        'enabled': value,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (value) {
        await NotificationService.instance.showTestNotification();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _notificationsEnabled = previousValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gagal menyimpan pengaturan notifikasi.',
          ),
        ),
      );
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();

      if (!context.mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logout failed. Please try again.'),
        ),
      );
    }
  }

  void showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report a user'),
        content: const Text(
          'Choose this option if a profile violates Go Fren community rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report submitted.'),
                ),
              );
            },
            child: const Text('REPORT'),
          ),
        ],
      ),
    );
  }

  void showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block user'),
        content: const Text(
          'Blocked profiles will no longer appear in your discovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User blocked.'),
                ),
              );
            },
            child: const Text('BLOCK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: FutureBuilder(
              future: Supabase.instance.client
                  .from("profiles")
                  .select("avatar_url")
                  .eq("id", Supabase.instance.client.auth.currentUser!.id)
                  .maybeSingle(),
              builder: (context, snapshot) {
                final avatarUrl = snapshot.data?["avatar_url"]?.toString() ?? "";

                if (avatarUrl.isNotEmpty) {
                  return CircleAvatar(
                    backgroundImage: NetworkImage(avatarUrl),
                  );
                }

                return const CircleAvatar(
                  backgroundColor: Color(0xFFE8E5FF),
                  child: Icon(
                    Icons.person,
                    color: Color(0xFF6C5CE7),
                  ),
                );
              },
            ),
            title: const Text(
              'My Profile',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Edit your profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(
              _notificationLoading
                  ? 'Loading...'
                  : _notificationsEnabled
                      ? 'Notifications are enabled'
                      : 'Notifications are disabled',
            ),
            trailing: _notificationLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : Switch(
                    value: _notificationsEnabled,
                    onChanged: _updateNotificationSetting,
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen())); },
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Block a user'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BlockedUsersScreen(),
                ),
              );
          },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Report a user'),
            onTap: () => showReportDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
            ),
            title: const Text(
              'Log out',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => logout(context),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'Go Fren v1.0.0',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// MY PROFILE
// ============================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('name, city, bio, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        profile = response;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load profile.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile?['avatar_url']?.toString() ?? '';
    final name = profile?['name']?.toString() ?? '';
    final city = profile?['city']?.toString() ?? '';
    final bio = profile?['bio']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: loadProfile,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: CircleAvatar(
                      radius: 65,
                      backgroundColor: const Color(0xFFE8E5FF),
                      backgroundImage: avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 65,
                              color: Color(0xFF6C5CE7),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      name.isEmpty ? 'Your Name' : name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (city.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            city,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Text(
                    'About me',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    bio.isEmpty ? 'No bio yet.' : bio,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        );

                        if (mounted) {
                          loadProfile();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('EDIT PROFILE'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// EDIT PROFILE
// ============================================================


class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() =>
      PrivacySettingsScreenState();
}

class PrivacySettingsScreenState
    extends State<PrivacySettingsScreen> {
  bool showProfile = true;
  bool showCity = true;
  bool allowNewMatches = true;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('privacy_settings')
          .select(
            'show_profile, show_city, allow_new_matches',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        setState(() {
          showProfile = response['show_profile'] as bool? ?? true;
          showCity = response['show_city'] as bool? ?? true;
          allowNewMatches =
              response['allow_new_matches'] as bool? ?? true;
        });
      } else {
        await Supabase.instance.client
            .from('privacy_settings')
            .insert({
          'user_id': user.id,
        });
      }

      setState(() {
        isLoading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load privacy settings.'),
        ),
      );
    }
  }

  Future<void> updateSetting({
    required String column,
    required bool value,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('privacy_settings')
          .upsert({
        'user_id': user.id,
        column: value,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      setState(() {
        if (column == 'show_profile') {
          showProfile = value;
        } else if (column == 'show_city') {
          showCity = value;
        } else if (column == 'allow_new_matches') {
          allowNewMatches = value;
        }
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update privacy setting.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Show my profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Allow your profile to appear in Discovery.',
                  ),
                  value: showProfile,
                  onChanged: (value) {
                    updateSetting(
                      column: 'show_profile',
                      value: value,
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text(
                    'Show my city',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Show your city on your profile.',
                  ),
                  value: showCity,
                  onChanged: (value) {
                    updateSetting(
                      column: 'show_city',
                      value: value,
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text(
                    'Allow new matches',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Allow other users to match with you.',
                  ),
                  value: allowNewMatches,
                  onChanged: (value) {
                    updateSetting(
                      column: 'allow_new_matches',
                      value: value,
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final nameController = TextEditingController(text: 'Ivan');
  final cityController = TextEditingController(text: 'Jakarta');
  final bioController = TextEditingController(
    text: 'Love meeting new people and having good conversations.',
  );

  XFile? selectedImage;
  String? existingAvatarUrl;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('name, city, bio, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (response == null || !mounted) return;

      setState(() {
        nameController.text = response['name']?.toString() ?? '';
        cityController.text = response['city']?.toString() ?? '';
        bioController.text = response['bio']?.toString() ?? '';
        existingAvatarUrl = response['avatar_url']?.toString();
      });
    } catch (_) {
      // Keep the current form values if loading fails.
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image == null || !mounted) return;

    setState(() {
      selectedImage = image;
    });
  }

  Future<void> saveProfile() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in first.'),
        ),
      );
      return;
    }

    try {
      String? avatarUrl;

      if (selectedImage != null) {
        final filePath = '${user.id}/profile.jpg';

        await Supabase.instance.client.storage
            .from('avatars')
            .upload(
              filePath,
              File(selectedImage!.path),
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );

        avatarUrl = "${Supabase.instance.client.storage.from('avatars').getPublicUrl(filePath)}?v=${DateTime.now().millisecondsSinceEpoch}";
      }

      final data = {
        'name': nameController.text.trim(),
        'city': cityController.text.trim(),
        'bio': bioController.text.trim(),
      };

      if (avatarUrl != null) {
        data['avatar_url'] = avatarUrl;
      }

      await Supabase.instance.client
          .from('profiles')
          .upsert({
            'id': user.id,
            ...data,
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save profile: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    cityController.dispose();
    bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: const Color(0xFFE8E5FF),
                  child: selectedImage != null
                      ? ClipOval(
                          child: Image.file(
                            File(selectedImage!.path),
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        )
                      : existingAvatarUrl != null &&
                              existingAvatarUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                existingAvatarUrl!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 65,
                              color: Color(0xFF6C5CE7),
                            ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C5CE7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: cityController,
            decoration: const InputDecoration(
              labelText: 'City',
              prefixIcon: Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: bioController,
            maxLines: 5,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Bio',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(
                'SAVE PROFILE',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
