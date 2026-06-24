import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../admin/screens/admin_shell.dart';
import '../../home/screens/app_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController(text: 'Engineering');
  bool _showPass = false;
  bool _isRegister = false;
  String _selectedRole = 'employee';

  late AnimationController _bgAnim;
  late AnimationController _cardAnim;
  late Animation<double> _cardSlide;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();
    _bgAnim =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
    _cardAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _cardSlide = Tween<double>(begin: 40, end: 0).animate(
        CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));
    _cardFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut));
    _cardAnim.forward();
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    _cardAnim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  String get _emailDomain {
    final email = _emailCtrl.text.trim();
    if (email.contains('@')) {
      final parts = email.split('@');
      if (parts.length == 2 && parts[1].isNotEmpty) return '@${parts[1]}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(children: [
        // Animated gradient background
        AnimatedBuilder(
          animation: _bgAnim,
          builder: (_, __) => Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF0A0B14),
                  Color(0xFF1a1035),
                  Color(0xFF0d1b4b)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(_bgAnim.value * 2 * math.pi),
              ),
            ),
          ),
        ),

        // Floating orbs
        Positioned(
            top: -60,
            right: -60,
            child: _Orb(size: 220, color: AppColors.primary.withOpacity(0.3))),
        Positioned(
            bottom: 100,
            left: -80,
            child: _Orb(size: 260, color: AppColors.purple.withOpacity(0.2))),
        Positioned(
            top: size.height * 0.4,
            right: -40,
            child: _Orb(size: 160, color: AppColors.accent.withOpacity(0.2))),

        // Content
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedBuilder(
              animation: _cardAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _cardSlide.value),
                child: Opacity(opacity: _cardFade.value, child: child),
              ),
              child: Column(children: [
                const SizedBox(height: 48),

                // Logo
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGrad,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 4)
                    ],
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: 20),
                const Text('WorkSpace Pro',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text(
                  _isRegister
                      ? 'Create your workspace account'
                      : 'Sign in to your workspace',
                  style: TextStyle(
                      fontSize: 15, color: Colors.white.withOpacity(0.6)),
                ),
                const SizedBox(height: 36),

                // Form card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 40,
                          offset: const Offset(0, 20))
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isRegister ? 'Create Account' : 'Welcome back',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(
                            _isRegister
                                ? 'Fill in your details to get started'
                                : 'Enter your credentials to continue',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.5))),
                        const SizedBox(height: 24),

                        if (_isRegister) ...[
                          _GlassField(
                              label: 'Full Name',
                              ctrl: _nameCtrl,
                              icon: Icons.person_outline_rounded),
                          const SizedBox(height: 14),
                          _GlassField(
                              label: 'Department',
                              ctrl: _deptCtrl,
                              icon: Icons.business_outlined),
                          const SizedBox(height: 20),

                          // Role toggle
                          Text('Register as',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.7))),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16)),
                            child: Row(children: [
                              _RoleBtn(
                                  label: 'Employee',
                                  icon: Icons.person_rounded,
                                  selected: _selectedRole == 'employee',
                                  color: AppColors.primary,
                                  onTap: () => setState(
                                      () => _selectedRole = 'employee')),
                              _RoleBtn(
                                  label: 'Admin',
                                  icon: Icons.admin_panel_settings_rounded,
                                  selected: _selectedRole == 'admin',
                                  color: AppColors.orange,
                                  onTap: () =>
                                      setState(() => _selectedRole = 'admin')),
                            ]),
                          ),
                          const SizedBox(height: 14),

                          // Role info
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: (_selectedRole == 'admin'
                                      ? AppColors.orange
                                      : AppColors.primary)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: (_selectedRole == 'admin'
                                          ? AppColors.orange
                                          : AppColors.primary)
                                      .withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              Icon(
                                  _selectedRole == 'admin'
                                      ? Icons.admin_panel_settings_rounded
                                      : Icons.person_rounded,
                                  color: _selectedRole == 'admin'
                                      ? AppColors.orange
                                      : AppColors.primary,
                                  size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                _selectedRole == 'admin'
                                    ? 'Admin: Manage team, meetings & approvals. One per domain.'
                                    : 'Employee: View tasks, attend meetings, apply for leave.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.7)),
                              )),
                            ]),
                          ),
                          const SizedBox(height: 14),

                          if (_emailCtrl.text.contains('@')) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                const Icon(Icons.domain_rounded,
                                    size: 14, color: Colors.white38),
                                const SizedBox(width: 8),
                                Text('Workspace: ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.5))),
                                Text(_emailDomain,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                              ]),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],

                        _GlassField(
                          label: 'Email Address',
                          ctrl: _emailCtrl,
                          icon: Icons.email_outlined,
                          keyboard: TextInputType.emailAddress,
                          onChanged: (_) {
                            if (_isRegister) setState(() {});
                          },
                        ),
                        const SizedBox(height: 14),
                        _GlassField(
                          label: 'Password',
                          ctrl: _passwordCtrl,
                          icon: Icons.lock_outline_rounded,
                          obscure: !_showPass,
                          suffix: IconButton(
                            icon: Icon(
                                _showPass
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: Colors.white38),
                            onPressed: () =>
                                setState(() => _showPass = !_showPass),
                          ),
                        ),

                        // Error
                        if (auth.error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                                color: AppColors.busy.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.busy.withOpacity(0.3))),
                            child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.busy, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(auth.error!,
                                      style: const TextStyle(
                                          color: AppColors.busy,
                                          fontSize: 13))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Submit button
                        Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isRegister && _selectedRole == 'admin'
                                  ? [AppColors.orange, const Color(0xFFEF4444)]
                                  : [AppColors.primary, AppColors.primaryDark],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: (_isRegister && _selectedRole == 'admin'
                                        ? AppColors.orange
                                        : AppColors.primary)
                                    .withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: auth.loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: auth.loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5))
                                : Text(
                                    _isRegister ? 'Create Account' : 'Sign In',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Toggle
                        Center(
                            child: GestureDetector(
                          onTap: () => setState(() {
                            _isRegister = !_isRegister;
                            _selectedRole = 'employee';
                          }),
                          child: RichText(
                              text: TextSpan(
                            text: _isRegister
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14),
                            children: [
                              TextSpan(
                                  text: _isRegister ? 'Sign In' : 'Sign Up',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          )),
                        )),
                      ]),
                ),

                const SizedBox(height: 20),

                // Info
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.shield_outlined,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Each company email domain gets its own isolated workspace',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.6)))),
                  ]),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _submit() async {
    if (_emailCtrl.text.trim().isEmpty) {
      _snack('Please enter your email');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      _snack('Please enter your password');
      return;
    }
    if (_isRegister && _nameCtrl.text.trim().isEmpty) {
      _snack('Please enter your name');
      return;
    }
    if (!_emailCtrl.text.trim().contains('@')) {
      _snack('Please enter a valid email');
      return;
    }

    final auth = context.read<AuthProvider>();
    bool ok;
    if (_isRegister) {
      ok = await auth.register(
          _nameCtrl.text.trim(),
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _selectedRole == 'admin' ? 'Administrator' : 'Employee',
          _deptCtrl.text.trim(),
          userRole: _selectedRole);
    } else {
      ok = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    }

    if (ok && mounted) {
      final user = auth.user;
      if (user != null && user.bio.contains('already has an admin')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              '⚠️ Your domain already has an admin. Registered as Employee.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ));
      }
      if (user != null && user.isAdmin) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminShell()),
            (r) => false);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AppShell()), (r) => false);
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.busy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => Container(
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

class _GlassField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData icon;
  final TextInputType keyboard;
  final bool obscure;
  final Widget? suffix;
  final Function(String)? onChanged;

  const _GlassField(
      {required this.label,
      required this.ctrl,
      required this.icon,
      this.keyboard = TextInputType.text,
      this.obscure = false,
      this.suffix,
      this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: keyboard,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.white38, size: 18),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      );
}

class _RoleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _RoleBtn(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
          child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [color, color.withOpacity(0.8)])
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white38, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.white38)),
          ]),
        ),
      ));
}
