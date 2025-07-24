// settings_screen.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:vydra/Home/Settings/DownloadManager/download_manager_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:vydra/Home/Settings/CheckUpdate/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  int _pingMs = -1;
  bool _isPinging = false;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  final UpdateService _updateService = UpdateService();
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    initConnectivity();
    _startPingCheck();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> initConnectivity() async {
    late List<ConnectivityResult> result;
    try {
      result = await _connectivity.checkConnectivity();
    } catch (e) {
      return;
    }
    if (!mounted) return;
    setState(() => _connectionStatus = _getPrimaryConnection(result));
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        setState(() => _connectionStatus = _getPrimaryConnection(result));
      },
    );
  }

  ConnectivityResult _getPrimaryConnection(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    } else if (results.contains(ConnectivityResult.none)) {
      return ConnectivityResult.none;
    }
    return ConnectivityResult.none;
  }

  Future<void> _checkPing() async {
    if (_isPinging) return;
    setState(() => _isPinging = true);

    const String pingUrl = 'https://www.youtube.com'; // Using Cloudflare's DNS for reliable ping
    const int maxAttempts = 3;
    const Duration timeout = Duration(seconds: 5);
    List<int> pingResults = [];

    try {
      for (int i = 0; i < maxAttempts; i++) {
        final stopwatch = Stopwatch()..start();
        try {
          final response = await http.get(Uri.parse(pingUrl)).timeout(
            timeout,
            onTimeout: () => http.Response('Timeout', 408),
          );
          stopwatch.stop();
          
          if (response.statusCode == 200) {
            pingResults.add(stopwatch.elapsedMilliseconds);
          }
        } catch (e) {
          // Continue to next attempt on individual failure
          continue;
        }
        // Small delay between attempts
        await Future.delayed(const Duration(milliseconds: 200));
      }

      setState(() {
        if (pingResults.isNotEmpty) {
          // Calculate average ping
          final averagePing = pingResults.reduce((a, b) => a + b) ~/ pingResults.length;
          _pingMs = averagePing;
        } else {
          _pingMs = -1;
        }
        _isPinging = false;
      });
    } catch (e) {
      setState(() {
        _pingMs = -1;
        _isPinging = false;
      });
    }
  }

  void _startPingCheck() {
    _checkPing();
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _checkPing();
    });
  }

  Color _getPingColor() {
    if (_pingMs < 0) return Colors.grey;
    if (_pingMs <= 100) return Colors.green;
    if (_pingMs <= 300) return Colors.yellow;
    return Colors.red;
  }

  String _getConnectionType() {
    switch (_connectionStatus) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile Data';
      case ConnectivityResult.none:
        return 'No Connection';
      default:
        return 'Unknown';
    }
  }

  Future<void> _clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing cache: $e')),
      );
    }
  }

  String _censorEmail(String? email) {
    if (email == null || email.isEmpty) return 'No email available';
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final username = parts[0];
    final domain = parts[1];
    if (username.length <= 3) return email;
    return '${username.substring(0, 3)}****@$domain';
  }

  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    final result = await _updateService.checkForUpdate();
    setState(() => _isCheckingUpdate = false);

    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
      return;
    }

    if (result['hasUpdate']) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Update Available',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          content: Text(
            'A new version (${result['latestVersion']}) is available. Current version: ${result['currentVersion']}. Would you like to update?',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _updateService.launchUpdateUrl(result['releaseUrl']);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening update URL: $e')),
                  );
                }
              },
              child: const Text(
                'Update',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are using the latest version')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // Profile Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    ClipOval(
                      child: user?.photoURL != null
                          ? CachedNetworkImage(
                              imageUrl: user!.photoURL!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              errorWidget: (context, url, error) => const Icon(
                                Icons.person,
                                size: 80,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              size: 80,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'No name available',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _censorEmail(user?.email),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Network Status Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getPingColor(),
                              boxShadow: [
                                BoxShadow(
                                  color: _getPingColor().withOpacity(0.3),
                                  spreadRadius: 5,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Network Status',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Connected via ${_getConnectionType()}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          Text(
                            _pingMs >= 0 ? 'Ping: ${_pingMs}ms' : 'Ping: Checking...',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Download Manager Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ListTile(
                  title: const Text(
                    'Download Manager',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    'View and manage downloaded files',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.download,
                    color: Colors.white,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DownloadManagerScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Check Update Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ListTile(
                  title: const Text(
                    'Check for Update',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    _isCheckingUpdate ? 'Checking for updates...' : 'Check for the latest version',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  trailing: _isCheckingUpdate
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Icon(
                          Icons.update,
                          color: Colors.white,
                        ),
                  onTap: _checkForUpdate,
                ),
              ),
              const SizedBox(height: 16),
              // Clear Cache Button
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ListTile(
                  title: const Text(
                    'Clear Cache',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    'Remove temporary files to free up space',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                  ),
                  onTap: () async {
                    await _clearCache();
                  },
                ),
              ),
              const SizedBox(height: 16),
              // About Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ListTile(
                  title: const Text(
                    'About',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    'Version 0.1.0\nCreated by @kyy-95631488 [ Github ]',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('About Vydra App'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}