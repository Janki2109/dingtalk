import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../../files/screens/files_screen.dart';
import '../../tasks/screens/tasks_screen.dart';
import '../../auth/screens/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Uint8List? _photoBytes;
  String _serverAvatarUrl = '';
  bool _uploadingPhoto = false;
  List<AttendanceModel> _attendanceRecords = [];
  bool _loadingAttendance = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPhoto();
    _loadAttendance();
    // Set online when profile opens
    context.read<AuthProvider>().setOnline();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Load photo — check prefs cache first, then fall back to DB avatar_url
  Future<void> _loadSavedPhoto() async {
    try {
      // Read provider before any await to avoid BuildContext-across-async-gap
      final auth = context.read<AuthProvider>();
      final prefs = await SharedPreferences.getInstance();

      // Check for cached server URL (new format)
      final cachedUrl = prefs.getString('profile_photo_url') ?? '';
      if (cachedUrl.isNotEmpty && mounted) {
        setState(() { _serverAvatarUrl = cachedUrl; _photoBytes = null; });
        return;
      }

      // Check for old base64 in prefs (backward compat)
      final b64 = prefs.getString('profile_photo');
      if (b64 != null && b64.isNotEmpty && mounted) {
        setState(() => _photoBytes = base64Decode(b64));
        return;
      }

      // Fall back to server DB avatar_url
      final avatarUrl = auth.user?.avatarUrl ?? '';
      if (avatarUrl.isEmpty || !mounted) return;
      if (avatarUrl.startsWith('local:')) {
        final bytes = base64Decode(avatarUrl.substring(6));
        setState(() => _photoBytes = bytes);
      } else if (avatarUrl.startsWith('/uploads/') || avatarUrl.startsWith('http')) {
        setState(() => _serverAvatarUrl = avatarUrl);
      }
    } catch (_) {}
  }

  Future<void> _savePhotoLocally(Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo', base64Encode(bytes));
  }

  Future<void> _savePhotoUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_url', url);
    await prefs.remove('profile_photo'); // clear any old base64
  }

  Future<void> _removePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_photo');
    await prefs.remove('profile_photo_url');
    setState(() { _photoBytes = null; _serverAvatarUrl = ''; });
  }

  Future<void> _loadAttendance() async {
    setState(() => _loadingAttendance = true);
    try {
      final list = await ApiService.getAttendance();
      if (mounted)
        setState(() {
          _attendanceRecords = list;
          _loadingAttendance = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingAttendance = false);
    }
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
    final name = user?.name ?? 'User';
    final role = user?.role ?? 'Employee';
    final dept = user?.department ?? '';
    final email = user?.email ?? '';
    final bio = user?.bio ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        // ── App Bar with photo ──────────────────────────────────────────────
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
                    // ── Profile photo ──────────────────────────────────────────
                    GestureDetector(
                      onTap: () => _showPhotoOptions(context),
                      child: Stack(children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              color: themeColor.withValues(alpha: 0.5)),
                          child: _uploadingPhoto
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : _photoBytes != null
                                  ? ClipOval(child: Image.memory(
                                      _photoBytes!, width: 90, height: 90, fit: BoxFit.cover))
                                  : _serverAvatarUrl.isNotEmpty
                                      ? ClipOval(child: CachedNetworkImage(
                                          imageUrl: _serverAvatarUrl.startsWith('http')
                                              ? _serverAvatarUrl
                                              : '${AppConstants.serverUrl}$_serverAvatarUrl',
                                          width: 90, height: 90, fit: BoxFit.cover,
                                          placeholder: (_, __) => const Padding(
                                              padding: EdgeInsets.all(28),
                                              child: CircularProgressIndicator(
                                                  color: Colors.white, strokeWidth: 2)),
                                          errorWidget: (_, __, ___) => Center(
                                              child: Text(
                                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 38,
                                                      fontWeight: FontWeight.w800))),
                                        ))
                                      : Center(
                                          child: Text(
                                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
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
                        // Online indicator
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
                        Icon(Icons.circle, color: AppColors.online, size: 8),
                        SizedBox(width: 6),
                        Text('Online',
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

          // Email card
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

          _Section(title: 'Workspace', items: [
            _Item(
                icon: Icons.task_alt,
                label: 'My Tasks',
                color: themeColor,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TasksScreen()))),
            _Item(
                icon: Icons.access_time,
                label: 'Attendance History',
                color: AppColors.online,
                onTap: () => _showAttendanceHistory(context)),
          ]),

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

  // ── Photo options ────────────────────────────────────────────────────────────
  void _showPhotoOptions(BuildContext context) {
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
                      final fileName = r.files.first.name;
                      setState(() => _uploadingPhoto = true);
                      final authRef = context.read<AuthProvider>();
                      try {
                        // Upload bytes to server → get real permanent URL
                        final result = await ApiService.uploadMedia(fileName, bytes);
                        final serverUrl = result['url'] as String? ?? '';
                        if (serverUrl.isNotEmpty) {
                          await _savePhotoUrl(serverUrl);
                          await _updateProfileOnServer(avatarUrl: serverUrl);
                          try {
                            final updated = await ApiService.getMe();
                            if (mounted) authRef.updateUser(updated);
                          } catch (_) {}
                          if (mounted) setState(() {
                            _serverAvatarUrl = serverUrl;
                            _photoBytes = null;
                            _uploadingPhoto = false;
                          });
                          _snack('✅ Photo saved to server!', AppColors.online);
                        } else {
                          // Fallback: local base64
                          await _savePhotoLocally(bytes);
                          await _updateProfileOnServer(avatarUrl: 'local:${base64Encode(bytes)}');
                          if (mounted) setState(() { _photoBytes = bytes; _uploadingPhoto = false; });
                          _snack('✅ Photo saved!', AppColors.online);
                        }
                      } catch (_) {
                        // Fallback to local
                        await _savePhotoLocally(bytes);
                        await _updateProfileOnServer(avatarUrl: 'local:${base64Encode(bytes)}');
                        if (mounted) setState(() { _photoBytes = bytes; _uploadingPhoto = false; });
                        _snack('✅ Photo saved!', AppColors.online);
                      }
                    }
                  } catch (_) {
                    if (mounted) setState(() => _uploadingPhoto = false);
                  }
                }),
            _PhotoBtn(
                icon: Icons.delete_outline,
                label: 'Remove',
                color: AppColors.busy,
                onTap: () async {
                  Navigator.pop(context);
                  await _removePhoto();
                  await _updateProfileOnServer(avatarUrl: '');
                  _snack('Photo removed', Colors.grey);
                }),
          ]),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ── Edit profile ─────────────────────────────────────────────────────────────
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
                    labelText: 'Bio (about yourself)',
                    prefixIcon: Icon(Icons.info_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Job Role',
                    prefixIcon: Icon(Icons.work_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Save to backend permanently
                    await _updateProfileOnServer(
                      name: nameCtrl.text.trim(),
                      bio: bioCtrl.text.trim(),
                      role: roleCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                    );
                    // Refresh user
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

  // ── Change password ──────────────────────────────────────────────────────────
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
                              labelText: 'Confirm New Password',
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
                                      _snack('Password must be 6+ characters',
                                          AppColors.busy);
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
                                              'new_password': newCtrl.text
                                            }),
                                          )
                                          .timeout(const Duration(seconds: 15));
                                      setS(() => loading = false);
                                      if (resp.statusCode == 200) {
                                        if (context.mounted)
                                          Navigator.pop(context);
                                        _snack(
                                            '✅ Password changed successfully!',
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

  // ── Theme & Brightness ────────────────────────────────────────────────────────
  void _showThemeSettings(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ThemeSheet(auth: auth),
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  void _showSettings(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(auth: auth),
    );
  }

  // ── Sign out ──────────────────────────────────────────────────────────────────
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
      // Sets status=offline on backend then clears token
      await auth.logout();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false);
    }
  }

  // ── Attendance history ───────────────────────────────────────────────────────
  void _showAttendanceHistory(BuildContext context) {
    final present =
        _attendanceRecords.where((a) => a.status == 'present').length;
    final absent = _attendanceRecords.length - present;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                const Text('Attendance History',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ])),
          if (_loadingAttendance)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  _AttStat('Present', '$present', AppColors.online),
                  const SizedBox(width: 8),
                  _AttStat('Absent', '$absent', AppColors.busy),
                  const SizedBox(width: 8),
                  _AttStat('Total', '${_attendanceRecords.length}',
                      AppColors.primary),
                ])),
            Expanded(
                child: _attendanceRecords.isEmpty
                    ? const Center(child: Text('No records yet'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _attendanceRecords.length,
                        itemBuilder: (ctx, i) {
                          final a = _attendanceRecords[i];
                          final present =
                              a.status == 'present' || a.status == 'late';
                          final color =
                              present ? AppColors.online : AppColors.busy;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border)),
                            child: Row(children: [
                              Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Icon(
                                      present
                                          ? Icons.check_circle_outline
                                          : Icons.cancel_outlined,
                                      color: color,
                                      size: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        '${a.date.day}/${a.date.month}/${a.date.year}',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                        a.checkIn != null
                                            ? '${_fmt(a.checkIn!)} → ${a.checkOut != null ? _fmt(a.checkOut!) : 'Still in'}'
                                            : 'Absent',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary)),
                                  ])),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(present ? 'Present' : 'Absent',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: color)),
                              ),
                            ]),
                          );
                        })),
          ],
        ]),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ── AI Chat Screen ─────────────────────────────────────────────────────────────
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  final _suggestions = [
    'Write a professional email',
    'Help me plan my day',
    'Explain something complex',
    'Draft a message to my team',
    'Give me productivity tips',
    'Help me write code',
    'Summarize a topic',
    'Review my writing',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'assistant',
      'content': 'Hello! I\'m your AI Assistant. How can I help you today?\n\n'
          'I can help you with:\n'
          '• Writing emails & messages\n'
          '• Answering any questions\n'
          '• Coding & debugging\n'
          '• Summarizing content\n'
          '• Brainstorming ideas\n\n'
          'Just ask me anything!',
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _loading = true;
    });
    _scrollBottom();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      final resp = await http
          .post(
            Uri.parse('${AppConstants.apiUrl}/chat/ai'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token'
            },
            body: jsonEncode({'user_id': 'ai', 'message': text}),
          )
          .timeout(const Duration(seconds: 30));

      final reply = resp.statusCode == 200
          ? (jsonDecode(resp.body)['reply'] as String? ?? 'No response')
          : 'Error ${resp.statusCode}. Try again.';
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '❌ Cannot connect. Is the backend running?'
        });
        _loading = false;
      });
    }
    _scrollBottom();
  }

  void _scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients)
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  gradient: AppColors.purpleGrad, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Assistant',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Always here to help',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.purple,
                    fontWeight: FontWeight.w500)),
          ]),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => setState(() {
                    _messages.clear();
                    _messages.add({
                      'role': 'assistant',
                      'content': 'New conversation started! How can I help you?'
                    });
                  })),
        ],
      ),
      body: Column(children: [
        // Quick suggestions
        if (_messages.length <= 1)
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _suggestions
                    .map((s) => GestureDetector(
                          onTap: () => _send(s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: themeColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: themeColor.withOpacity(0.2))),
                            child: Text(s,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: themeColor,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ))
                    .toList()),
          ),

        // Messages
        Expanded(
            child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          itemCount: _messages.length + (_loading ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == _messages.length) return _TypingBubble();
            final msg = _messages[i];
            final isMe = msg['role'] == 'user';
            return _AIChatBubble(
                text: msg['content'] ?? '', isMe: isMe, themeColor: themeColor);
          },
        )),

        // Input
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Row(children: [
            Expanded(
                child: Container(
              decoration: BoxDecoration(
                  color: AppColors.surfaceVar,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.purple)),
                Expanded(
                    child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                      hintText: 'Ask me anything...',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                )),
              ]),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(),
              child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      gradient: AppColors.purpleGrad, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AIChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final Color themeColor;
  const _AIChatBubble(
      {required this.text, required this.isMe, required this.themeColor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                      gradient: AppColors.purpleGrad, shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 16)),
              const SizedBox(width: 8),
            ],
            Flexible(
                child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: isMe ? themeColor : AppColors.surface,
                  borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]),
              child: Text(text,
                  style: TextStyle(
                      color: isMe ? Colors.white : AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.5)),
            )),
          ],
        ),
      );
}

class _TypingBubble extends StatefulWidget {
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                  gradient: AppColors.purpleGrad, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 16)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4))),
            child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final v = (_ctrl.value - i * 0.25).abs() % 1.0;
                        return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: AppColors.purple.withOpacity(
                                    0.3 + (v < 0.5 ? v : 1 - v) * 0.7),
                                shape: BoxShape.circle));
                      }),
                    )),
          ),
        ]),
      );
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
    const Color(0xFF1A73E8), // Blue (default)
    const Color(0xFF7C4DFF), // Purple
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFF22C55E), // Green
    const Color(0xFFEF4444), // Red
    const Color(0xFFFF6B35), // Orange
    const Color(0xFFE91E63), // Pink
    const Color(0xFFF59E0B), // Amber
    const Color(0xFF607D8B), // Grey
    const Color(0xFF000000), // Dark
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
                child: const Text('Done'),
              )),
        ]),
      );
}

// ── Settings Sheet ─────────────────────────────────────────────────────────────
class _SettingsSheet extends StatelessWidget {
  final AuthProvider auth;
  const _SettingsSheet({required this.auth});
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

class _AttStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AttStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ));
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
