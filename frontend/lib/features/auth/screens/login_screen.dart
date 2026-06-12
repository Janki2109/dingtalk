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

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController(text: 'Engineering');
  bool _showPass = false;
  bool _isRegister = false;
  String _selectedRole = 'employee'; // 'admin' or 'employee'

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 40),

            // Logo
            Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                    gradient: AppColors.primaryGrad, shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium,
                    color: Colors.white, size: 40)),
            const SizedBox(height: 16),
            const Text('WorkSpace Pro',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                _isRegister
                    ? 'Create your workspace account'
                    : 'Sign in to your workspace',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 32),

            // Form card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8))
                  ]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isRegister ? 'Create Account' : 'Welcome back',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 20),

                    if (_isRegister) ...[
                      _Field(
                          label: 'Full Name',
                          ctrl: _nameCtrl,
                          icon: Icons.person_outline),
                      const SizedBox(height: 14),
                      _Field(
                          label: 'Department',
                          ctrl: _deptCtrl,
                          icon: Icons.business_outlined),
                      const SizedBox(height: 16),

                      // Admin / Employee toggle
                      const Text('Register as',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceVar,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          _RoleBtn(
                            label: 'Employee',
                            icon: Icons.person_rounded,
                            selected: _selectedRole == 'employee',
                            color: AppColors.primary,
                            onTap: () =>
                                setState(() => _selectedRole = 'employee'),
                          ),
                          _RoleBtn(
                            label: 'Admin',
                            icon: Icons.admin_panel_settings_rounded,
                            selected: _selectedRole == 'admin',
                            color: AppColors.orange,
                            onTap: () =>
                                setState(() => _selectedRole = 'admin'),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 10),

                      // Role info box
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: (_selectedRole == 'admin'
                                    ? AppColors.orange
                                    : AppColors.primary)
                                .withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: (_selectedRole == 'admin'
                                        ? AppColors.orange
                                        : AppColors.primary)
                                    .withOpacity(0.2))),
                        child: Row(children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: (_selectedRole == 'admin'
                                          ? AppColors.orange
                                          : AppColors.primary)
                                      .withOpacity(0.15),
                                  shape: BoxShape.circle),
                              child: Icon(
                                  _selectedRole == 'admin'
                                      ? Icons.admin_panel_settings_rounded
                                      : Icons.person_rounded,
                                  color: _selectedRole == 'admin'
                                      ? AppColors.orange
                                      : AppColors.primary,
                                  size: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    _selectedRole == 'admin'
                                        ? 'Admin Account'
                                        : 'Employee Account',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _selectedRole == 'admin'
                                            ? AppColors.orange
                                            : AppColors.primary)),
                                Text(
                                    _selectedRole == 'admin'
                                        ? 'Manage team, meetings, tasks & approvals. One admin per domain.'
                                        : 'View tasks, check in, apply leave, join meetings',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                              ])),
                        ]),
                      ),
                      const SizedBox(height: 14),

                      // Domain note
                      if (_emailCtrl.text.contains('@'))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.surfaceVar,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.domain_rounded,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text('Your workspace domain: ',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMuted)),
                            Text(_emailDomain,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                          ]),
                        ),
                      if (_emailCtrl.text.contains('@'))
                        const SizedBox(height: 14),
                    ],

                    // Email
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (_isRegister) setState(() {});
                      },
                      decoration: const InputDecoration(
                          labelText: 'Email Address',
                          prefixIcon: Icon(Icons.email_outlined, size: 18)),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_showPass,
                      decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 18),
                          suffixIcon: IconButton(
                              icon: Icon(
                                  _showPass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18),
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass))),
                    ),

                    // Error
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: AppColors.busy.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.busy, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(auth.error!,
                                    style: const TextStyle(
                                        color: AppColors.busy, fontSize: 13))),
                          ])),
                    ],
                    const SizedBox(height: 20),

                    // Submit
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: auth.loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor:
                                  _isRegister && _selectedRole == 'admin'
                                      ? AppColors.orange
                                      : AppColors.primary),
                          child: auth.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(_isRegister ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                        )),
                    const SizedBox(height: 16),

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
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 14),
                        children: [
                          TextSpan(
                              text: _isRegister ? 'Sign In' : 'Sign Up',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600))
                        ],
                      )),
                    )),
                  ]),
            ),

            const SizedBox(height: 16),

            // Info box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Each company email domain gets its own isolated workspace',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
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
        userRole: _selectedRole,
      );
    } else {
      ok = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    }

    if (ok && mounted) {
      // Show note if admin slot was taken
      final user = auth.user;
      if (user != null && user.bio.contains('already has an admin')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              '⚠️ Your domain already has an admin. You were registered as Employee.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }

      if (user != null && user.isAdmin) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminShell()),
            (route) => false);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AppShell()),
            (route) => false);
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.busy,
      behavior: SnackBarBehavior.floating,
    ));
  }
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                color: selected ? Colors.white : AppColors.textMuted, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textMuted)),
          ]),
        ),
      ));
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData icon;
  final TextInputType keyboard;
  const _Field(
      {required this.label,
      required this.ctrl,
      required this.icon,
      this.keyboard = TextInputType.text});
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration:
            InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18)),
      );
}
