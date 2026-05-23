import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'screens/planner/planner_page.dart';
import 'theme.dart';
import 'auth_notifier.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize();

  // if (kDebugMode) {
  // final host = defaultTargetPlatform == TargetPlatform.android
  //     ? '10.0.2.2'
  //     : 'localhost';
  // FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  // }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthNotifier _authNotifier = AuthNotifier();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    // Set up GoRouter with AuthNotifier serving as the refreshListenable
    _router = GoRouter(
      refreshListenable: _authNotifier,
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/verify-email',
          builder: (context, state) => const VerifyEmailScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/planner',
          builder: (context, state) => const PlannerPage(),
        ),
      ],
      redirect: (context, state) {
        final isAuthenticated = _authNotifier.isAuthenticated;
        final isEmailVerified = _authNotifier.isEmailVerified;
        final isGoingToLogin = state.matchedLocation == '/login';
        final isGoingToSignup = state.matchedLocation == '/signup';
        final isGoingToForgot = state.matchedLocation == '/forgot-password';
        final isGoingToVerify = state.matchedLocation == '/verify-email';

        // 1. Not Authenticated
        if (!isAuthenticated) {
          // Allow routing only to login, signup, or forgot-password
          if (isGoingToLogin || isGoingToSignup || isGoingToForgot) {
            return null;
          }
          return '/login';
        }

        // 2. Authenticated but email not verified
        final user = _authNotifier.user;
        final isGoogleUser =
            user?.providerData.any((p) => p.providerId == 'google.com') ??
            false;

        // Google accounts are pre-verified. Email-password accounts require verification check.
        if (!isEmailVerified && !isGoogleUser) {
          if (isGoingToVerify) return null;
          return '/verify-email';
        }

        // 3. Authenticated and Verified (or Google user)
        // Prevent going to auth screens if already logged in and verified
        if (isGoingToLogin ||
            isGoingToSignup ||
            isGoingToForgot ||
            isGoingToVerify) {
          return '/';
        }

        // Proceed normally
        return null;
      },
    );
  }

  @override
  void dispose() {
    _authNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PartyBee',
      debugShowCheckedModeBanner: false,
      theme: PremiumTheme.darkTheme,
      routerConfig: _router,
    );
  }
}
