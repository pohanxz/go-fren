import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const GoFrenApp());
}

class GoFrenApp extends StatelessWidget {
  const GoFrenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
            borderSide: BorderSide(color: Colors.grey.shade200),
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
      home: const SplashScreen(),
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

  const Profile({
    this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.bio,
    required this.imageUrl,
    required this.interests,
  });
}

const demoProfiles = <Profile>[
  Profile(
    name: 'Sarah',
    age: 24,
    city: 'Jakarta',
    bio: 'Love good conversations, music, food and exploring new places.',
    imageUrl: 'https://i.pravatar.cc/600?img=47',
    interests: ['Music', 'Travel', 'Food'],
  ),
  Profile(
    name: 'Maya',
    age: 26,
    city: 'Depok',
    bio: 'Coffee lover, movie fan and always looking for something new.',
    imageUrl: 'https://i.pravatar.cc/600?img=32',
    interests: ['Movies', 'Food', 'Photography'],
  ),
  Profile(
    name: 'Nadia',
    age: 23,
    city: 'Tangerang',
    bio: 'Gaming, books and weekend adventures.',
    imageUrl: 'https://i.pravatar.cc/600?img=44',
    interests: ['Gaming', 'Books', 'Travel'],
  ),
];

// ============================================================
// SPLASH
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      final session = Supabase.instance.client.auth.currentSession;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => session != null
              ? const MainNavigation()
              : const LoginScreen(),
        ),
      );
    });
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
                  onPressed: () {},
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
      body: pages[currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Matches',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
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

  @override
  void initState() {
    super.initState();
    loadProfiles();
  }

  Future<void> loadProfiles() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => isLoading = false);
      return;
    }

    try {
      final blockedResponse = await Supabase.instance.client
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', user.id);

      final blockedIds = (blockedResponse as List)
          .map((item) => item['blocked_id'] as String)
          .toSet();

      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, name, bio, birth_date, city, avatar_url')
          .neq('id', user.id);

      final loadedProfiles = <Profile>[];

      for (final item in response as List) {
        final id = item['id'] as String;

        if (blockedIds.contains(id)) continue;

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

        loadedProfiles.add(
          Profile(
          id: id,
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
    setState(() {
      if (currentProfile < profiles.length - 1) {
        currentProfile++;
      } else {
        currentProfile = 0;
      }
    });
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (profiles.isEmpty) {
      return const Center(
        child: Text(
          'No profiles available right now.',
          style: TextStyle(fontSize: 16),
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
                  onPressed: () {},
                  icon: const Icon(Icons.tune),
                ),
              ],
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
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        profile.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade300,
                            child: const Icon(
                              Icons.person,
                              size: 100,
                              color: Colors.white,
                            ),
                          );
                        },
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
                            Text(
                              '${profile.name}, ${profile.age}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 29,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
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
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionButton(
                  icon: Icons.close,
                  color: Colors.red,
                  onTap: skip,
                ),
                const SizedBox(width: 35),
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
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
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

  @override
  void initState() {
    super.initState();
    loadMatches();
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
            .select('blocked_id')
            .eq('blocker_id', user.id);

        final blockedIds = (blockedResponse as List)
            .map((item) => item['blocked_id'] as String)
            .toSet();

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

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chats',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundImage:
                  NetworkImage(demoProfiles[0].imageUrl),
            ),
            title: const Text(
              'Sarah',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Nice to meet you!'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    profile: demoProfiles[0],
                  ),
                ),
              );
            },
          ),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundImage:
                  NetworkImage(demoProfiles[1].imageUrl),
            ),
            title: const Text(
              'Maya',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Hey! How are you?'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    profile: demoProfiles[1],
                  ),
                ),
              );
            },
          ),
        ],
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
  final messages = <Map<String, dynamic>>[];

  String? matchId;
  RealtimeChannel? messagesChannel;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadChat();
  }

  @override
  void dispose() {
    messageController.dispose();
    messagesChannel?.unsubscribe();
    super.dispose();
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
            callback: (payload) {
              if (!mounted) return;

              setState(() {
                messages.add(
                  Map<String, dynamic>.from(payload.newRecord),
                );
              });
            },
          )
          .subscribe();

      final messageResponse = await Supabase.instance.client
          .from('messages')
          .select('id, sender_id, message, created_at')
          .eq('match_id', matchId!)
          .order('created_at');

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

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.profile.imageUrl.isNotEmpty
                  ? NetworkImage(widget.profile.imageUrl)
                  : null,
              child: widget.profile.imageUrl.isEmpty
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(widget.profile.name),
          ],
        ),
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
                          child: Text('No messages yet.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final item = messages[index];
                            final isMe =
                                item['sender_id'] == currentUserId;

                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin:
                                    const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? const Color(0xFF6C5CE7)
                                      : Colors.grey.shade200,
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: Text(
                                  item['message'] as String,
                                  style: TextStyle(
                                    color: isMe
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => sendMessage(),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: sendMessage,
                        icon: const Icon(Icons.send),
                      ),
                    ],
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
            trailing: Switch(
              value: true,
              onChanged: (_) {},
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
