import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'data/services/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/admin/screens/admin_shell.dart';
import 'features/home/screens/app_shell.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(ChangeNotifierProvider(
      create: (_) => AuthProvider(), child: const WorkSpaceApp()));
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
      WidgetsBinding.instance.addPostFrameCallback((_) => startHeartbeat(auth));
    }
    return MaterialApp(
      title: 'WorkSpace Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeWithColor(auth.themeColor, false),
      darkTheme: AppTheme.themeWithColor(auth.themeColor, true),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _scale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
    _init();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    await context.read<AuthProvider>().tryAutoLogin();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    Widget next = !auth.isLoggedIn
        ? const LoginScreen()
        : auth.isAdmin
            ? const AdminShell()
            : const AppShell();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => next,
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0B14), Color(0xFF1a1035), Color(0xFF0d1b4b)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(children: [
            // Orbs
            Positioned(
                top: -60,
                right: -60,
                child: _buildOrb(220, AppColors.primary.withOpacity(0.3))),
            Positioned(
                bottom: 100,
                left: -80,
                child: _buildOrb(260, AppColors.purple.withOpacity(0.2))),

            Center(
                child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGrad,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primary.withOpacity(0.5),
                                  blurRadius: 40,
                                  spreadRadius: 8)
                            ],
                          ),
                          child: const Icon(Icons.workspace_premium,
                              color: Colors.white, size: 52),
                        ),
                        const SizedBox(height: 24),
                        const Text('WorkSpace Pro',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Text('Professional Team Communication',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14)),
                        const SizedBox(height: 60),
                        SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                                color: AppColors.primary.withOpacity(0.8),
                                strokeWidth: 2.5)),
                      ]),
                ),
              ),
            )),
          ]),
        ),
      );

  Widget _buildOrb(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                  color: color,
                  blurRadius: size * 0.5,
                  spreadRadius: size * 0.1)
            ]),
      );
}

class AppNavigator {
  static void goToLogin(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  static void goToAdmin(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminShell()), (r) => false);
  static void goToEmployee(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()), (r) => false);
}
