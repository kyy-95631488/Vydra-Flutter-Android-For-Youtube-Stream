// auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/youtube',
    ],
  );

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      // Attempt silent sign-in first
      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        // If silent sign-in fails, trigger interactive sign-in
        final newGoogleUser = await _googleSignIn.signIn();
        if (newGoogleUser == null) {
          print('Google Sign-In cancelled by user');
          return null;
        }
        return await _authenticateWithGoogle(newGoogleUser);
      }
      return await _authenticateWithGoogle(googleUser);
    } catch (e) {
      print('Error during Google Sign-In: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _authenticateWithGoogle(GoogleSignInAccount googleUser) async {
    try {
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      print('Authenticated user: ${userCredential.user?.email}');
      return {
        'user': userCredential.user,
        'accessToken': googleAuth.accessToken,
      };
    } catch (e) {
      print('Error authenticating with Google: $e');
      return null;
    }
  }

  Future<String?> getAccessToken() async {
    try {
      final GoogleSignInAccount? googleUser = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (googleUser == null) {
        print('No Google user signed in');
        return null;
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) {
        print('No valid access token available');
        return null;
      }
      print('Retrieved access token for user: ${googleUser.email}');
      return googleAuth.accessToken;
    } catch (e) {
      print('Error retrieving access token: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      print('User signed out successfully');
    } catch (e) {
      print('Error during sign out: $e');
    }
  }
}