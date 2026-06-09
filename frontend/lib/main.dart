import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
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

    // ── Browser tab close / refresh detection ──────────────────────────────
    try {
      js.context.callMethod('eval', [
        '''
        window.addEventListener('beforeunload', function(e) {
          // Send offline status synchronously when tab closes
          var token = localStorage.getItem('flutter.auth_token');
          if (token) {
            var port = window.location.port === '9090' ? '9090' : '9090';
            navigator.sendBeacon(
              'http://localhost:9090/api/users/status-offline',
              JSON.stringify({token: token})
            );
            // Also try fetch (may not complete but worth trying)
            fetch('http://localhost:9090/api/users/status', {
              method: 'PATCH',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + token
              },
              body: JSON.stringify({status: 'offline'}),
              keepalive: true
            });
          }
        });
      '''
      ]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── App lifecycle — pause = tab hidden, resume = tab visible ───────────────
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

  // Start heartbeat — every 20s tell backend user is still online
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

    // Start heartbeat when logged in
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
                  color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium,
                  color: Colors.white, size: 44)),
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
      )),
    );
  }
}

// ── Global navigation helper ──────────────────────────────────────────────────
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
