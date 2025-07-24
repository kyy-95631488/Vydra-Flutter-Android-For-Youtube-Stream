// about_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _cardController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _cardScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Main animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();

    // Card animation controller
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    // Fade animation for title
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Scale animation for main content
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    // Slide animation for cards
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    // Card scale animation
    _cardScaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _cardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1B2E),
          // Adding subtle texture instead of gradient
          image: DecorationImage(
            image: const AssetImage('assets/noise_texture.png'),
            fit: BoxFit.cover,
            opacity: 0.05,
          ),
        ),
        child: Stack(
          children: [
            // Background particles
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(seconds: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.02),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // App Bar
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
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
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: Text(
                                'About Vydra',
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
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Main Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Column(
                          children: [
                            // Creator Card
                            SlideTransition(
                              position: _slideAnimation,
                              child: ScaleTransition(
                                scale: _cardScaleAnimation,
                                child: Container(
                                  padding: const EdgeInsets.all(24),
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
                                  child: Column(
                                    children: [
                                      // Creator Avatar
                                      Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF2D3748), // Solid color instead of gradient
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: Image.network(
                                            'https://hendriansyah-project.vercel.app/_next/image?url=%2Fimages%2Fpribadi-kartun.png&w=384&q=75',
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                              size: 60,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Creator Name
                                      Text(
                                        'Hendriansyah Rizky Setiawan',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 1.2,
                                          shadows: [
                                            Shadow(
                                              color: Colors.white.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center, // Center the name
                                      ),
                                      const SizedBox(height: 8),
                                      // Creator Title
                                      Text(
                                        'Creator of Vydra',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        textAlign: TextAlign.center, // Center the title for consistency
                                      ),
                                      const SizedBox(height: 16),
                                      // Creator Bio
                                      Text(
                                        'Passionate Flutter developer crafting seamless and innovative mobile experiences. Dedicated to pushing the boundaries of app development with a focus on performance and aesthetics.',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 16,
                                          color: Colors.white.withOpacity(0.9),
                                          height: 1.5,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 24),
                                      // Social Links
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: () async {
                                              final url = Uri.parse('https://github.com/kyy-95631488');
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withOpacity(0.2),
                                              ),
                                              child: const Icon(
                                                Icons.code_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          GestureDetector(
                                            onTap: () async {
                                              final url = Uri.parse('https://www.linkedin.com/in/hendriansyah-rizky-setiawan-8b4a68308/');
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withOpacity(0.2),
                                              ),
                                              child: const Icon(
                                                Icons.link_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          GestureDetector(
                                            onTap: () async {
                                              final url = Uri.parse('https://hendriansyah-project.vercel.app/');
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withOpacity(0.2),
                                              ),
                                              child: const Icon(
                                                Icons.web_rounded,
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
                              ),
                            ),
                            const SizedBox(height: 24),
                            // App Info Card
                            SlideTransition(
                              position: _slideAnimation,
                              child: ScaleTransition(
                                scale: _cardScaleAnimation,
                                child: Container(
                                  padding: const EdgeInsets.all(24),
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
                                  child: Column(
                                    children: [
                                      Text(
                                        'About Vydra',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 1.2,
                                        ),
                                        textAlign: TextAlign.center, // Center for consistency
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Vydra is a cutting-edge Flutter application designed to deliver a seamless and immersive experience for streaming and exploring content. Built with passion and innovation, Vydra aims to redefine how users interact with digital media.',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 16,
                                          color: Colors.white.withOpacity(0.9),
                                          height: 1.5,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Version 0.1.0',
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 14,
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                        textAlign: TextAlign.center, // Center for consistency
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}