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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
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
                    ? 'Create your account'
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

                    // Register fields
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
                      const SizedBox(height: 14),

                      // Employee info box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.2))),
                        child: Row(children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.person,
                                  color: AppColors.primary, size: 20)),
                          const SizedBox(width: 10),
                          const Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Employee Account',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                Text(
                                    'View tasks, check in, apply leave, join meetings',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                              ])),
                        ]),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Email
                    _Field(
                        label: 'Email Address',
                        ctrl: _emailCtrl,
                        icon: Icons.email_outlined,
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 14),

                    // Password
                    TextFormField(
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

                    // Submit button
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: auth.loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: auth.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(_isRegister ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                        )),
                    const SizedBox(height: 16),

                    // Toggle login/register
                    Center(
                        child: GestureDetector(
                      onTap: () => setState(() {
                        _isRegister = !_isRegister;
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
            const SizedBox(height: 20),

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
                    child: Text('Login with your registered email and password',
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your email'),
          backgroundColor: AppColors.busy,
          behavior: SnackBarBehavior.floating));
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your password'),
          backgroundColor: AppColors.busy,
          behavior: SnackBarBehavior.floating));
      return;
    }
    if (_isRegister && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: AppColors.busy,
          behavior: SnackBarBehavior.floating));
      return;
    }

    final auth = context.read<AuthProvider>();
    bool ok;

    if (_isRegister) {
      // Always register as Employee
      ok = await auth.register(
        _nameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        'Employee',
        _deptCtrl.text.trim(),
      );
    } else {
      ok = await auth.login(_emailCtrl.text.trim(), _passwordCtrl.text);
    }

    if (ok && mounted) {
      final user = auth.user;
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
  Widget build(BuildContext context) => TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration:
            InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18)),
      );
}
