import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/services/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/admin/screens/admin_shell.dart';
import 'features/home/screens/app_shell.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const WorkSpaceApp(),
    ),
  );
}

class WorkSpaceApp extends StatefulWidget {
  const WorkSpaceApp({super.key});
  @override
  State<WorkSpaceApp> createState() => _WorkSpaceAppState();
}

class _WorkSpaceAppState extends State<WorkSpaceApp>
    with WidgetsBindingObserver {
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.resumed) {
      auth.setOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      auth.setOffline();
    }
  }

  void startHeartbeat(AuthProvider auth) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (auth.isLoggedIn) {
        auth.setOnline();
      } else {
        _heartbeat?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoggedIn && (_heartbeat == null || !_heartbeat!.isActive)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        startHeartbeat(auth);
      });
    }

    return MaterialApp(
      title: 'WorkSpace Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeWithColor(auth.themeColor),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await context.read<AuthProvider>().tryAutoLogin();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    Widget next;
    if (!auth.isLoggedIn) {
      next = const LoginScreen();
    } else if (auth.isAdmin) {
      next = const AdminShell();
    } else {
      next = const AppShell();
    }
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => next));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: auth.themeColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: 20),
            const Text('WorkSpace Pro',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Professional Team Communication',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class AppNavigator {
  static void goToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false);
  }

  static void goToAdmin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminShell()),
        (route) => false);
  }

  static void goToEmployee(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()), (route) => false);
  }
}
