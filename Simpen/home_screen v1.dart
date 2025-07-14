// // home_screen.dart
// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:vydra/Auth/Service/auth_service.dart';
// import 'package:particles_fly/particles_fly.dart';

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
//   late AnimationController _controller;
//   late AnimationController _pulseController;
//   late Animation<double> _scaleAnimation;
//   late Animation<double> _fadeAnimation;
//   late Animation<double> _pulseAnimation;
//   final AuthService _authService = AuthService();
//   User? _user;

//   @override
//   void initState() {
//     super.initState();
    
//     // Main animation controller
//     _controller = AnimationController(
//       duration: const Duration(milliseconds: 1200),
//       vsync: this,
//     )..forward();

//     // Pulse animation for button
//     _pulseController = AnimationController(
//       duration: const Duration(milliseconds: 2000),
//       vsync: this,
//     )..repeat(reverse: true);

//     _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
//       CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
//     );

//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
//     );

//     _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
//       CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
//     );

//     // Check current user
//     _user = _authService.currentUser;
    
//     _authService.authStateChanges.listen((User? user) {
//       if (mounted) {
//         setState(() {
//           _user = user;
//         });
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     _pulseController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       extendBodyBehindAppBar: true,
//       appBar: PreferredSize(
//         preferredSize: const Size.fromHeight(70),
//         child: AnimatedBuilder(
//           animation: _fadeAnimation,
//           builder: (context, child) => AppBar(
//             title: Text(
//               'Vydra',
//               style: TextStyle(
//                 fontFamily: 'Poppins',
//                 fontWeight: FontWeight.w700,
//                 fontSize: 24,
//                 color: Colors.white,
//                 shadows: [
//                   Shadow(
//                     color: Colors.black.withOpacity(0.3),
//                     offset: const Offset(0, 2),
//                     blurRadius: 4,
//                   ),
//                 ],
//               ),
//             ),
//             backgroundColor: Colors.transparent,
//             elevation: 0,
//             flexibleSpace: Container(
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [
//                     const Color(0xFF6B48FF).withOpacity(_fadeAnimation.value * 0.7),
//                     const Color(0xFF00DDEB).withOpacity(_fadeAnimation.value * 0.7),
//                   ],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
//               ),
//             ),
//             actions: [
//               if (_user != null)
//                 IconButton(
//                   icon: const Icon(Icons.logout, color: Colors.white, size: 28),
//                   onPressed: () async {
//                     await _authService.signOut();
//                   },
//                 ),
//             ],
//           ),
//         ),
//       ),
//       body: Stack(
//         children: [
//           // Particle background
//           ParticlesFly(
//             height: MediaQuery.of(context).size.height,
//             width: MediaQuery.of(context).size.width,
//             numberOfParticles: 50,
//             speedOfParticles: 1.5,
//             lineColor: Colors.white.withOpacity(0.2),
//             particleColor: Colors.white.withOpacity(0.3),
//           ),
//           // Main content
//           Container(
//             decoration: BoxDecoration(
//               gradient: LinearGradient(
//                 colors: [
//                   const Color(0xFF1A1B2F).withOpacity(0.9),
//                   const Color(0xFF2E2E4A).withOpacity(0.9),
//                 ],
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//               ),
//             ),
//             child: Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   ScaleTransition(
//                     scale: _scaleAnimation,
//                     child: FadeTransition(
//                       opacity: _fadeAnimation,
//                       child: Container(
//                         margin: const EdgeInsets.symmetric(horizontal: 20),
//                         padding: const EdgeInsets.all(24),
//                         decoration: BoxDecoration(
//                           color: Colors.white.withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(20),
//                           border: Border.all(
//                             color: Colors.white.withOpacity(0.2),
//                             width: 1.5,
//                           ),
//                           boxShadow: [
//                             BoxShadow(
//                               color: Colors.black.withOpacity(0.2),
//                               blurRadius: 20,
//                               offset: const Offset(5, 5),
//                             ),
//                             BoxShadow(
//                               color: Colors.white.withOpacity(0.1),
//                               blurRadius: 20,
//                               offset: const Offset(-5, -5),
//                             ),
//                           ],
//                           // Glassmorphism effect
//                           backgroundBlendMode: BlendMode.overlay,
//                         ),
//                         child: Text(
//                           _user != null 
//                               ? 'Hello, ${_user!.displayName ?? 'Explorer'}!'
//                               : 'Welcome to Vydra',
//                           style: const TextStyle(
//                             fontFamily: 'Poppins',
//                             fontSize: 32,
//                             fontWeight: FontWeight.w800,
//                             color: Colors.white,
//                             letterSpacing: 1.2,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 30),
//                   ScaleTransition(
//                     scale: _pulseAnimation,
//                     child: GestureDetector(
//                       onTap: _user == null
//                           ? () async {
//                               final user = await _authService.signInWithGoogle();
//                               if (user != null && mounted) {
//                                 setState(() {
//                                   _user = user;
//                                 });
//                               }
//                             }
//                           : null,
//                       child: Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
//                         decoration: BoxDecoration(
//                           gradient: const LinearGradient(
//                             colors: [Color(0xFF6B48FF), Color(0xFF00DDEB)],
//                           ),
//                           borderRadius: BorderRadius.circular(50),
//                           boxShadow: [
//                             BoxShadow(
//                               color: const Color(0xFF6B48FF).withOpacity(0.3),
//                               blurRadius: 15,
//                               spreadRadius: 2,
//                             ),
//                           ],
//                         ),
//                         child: Text(
//                           _user == null ? 'Sign in with Google' : 'Explore Now',
//                           style: const TextStyle(
//                             fontFamily: 'Poppins',
//                             fontSize: 20,
//                             fontWeight: FontWeight.w600,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }