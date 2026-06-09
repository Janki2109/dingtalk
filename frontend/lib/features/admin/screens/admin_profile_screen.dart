import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../../files/screens/files_screen.dart';
import '../../auth/screens/login_screen.dart';
import '../../profile/screens/profile_screen.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});
  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  Uint8List? _photoBytes;

  @override
  void initState() {
    super.initState();
    _loadSavedPhoto();
    context.read<AuthProvider>().setOnline();
  }

  Future<void> _loadSavedPhoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString('profile_photo');
      if (b64 != null && mounted) {
        setState(() => _photoBytes = base64Decode(b64));
      }
    } catch (_) {}
  }

  Future<void> _savePhotoLocally(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo', base64Encode(bytes));
  }

  Future<void> _updateProfileOnServer({
    String? name,
    String? bio,
    String? avatarUrl,
    String? role,
    String? phone,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      if (token == null) return;
      await http
          .put(
            Uri.parse('${AppConstants.apiUrl}/auth/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name ?? '',
              'bio': bio ?? '',
              'avatar_url': avatarUrl ?? '',
              'role': role ?? '',
              'phone': phone ?? '',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final themeColor = auth.themeColor;
    final name = user?.name ?? 'Admin';
    final role = user?.role ?? 'Administrator';
    final dept = user?.department ?? '';
    final email = user?.email ?? '';
    final bio = user?.bio ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          expandedHeight: 260,
          pinned: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showEditProfile(context, auth),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _showSettings(context, auth),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [themeColor, themeColor.withOpacity(0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    GestureDetector(
                      onTap: () => _showPhotoOptions(context, themeColor),
                      child: Stack(children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              color: themeColor.withOpacity(0.5)),
                          child: _photoBytes != null
                              ? ClipOval(
                                  child: Image.memory(_photoBytes!,
                                      width: 90, height: 90, fit: BoxFit.cover))
                              : Center(
                                  child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : 'A',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 38,
                                          fontWeight: FontWeight.w800))),
                        ),
                        Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: themeColor, width: 2)),
                              child: Icon(Icons.camera_alt,
                                  size: 14, color: themeColor),
                            )),
                        Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                  color: AppColors.online,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2)),
                            )),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text('$role · $dept',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(bio,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20)),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('Administrator',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: Column(children: [
          const SizedBox(height: 16),

          // Email
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const Icon(Icons.email_outlined,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Text(email,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textSecondary)),
                ]),
              )),
          const SizedBox(height: 12),

          // Features
          _Section(title: 'Features', items: [
            _Item(
                icon: Icons.people_outline,
                label: 'Contacts & Org Chart',
                color: AppColors.accent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ContactsScreen()))),
            _Item(
                icon: Icons.folder_outlined,
                label: 'File Manager',
                color: AppColors.orange,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FilesScreen()))),
            _Item(
                icon: Icons.auto_awesome,
                label: 'AI Assistant',
                color: AppColors.purple,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AIChatScreen()))),
          ]),

          // Account
          _Section(title: 'Account', items: [
            _Item(
                icon: Icons.palette_outlined,
                label: 'Theme & Brightness',
                color: AppColors.purple,
                onTap: () => _showThemeSettings(context, auth)),
            _Item(
                icon: Icons.lock_outline,
                label: 'Change Password',
                color: AppColors.primary,
                onTap: () => _showChangePassword(context)),
            _Item(
                icon: Icons.logout,
                label: 'Sign Out',
                color: AppColors.busy,
                onTap: () => _signOut(context, auth)),
          ]),

          const SizedBox(height: 100),
        ])),
      ]),
    );
  }

  void _showPhotoOptions(BuildContext context, Color themeColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Profile Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _PhotoBtn(
                icon: Icons.photo_library,
                label: 'Upload Photo',
                color: AppColors.purple,
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final r = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                        withData: true);
                    if (r != null &&
                        r.files.isNotEmpty &&
                        r.files.first.bytes != null) {
                      final bytes = r.files.first.bytes!;
                      setState(() => _photoBytes = bytes);
                      await _savePhotoLocally(bytes);
                      await _updateProfileOnServer(
                          avatarUrl: 'local:${base64Encode(bytes)}');
                      _snack('✅ Photo saved!', AppColors.online);
                    }
                  } catch (_) {}
                }),
            _PhotoBtn(
                icon: Icons.delete_outline,
                label: 'Remove',
                color: AppColors.busy,
                onTap: () async {
                  Navigator.pop(context);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('profile_photo');
                  setState(() => _photoBytes = null);
                  await _updateProfileOnServer(avatarUrl: '');
                  _snack('Photo removed', Colors.grey);
                }),
          ]),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  void _showEditProfile(BuildContext context, AuthProvider auth) {
    final user = auth.user;
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    final bioCtrl = TextEditingController(text: user?.bio ?? '');
    final roleCtrl = TextEditingController(text: user?.role ?? '');
    final phoneCtrl = TextEditingController(text: user?.phone ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Edit Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: bioCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Bio', prefixIcon: Icon(Icons.info_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Role', prefixIcon: Icon(Icons.work_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateProfileOnServer(
                      name: nameCtrl.text.trim(),
                      bio: bioCtrl.text.trim(),
                      role: roleCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                    );
                    try {
                      final updated = await ApiService.getMe();
                      if (mounted) auth.updateUser(updated);
                    } catch (_) {}
                    _snack('✅ Profile updated!', AppColors.online);
                  },
                  child: const Text('Save Changes'),
                )),
          ],
        )),
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool loading = false;
    bool showOld = false, showNew = false, showConf = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 20),
                      const Text('Change Password',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      TextField(
                          controller: oldCtrl,
                          obscureText: !showOld,
                          decoration: InputDecoration(
                              labelText: 'Current Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                  icon: Icon(showOld
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () =>
                                      setS(() => showOld = !showOld)))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: newCtrl,
                          obscureText: !showNew,
                          decoration: InputDecoration(
                              labelText: 'New Password',
                              prefixIcon: const Icon(Icons.lock_reset),
                              suffixIcon: IconButton(
                                  icon: Icon(showNew
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () =>
                                      setS(() => showNew = !showNew)))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: confCtrl,
                          obscureText: !showConf,
                          decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon:
                                  const Icon(Icons.check_circle_outline),
                              suffixIcon: IconButton(
                                  icon: Icon(showConf
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () =>
                                      setS(() => showConf = !showConf)))),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading
                                ? null
                                : () async {
                                    if (newCtrl.text != confCtrl.text) {
                                      _snack('Passwords do not match',
                                          AppColors.busy);
                                      return;
                                    }
                                    if (newCtrl.text.length < 6) {
                                      _snack(
                                          'Min 6 characters', AppColors.busy);
                                      return;
                                    }
                                    setS(() => loading = true);
                                    try {
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      final token = prefs
                                          .getString(AppConstants.tokenKey);
                                      final resp = await http
                                          .post(
                                            Uri.parse(
                                                '${AppConstants.apiUrl}/auth/change-password'),
                                            headers: {
                                              'Content-Type':
                                                  'application/json',
                                              if (token != null)
                                                'Authorization': 'Bearer $token'
                                            },
                                            body: jsonEncode({
                                              'old_password': oldCtrl.text,
                                              'new_password': newCtrl.text,
                                            }),
                                          )
                                          .timeout(const Duration(seconds: 15));
                                      setS(() => loading = false);
                                      if (resp.statusCode == 200) {
                                        if (context.mounted)
                                          Navigator.pop(context);
                                        _snack('✅ Password changed!',
                                            AppColors.online);
                                      } else {
                                        final msg =
                                            jsonDecode(resp.body)['error'] ??
                                                'Failed';
                                        _snack(msg, AppColors.busy);
                                      }
                                    } catch (_) {
                                      setS(() => loading = false);
                                      _snack('Failed. Check connection.',
                                          AppColors.busy);
                                    }
                                  },
                            child: loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text('Change Password'),
                          )),
                    ]),
              )),
    );
  }

  void _showThemeSettings(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ThemeSheet(auth: auth),
    );
  }

  void _showSettings(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Push Notifications'),
              trailing: Switch(
                  value: true, onChanged: (_) {}, activeColor: auth.themeColor),
              contentPadding: EdgeInsets.zero),
          ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              trailing: const Text('English',
                  style: TextStyle(color: AppColors.textMuted)),
              contentPadding: EdgeInsets.zero),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, AuthProvider auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await auth.logout();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false);
    }
  }
}

// ── Theme Sheet ────────────────────────────────────────────────────────────────
class _ThemeSheet extends StatefulWidget {
  final AuthProvider auth;
  const _ThemeSheet({required this.auth});
  @override
  State<_ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends State<_ThemeSheet> {
  late Color _color;
  late double _brightness;

  final _colors = [
    const Color(0xFF1A73E8),
    const Color(0xFF7C4DFF),
    const Color(0xFF00BCD4),
    const Color(0xFF22C55E),
    const Color(0xFFEF4444),
    const Color(0xFFFF6B35),
    const Color(0xFFE91E63),
    const Color(0xFFF59E0B),
    const Color(0xFF607D8B),
    const Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    _color = widget.auth.themeColor;
    _brightness = widget.auth.brightness;
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Theme & Brightness',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Color',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary))),
          const SizedBox(height: 12),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _colors
                  .map((c) => GestureDetector(
                        onTap: () {
                          setState(() => _color = c);
                          widget.auth.updateTheme(color: c);
                        },
                        child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: _color.value == c.value
                                    ? Border.all(
                                        color: AppColors.border, width: 3)
                                    : null,
                                boxShadow: _color.value == c.value
                                    ? [
                                        BoxShadow(
                                            color: c.withOpacity(0.5),
                                            blurRadius: 8)
                                      ]
                                    : null),
                            child: _color.value == c.value
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 22)
                                : null),
                      ))
                  .toList()),
          const SizedBox(height: 24),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Brightness',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary))),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.brightness_low, color: AppColors.textMuted),
            Expanded(
                child: Slider(
              value: _brightness,
              min: 0.3,
              max: 1.0,
              activeColor: _color,
              onChanged: (v) {
                setState(() => _brightness = v);
                widget.auth.updateTheme(brightness: v);
              },
            )),
            const Icon(Icons.brightness_high, color: AppColors.textMuted),
          ]),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'))),
        ]),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _PhotoBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PhotoBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28)),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _Section({required this.title, required this.items});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted))),
          Container(
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border)),
            child: Column(
                children: List.generate(
                    items.length,
                    (i) => Column(children: [
                          items[i],
                          if (i < items.length - 1)
                            const Divider(height: 1, indent: 56),
                        ]))),
          ),
        ]),
      );
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Item(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
        title: Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right,
            color: AppColors.textMuted, size: 18),
        onTap: onTap,
      );
}
