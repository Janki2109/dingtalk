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

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _photoBytes;
  String _serverAvatarUrl = '';
  bool _uploadingPhoto = false;
  List<AttendanceModel> _attendanceRecords = [];
  bool _loadingAttendance = false;
  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _loadSavedPhoto();
    _loadAttendance();
    context.read<AuthProvider>().setOnline();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPhoto() async {
    try {
      final auth = context.read<AuthProvider>();
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('profile_photo_url') ?? '';
      if (cachedUrl.isNotEmpty && mounted) {
        setState(() {
          _serverAvatarUrl = cachedUrl;
          _photoBytes = null;
        });
        return;
      }
      final b64 = prefs.getString('profile_photo');
      if (b64 != null && b64.isNotEmpty && mounted) {
        setState(() => _photoBytes = base64Decode(b64));
        return;
      }
      final avatarUrl = auth.user?.avatarUrl ?? '';
      if (avatarUrl.isEmpty || !mounted) return;
      if (avatarUrl.startsWith('local:')) {
        setState(() => _photoBytes = base64Decode(avatarUrl.substring(6)));
      } else if (avatarUrl.startsWith('/uploads/') ||
          avatarUrl.startsWith('http')) {
        setState(() => _serverAvatarUrl = avatarUrl);
      }
    } catch (_) {}
  }

  Future<void> _savePhotoLocally(Uint8List bytes) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('profile_photo', base64Encode(bytes));
  }

  Future<void> _savePhotoUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('profile_photo_url', url);
    await p.remove('profile_photo');
  }

  Future<void> _removePhoto() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('profile_photo');
    await p.remove('profile_photo_url');
    setState(() {
      _photoBytes = null;
      _serverAvatarUrl = '';
    });
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

  Future<void> _updateProfileOnServer(
      {String? name,
      String? bio,
      String? avatarUrl,
      String? role,
      String? phone}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final token = p.getString(AppConstants.tokenKey);
      if (token == null) return;
      await http
          .put(Uri.parse('${AppConstants.apiUrl}/auth/profile'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token'
              },
              body: jsonEncode({
                'name': name ?? '',
                'bio': bio ?? '',
                'avatar_url': avatarUrl ?? '',
                'role': role ?? '',
                'phone': phone ?? ''
              }))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
    final present =
        _attendanceRecords.where((a) => a.status == 'present').length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FadeTransition(
          opacity: _fade,
          child: CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                    onPressed: () => _showEditProfile(context, auth)),
                IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white),
                    onPressed: () => _showSettings(context, auth)),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [themeColor, AppColors.purple],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight)),
                  child: Stack(children: [
                    Positioned(
                        top: -40,
                        right: -40,
                        child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.07)))),
                    Positioned(
                        bottom: -20,
                        left: -20,
                        child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05)))),
                    Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 56),
                          GestureDetector(
                              onTap: () => _showPhotoOptions(context),
                              child: Stack(children: [
                                Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 3),
                                        boxShadow: [
                                          BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8))
                                        ],
                                        color: themeColor.withOpacity(0.5)),
                                    child: _uploadingPhoto
                                        ? const Padding(
                                            padding: EdgeInsets.all(28),
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : _photoBytes != null
                                            ? ClipOval(
                                                child: Image.memory(_photoBytes!,
                                                    width: 96,
                                                    height: 96,
                                                    fit: BoxFit.cover))
                                            : _serverAvatarUrl.isNotEmpty
                                                ? ClipOval(
                                                    child: CachedNetworkImage(
                                                        imageUrl: _serverAvatarUrl.startsWith('http')
                                                            ? _serverAvatarUrl
                                                            : '${AppConstants.serverUrl}$_serverAvatarUrl',
                                                        width: 96,
                                                        height: 96,
                                                        fit: BoxFit.cover,
                                                        placeholder: (_, __) =>
                                                            const Padding(
                                                                padding:
                                                                    EdgeInsets.all(
                                                                        28),
                                                                child: CircularProgressIndicator(
                                                                    color: Colors
                                                                        .white,
                                                                    strokeWidth:
                                                                        2)),
                                                        errorWidget: (_, __, ___) =>
                                                            Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)))))
                                                : Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)))),
                                Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: themeColor, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.15),
                                                  blurRadius: 8)
                                            ]),
                                        child: Icon(Icons.camera_alt_rounded,
                                            size: 15, color: themeColor))),
                                Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                            color: AppColors.online,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white,
                                                width: 2)))),
                              ])),
                          const SizedBox(height: 12),
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text('$role${dept.isNotEmpty ? ' · $dept' : ''}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13)),
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 40),
                                child: Text(bio,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 12),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                          const SizedBox(height: 10),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _StatusBadge(
                                    label: 'Online',
                                    icon: Icons.circle,
                                    color: AppColors.online),
                                const SizedBox(width: 8),
                                _StatusBadge(
                                    label: '$present days present',
                                    icon: Icons.calendar_today_rounded,
                                    color: Colors.white70),
                              ]),
                        ]),
                  ]),
                ),
              ),
            ),
            SliverToBoxAdapter(
                child: Column(children: [
              const SizedBox(height: 20),

              // Quick stats row
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _QuickStat(
                        label: 'Email',
                        value: email.split('@').first,
                        icon: Icons.email_rounded,
                        color: themeColor),
                    const SizedBox(width: 10),
                    _QuickStat(
                        label: 'Department',
                        value: dept.isNotEmpty ? dept : 'General',
                        icon: Icons.business_rounded,
                        color: AppColors.purple),
                    const SizedBox(width: 10),
                    _QuickStat(
                        label: 'Present',
                        value: '$present days',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.online),
                  ])),
              const SizedBox(height: 20),

              // Features
              _ProfileSection(title: 'FEATURES', items: [
                _ProfileItem(
                    icon: Icons.people_rounded,
                    label: 'Contacts & Org Chart',
                    subtitle: 'View team directory',
                    color: AppColors.accent,
                    gradient: AppColors.accentGrad,
                    onTap: () => Navigator.push(
                        context, _route(const ContactsScreen()))),
                _ProfileItem(
                    icon: Icons.folder_rounded,
                    label: 'File Manager',
                    subtitle: 'Browse shared files',
                    color: AppColors.orange,
                    gradient: AppColors.orangeGrad,
                    onTap: () =>
                        Navigator.push(context, _route(const FilesScreen()))),
                _ProfileItem(
                    icon: Icons.auto_awesome_rounded,
                    label: 'AI Assistant',
                    subtitle: 'Ask anything',
                    color: AppColors.purple,
                    gradient: AppColors.purpleGrad,
                    onTap: () =>
                        Navigator.push(context, _route(const AIChatScreen()))),
              ]),

              _ProfileSection(title: 'WORKSPACE', items: [
                _ProfileItem(
                    icon: Icons.task_alt_rounded,
                    label: 'My Tasks',
                    subtitle: 'View assigned tasks',
                    color: themeColor,
                    gradient: AppColors.primaryGrad,
                    onTap: () =>
                        Navigator.push(context, _route(const TasksScreen()))),
                _ProfileItem(
                    icon: Icons.access_time_rounded,
                    label: 'Attendance History',
                    subtitle: '$present days present',
                    color: AppColors.online,
                    gradient: AppColors.emeraldGrad,
                    onTap: () => _showAttendanceHistory(context)),
              ]),

              _ProfileSection(title: 'ACCOUNT', items: [
                _ProfileItem(
                    icon: Icons.palette_rounded,
                    label: 'Theme & Appearance',
                    subtitle: 'Customize colors',
                    color: AppColors.purple,
                    gradient: AppColors.purpleGrad,
                    onTap: () => _showThemeSettings(context, auth)),
                _ProfileItem(
                    icon: Icons.lock_rounded,
                    label: 'Change Password',
                    subtitle: 'Update security',
                    color: AppColors.primary,
                    gradient: AppColors.primaryGrad,
                    onTap: () => _showChangePassword(context)),
                _ProfileItem(
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    subtitle: 'See you soon!',
                    color: AppColors.busy,
                    gradient: const LinearGradient(
                        colors: [AppColors.busy, Color(0xFFFF6B6B)]),
                    onTap: () => _signOut(context, auth),
                    isDanger: true),
              ]),

              const SizedBox(height: 100),
            ])),
          ])),
    );
  }

  PageRoute _route(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child),
      );

  void _showPhotoOptions(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
              decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PhotoOption(
                          icon: Icons.photo_library_rounded,
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
                                  final result = await ApiService.uploadMedia(
                                      fileName, bytes);
                                  final serverUrl =
                                      result['url'] as String? ?? '';
                                  if (serverUrl.isNotEmpty) {
                                    await _savePhotoUrl(serverUrl);
                                    await _updateProfileOnServer(
                                        avatarUrl: serverUrl);
                                    try {
                                      final updated = await ApiService.getMe();
                                      if (mounted) authRef.updateUser(updated);
                                    } catch (_) {}
                                    if (mounted)
                                      setState(() {
                                        _serverAvatarUrl = serverUrl;
                                        _photoBytes = null;
                                        _uploadingPhoto = false;
                                      });
                                    _snack('✅ Photo saved!', AppColors.online);
                                  } else {
                                    throw Exception('no url');
                                  }
                                } catch (_) {
                                  await _savePhotoLocally(bytes);
                                  await _updateProfileOnServer(
                                      avatarUrl:
                                          'local:${base64Encode(bytes)}');
                                  if (mounted)
                                    setState(() {
                                      _photoBytes = bytes;
                                      _uploadingPhoto = false;
                                    });
                                  _snack('✅ Photo saved!', AppColors.online);
                                }
                              }
                            } catch (_) {
                              if (mounted)
                                setState(() => _uploadingPhoto = false);
                            }
                          }),
                      _PhotoOption(
                          icon: Icons.delete_outline_rounded,
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
            ));
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
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
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
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person_outline_rounded))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: bioCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Bio',
                            prefixIcon: Icon(Icons.info_outline_rounded),
                            alignLabelWithHint: true)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: roleCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Job Role',
                            prefixIcon: Icon(Icons.work_outline_rounded))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: 'Phone',
                            prefixIcon: Icon(Icons.phone_outlined))),
                    const SizedBox(height: 20),
                    Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                            gradient: AppColors.primaryGrad,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6))
                            ]),
                        child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _updateProfileOnServer(
                                  name: nameCtrl.text.trim(),
                                  bio: bioCtrl.text.trim(),
                                  role: roleCtrl.text.trim(),
                                  phone: phoneCtrl.text.trim());
                              try {
                                final updated = await ApiService.getMe();
                                if (mounted) auth.updateUser(updated);
                              } catch (_) {}
                              _snack('✅ Profile updated!', AppColors.online);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14))),
                            child: const Text('Save Changes',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)))),
                  ])),
            ));
  }

  void _showChangePassword(BuildContext context) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool loading = false, showOld = false, showNew = false, showConf = false;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => Container(
                  decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28))),
                  padding: EdgeInsets.fromLTRB(24, 16, 24,
                      MediaQuery.of(context).viewInsets.bottom + 32),
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
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                    icon: Icon(showOld
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded),
                                    onPressed: () =>
                                        setS(() => showOld = !showOld)))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: newCtrl,
                            obscureText: !showNew,
                            decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon:
                                    const Icon(Icons.lock_reset_rounded),
                                suffixIcon: IconButton(
                                    icon: Icon(showNew
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded),
                                    onPressed: () =>
                                        setS(() => showNew = !showNew)))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: confCtrl,
                            obscureText: !showConf,
                            decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                prefixIcon: const Icon(
                                    Icons.check_circle_outline_rounded),
                                suffixIcon: IconButton(
                                    icon: Icon(showConf
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded),
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
                                          _snack('Min 6 characters',
                                              AppColors.busy);
                                          return;
                                        }
                                        setS(() => loading = true);
                                        try {
                                          final p = await SharedPreferences
                                              .getInstance();
                                          final token = p
                                              .getString(AppConstants.tokenKey);
                                          final resp = await http
                                              .post(
                                                  Uri.parse(
                                                      '${AppConstants.apiUrl}/auth/change-password'),
                                                  headers: {
                                                    'Content-Type':
                                                        'application/json',
                                                    if (token != null)
                                                      'Authorization':
                                                          'Bearer $token'
                                                  },
                                                  body: jsonEncode({
                                                    'old_password':
                                                        oldCtrl.text,
                                                    'new_password': newCtrl.text
                                                  }))
                                              .timeout(
                                                  const Duration(seconds: 15));
                                          setS(() => loading = false);
                                          if (resp.statusCode == 200) {
                                            if (context.mounted)
                                              Navigator.pop(context);
                                            _snack('✅ Password changed!',
                                                AppColors.online);
                                          } else {
                                            _snack(
                                                jsonDecode(
                                                        resp.body)['error'] ??
                                                    'Failed',
                                                AppColors.busy);
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
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Text('Change Password'))),
                      ]),
                )));
  }

  void _showThemeSettings(BuildContext context, AuthProvider auth) =>
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ThemeSheet(auth: auth));
  void _showSettings(BuildContext context, AuthProvider auth) =>
      showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _SettingsSheet(auth: auth));

  Future<void> _signOut(BuildContext context, AuthProvider auth) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              content: const Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.busy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Sign Out')),
              ],
            ));
    if (ok == true && context.mounted) {
      await auth.logout();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
    }
  }

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
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(children: [
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(children: [
                      const Text('Attendance History',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context)),
                    ])),
                if (_loadingAttendance)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else ...[
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(children: [
                        _AttStatCard('Present', '$present', AppColors.online),
                        const SizedBox(width: 8),
                        _AttStatCard('Absent', '$absent', AppColors.busy),
                        const SizedBox(width: 8),
                        _AttStatCard('Total', '${_attendanceRecords.length}',
                            AppColors.primary),
                      ])),
                  Expanded(
                      child: _attendanceRecords.isEmpty
                          ? const Center(
                              child: Text('No records yet',
                                  style: TextStyle(color: AppColors.textMuted)))
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _attendanceRecords.length,
                              itemBuilder: (ctx, i) {
                                final a = _attendanceRecords[i];
                                final isPresent =
                                    a.status == 'present' || a.status == 'late';
                                final color = isPresent
                                    ? AppColors.online
                                    : AppColors.busy;
                                return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: color.withOpacity(0.15))),
                                    child: Row(children: [
                                      Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          child: Icon(
                                              isPresent
                                                  ? Icons
                                                      .check_circle_outline_rounded
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
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            Text(
                                                a.checkIn != null
                                                    ? '${_fmt(a.checkIn!)} → ${a.checkOut != null ? _fmt(a.checkOut!) : 'Still in'}'
                                                    : 'Absent',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors
                                                        .textSecondary)),
                                          ])),
                                      Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          child: Text(
                                              isPresent ? 'Present' : 'Absent',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: color))),
                                    ]));
                              })),
                ],
              ]),
            ));
  }

  String _fmt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusBadge(
      {required this.label, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 8),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _QuickStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                  color: color.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ));
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final List<_ProfileItem> items;
  const _ProfileSection({required this.title, required this.items});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2))),
        Container(
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child: Column(
                children: List.generate(
                    items.length,
                    (i) => Column(children: [
                          items[i],
                          if (i < items.length - 1)
                            const Divider(height: 1, indent: 68),
                        ])))),
      ]));
}

class _ProfileItem extends StatefulWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final bool isDanger;
  const _ProfileItem(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.gradient,
      required this.onTap,
      this.isDanger = false});
  @override
  State<_ProfileItem> createState() => _ProfileItemState();
}

class _ProfileItemState extends State<_ProfileItem> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _pressed ? widget.color.withOpacity(0.04) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    gradient: widget.gradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: widget.color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ]),
                child: Icon(widget.icon, color: Colors.white, size: 20)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.isDanger
                              ? AppColors.busy
                              : AppColors.textPrimary)),
                  Text(widget.subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ])),
            Icon(Icons.chevron_right_rounded,
                color: widget.isDanger
                    ? AppColors.busy.withOpacity(0.5)
                    : AppColors.textMuted,
                size: 20),
          ]),
        ),
      );
}

class _AttStatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AttStatCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ])));
}

class _PhotoOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PhotoOption(
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
      ]));
}

// ── AI Chat Screen ──────────────────────────────────────────────────────────
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
    'Give me productivity tips',
    'Help me write code',
    'Summarize a topic',
    'Draft a team message'
  ];

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'assistant',
      'content':
          'Hello! I\'m your AI Assistant 👋\n\nI can help with:\n• Writing emails & messages\n• Answering questions\n• Coding & debugging\n• Brainstorming ideas\n\nJust ask me anything!'
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
      final p = await SharedPreferences.getInstance();
      final token = p.getString(AppConstants.tokenKey);
      final resp = await http
          .post(Uri.parse('${AppConstants.apiUrl}/chat/ai'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token'
              },
              body: jsonEncode({'user_id': 'ai', 'message': text}))
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                  gradient: AppColors.purpleGrad, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Assistant',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Powered by Llama',
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
                      'content': 'New conversation! How can I help you?'
                    });
                  }))
        ],
      ),
      body: Column(children: [
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
                                      fontWeight: FontWeight.w500)))))
                      .toList())),
        Expanded(
            child: ListView.builder(
                controller: _scroll,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                itemCount: _messages.length + (_loading ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == _messages.length) return _TypingBubble();
                  final msg = _messages[i];
                  final isMe = msg['role'] == 'user';
                  return _AIChatBubble(
                      text: msg['content'] ?? '',
                      isMe: isMe,
                      themeColor: themeColor);
                })),
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
                            child: Icon(Icons.auto_awesome_rounded,
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
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10)))),
                      ]))),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: () => _send(),
                  child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                          gradient: AppColors.purpleGrad,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x558B5CF6),
                                blurRadius: 12,
                                offset: Offset(0, 4))
                          ]),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20))),
            ])),
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
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 16)),
              const SizedBox(width: 8)
            ],
            Flexible(
                child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        gradient: isMe
                            ? LinearGradient(colors: [
                                themeColor,
                                themeColor.withOpacity(0.85)
                              ])
                            : null,
                        color: isMe ? null : AppColors.surface,
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
                            height: 1.5)))),
          ]));
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
            child: const Icon(Icons.auto_awesome_rounded,
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
                    })))),
      ]));
}

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
    const Color(0xFF6C63FF),
    const Color(0xFF1A73E8),
    const Color(0xFF7C4DFF),
    const Color(0xFF00BCD4),
    const Color(0xFF22C55E),
    const Color(0xFFEF4444),
    const Color(0xFFFF6B35),
    const Color(0xFFE91E63),
    const Color(0xFFF59E0B),
    const Color(0xFF000000)
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
          const Text('Theme & Appearance',
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
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 46,
                          height: 46,
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
                                          blurRadius: 10,
                                          spreadRadius: 2)
                                    ]
                                  : null),
                          child: _color.value == c.value
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 22)
                              : null)))
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
            const Icon(Icons.brightness_low_rounded,
                color: AppColors.textMuted),
            Expanded(
                child: Slider(
                    value: _brightness,
                    min: 0.3,
                    max: 1.0,
                    activeColor: _color,
                    onChanged: (v) {
                      setState(() => _brightness = v);
                      widget.auth.updateTheme(brightness: v);
                    })),
            const Icon(Icons.brightness_high_rounded,
                color: AppColors.textMuted),
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

class _SettingsSheet extends StatelessWidget {
  final AuthProvider auth;
  const _SettingsSheet({required this.auth});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
              leading: const Icon(Icons.language_rounded),
              title: const Text('Language'),
              trailing: const Text('English',
                  style: TextStyle(color: AppColors.textMuted)),
              contentPadding: EdgeInsets.zero),
          const SizedBox(height: 20),
        ]),
      );
}
