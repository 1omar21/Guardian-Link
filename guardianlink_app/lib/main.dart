import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/services/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/fcm_service.dart';
import 'core/services/api_service.dart';
import 'core/navigation.dart';
import 'core/constants/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/parent/screens/parent_home_screen.dart';
import 'features/child/screens/child_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    // App still works without Firebase; only push notifications are disabled.
    debugPrint('Firebase initialization error: $e');
  }

  // Lets the native browsing monitor find the backend.
  await ApiService().persistConfigForNative();

  runApp(const MyApp());

  // Not awaited: the notification-permission dialog must not block startup.
  FCMService().initialize();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'GuardianLink',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/parent-home': (context) => const ParentHomeScreen(),
              '/child-home': (context) => const ChildHomeScreen(),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Check if user is already logged in
    Future.microtask(() {
      context.read<AuthProvider>().checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.isInitializing) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authProvider.isAuthenticated) {
          final user = authProvider.currentUser!;
          if (user.isParent) {
            return const ParentHomeScreen();
          } else {
            return const ChildHomeScreen();
          }
        }

        return const LoginScreen();
      },
    );
  }
}
