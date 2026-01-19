import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vigil_app/features/dashboard/presentation/screens/grid_view_screen.dart';
import 'package:vigil_app/features/auth/presentation/screens/login_screen.dart';
import 'package:vigil_app/core/config/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (with placeholders for now)
  // We wrap this in a try-catch to avoid crashing if credentials are missing during dev
  try {
    if (AppConstants.supabaseUrl != 'YOUR_SUPABASE_URL') {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
      );
    }
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
  }

  runApp(const ProviderScope(child: VigilApp()));
}

class VigilApp extends ConsumerWidget {
  const VigilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark, // Dark mode default
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data?.session;
          if (session != null) {
            return const GridViewScreen();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
