import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final GoTrueClient _auth = Supabase.instance.client.auth;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  // Sign Up with Email and Password
  Future<AuthResponse> signUp(String email, String password) async {
    return await _auth.signUp(email: email, password: password);
  }

  // Sign In with Email and Password
  Future<AuthResponse> signIn(String email, String password) async {
    return await _auth.signInWithPassword(email: email, password: password);
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
