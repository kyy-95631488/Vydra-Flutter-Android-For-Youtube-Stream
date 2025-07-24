// home_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vydra/Auth/Service/auth_service.dart';
import 'package:vydra/Home/VideoList/video_list_screen.dart';
import 'package:vydra/Home/AboutApp/about_screen.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final AuthService _authService = AuthService();
  User? _user;
  String? _accessToken;
  String? _latestVersion;
  String? _downloadUrl;
  double _downloadProgress = 0.0;
  bool _isUpdating = false;
  bool _showUpdateDialog = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _user = _authService.currentUser;
    _refreshAccessToken();
    _checkForUpdates();

    _authService.authStateChanges.listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
          if (user != null) {
            _refreshAccessToken();
          } else {
            _accessToken = null;
          }
        });
      }
    });
  }

  Future<void> _refreshAccessToken() async {
    if (_user != null) {
      final token = await _authService.getAccessToken();
      if (mounted) {
        setState(() {
          _accessToken = token;
        });
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Replace with your GitHub repository details
      const repoOwner = 'kyy-95631488';
      const repoName = 'Vydra-Flutter-Android-For-Youtube-Stream';
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final release = jsonDecode(response.body);
        _latestVersion = release['tag_name']?.replaceFirst('v', '');

        if (_latestVersion != null && _latestVersion != currentVersion) {
          _downloadUrl = release['assets']?.isNotEmpty == true
              ? release['assets'][0]['browser_download_url']
              : null;

          final prefs = await SharedPreferences.getInstance();
          final lastPrompt = prefs.getInt('lastUpdatePrompt') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          const threeDaysInMs = 3 * 24 * 60 * 60 * 1000;

          if (_downloadUrl != null) {
            if (lastPrompt == 0 || now - lastPrompt > threeDaysInMs) {
              if (lastPrompt != 0) {
                // Auto-update after 3 days
                await _startUpdate();
              } else {
                setState(() {
                  _showUpdateDialog = true;
                });
                await prefs.setInt('lastUpdatePrompt', now);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
  }

  Future<void> _startUpdate() async {
    if (_downloadUrl == null) return;

    setState(() {
      _isUpdating = true;
      _downloadProgress = 0.0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final response = await http.get(Uri.parse(_downloadUrl!));
      final bytes = response.bodyBytes;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/update.apk');
      await file.writeAsBytes(bytes);

      setState(() {
        _downloadProgress = 0.5; // Simulate download progress
      });

      // Simulate installation progress
      for (double i = 0.5; i <= 1.0; i += 0.1) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          setState(() {
            _downloadProgress = i;
          });
        }
      }

      // Open the downloaded APK file for installation
      if (await canLaunchUrl(Uri.file(file.path))) {
        await launchUrl(Uri.file(file.path));
      }

      await prefs.remove('lastUpdatePrompt');
    } catch (e) {
      print('Error during update: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A1B2E),
                  const Color(0xFF2E2F4A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Background particle effect
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(seconds: 10),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.05),
                          Colors.transparent,
                        ],
                        radius: 1.5,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      // App Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.3),
                                        Colors.white.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.star_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Vydra',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 2.0,
                                    shadows: [
                                      Shadow(
                                        color: Colors.white.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const AboutScreen(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.2),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.info_outline_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (_user != null)
                                  GestureDetector(
                                    onTap: () async {
                                      await _authService.signOut();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.2),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.logout_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Main Content
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SlideTransition(
                                position: _slideAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 24),
                                    padding: const EdgeInsets.all(40),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.2),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                        BoxShadow(
                                          color: Colors.white.withOpacity(0.05),
                                          blurRadius: 20,
                                          offset: const Offset(0, -10),
                                        ),
                                      ],
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.15),
                                          Colors.white.withOpacity(0.05),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: Text(
                                      _user != null
                                          ? 'Welcome, ${_user!.displayName ?? 'Voyager'}!'
                                          : 'Discover Vydra Universe!',
                                      style: TextStyle(
                                        fontFamily: 'Montserrat',
                                        fontSize: 36,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 1.2,
                                        height: 1.3,
                                        shadows: [
                                          Shadow(
                                            color: Colors.white.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 48),
                              ScaleTransition(
                                scale: _scaleAnimation,
                                child: GestureDetector(
                                  onTap: _user == null
                                      ? () async {
                                          final result = await _authService.signInWithGoogle();
                                          if (result != null && mounted) {
                                            setState(() {
                                              _user = result['user'] as User?;
                                              _accessToken = result['accessToken'] as String?;
                                            });
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => VideoListScreen(
                                                  user: _user!,
                                                  accessToken: _accessToken!,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      : () async {
                                          await _refreshAccessToken();
                                          if (_accessToken == null) {
                                            final result = await _authService.signInWithGoogle();
                                            if (result != null && mounted) {
                                              setState(() {
                                                _user = result['user'] as User?;
                                                _accessToken = result['accessToken'] as String?;
                                              });
                                            } else {
                                              return;
                                            }
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => VideoListScreen(
                                                user: _user!,
                                                accessToken: _accessToken!,
                                              ),
                                            ),
                                          );
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF6B46C1),
                                          Color(0xFF3B82F6),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(50),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF6B46C1).withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                        BoxShadow(
                                          color: Colors.white.withOpacity(0.1),
                                          blurRadius: 12,
                                          offset: const Offset(0, -6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.rocket_launch_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          _user == null ? 'Launch with Google' : 'Explore Now',
                                          style: TextStyle(
                                            fontFamily: 'Montserrat',
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 1.0,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black.withOpacity(0.3),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Update Dialog
                if (_showUpdateDialog)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'New Update Available!',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1B2E),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Version $_latestVersion is available. Would you like to update now?',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 16,
                              color: const Color(0xFF2E2F4A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    _showUpdateDialog = false;
                                  });
                                  await _startUpdate();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B46C1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                child: const Text(
                                  'Update Now',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  setState(() {
                                    _showUpdateDialog = false;
                                  });
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setInt('lastUpdatePrompt', DateTime.now().millisecondsSinceEpoch);
                                },
                                child: const Text(
                                  'Later',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 16,
                                    color: Color(0xFF6B46C1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                // Update Progress Dialog
                if (_isUpdating)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Updating...',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1A1B2E),
                            ),
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: Colors.grey[300],
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6B46C1)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(_downloadProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 16,
                              color: const Color(0xFF2E2F4A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}