import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../chat/screens/chat_detail_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<UserModel> _users = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await ApiService.getUsers();
      if (mounted)
        setState(() {
          _users = users;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Open chat with a workspace user
  Future<void> _openChat(UserModel user) async {
    final currentUser = context.read<AuthProvider>().user;
    if (currentUser == null) return;
    try {
      final chatId = await ApiService.createDirectChat(user.id);
      if (!mounted) return;
      final chat = ChatModel(
        id: chatId,
        name: user.name,
        lastMessage: '',
        lastTime: DateTime.now(),
        unreadCount: 0,
      );
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatDetailScreen(chat: chat, currentUserId: currentUser.id),
          ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.busy,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  List<UserModel> get _filtered => _users
      .where((u) =>
          u.name.toLowerCase().contains(_search.toLowerCase()) ||
          u.email.toLowerCase().contains(_search.toLowerCase()))
      .toList();

  Map<String, List<UserModel>> get _byDept {
    final map = <String, List<UserModel>>{};
    for (final u in _filtered) {
      map
          .putIfAbsent(
              u.department.isEmpty ? 'General' : u.department, () => [])
          .add(u);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            title: const Text('Contacts & Org',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh, size: 22), onPressed: _load),
            ],
            bottom: TabBar(
              controller: _tab,
              labelColor: themeColor,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: themeColor,
              tabs: const [
                Tab(text: 'Contacts'),
                Tab(text: 'Org Chart'),
              ],
            ),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _tab, children: [
                // ── Contacts Tab ─────────────────────────────────────────
                ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceVar,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: Text('No contacts found',
                              style: TextStyle(color: AppColors.textMuted))),
                    )
                  else
                    ..._byDept.entries.map((e) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary)),
                            ),
                            ...e.value.map((u) => _ContactTile(
                                user: u, onMessage: () => _openChat(u))),
                          ],
                        )),
                  const SizedBox(height: 90),
                ]),

                // ── Org Chart Tab ────────────────────────────────────────
                ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Company Structure',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 16),

                  // Admins at top
                  ..._users.where((u) => u.isAdmin).map((u) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: themeColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: themeColor.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          UserAvatar(name: u.name, size: 52, status: u.status),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Text(u.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: themeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text('Admin',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: themeColor,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                                Text(u.role,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13)),
                                Text(u.department,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                              ])),
                          IconButton(
                            icon: Icon(Icons.chat_bubble_outline,
                                color: themeColor),
                            onPressed: () => _openChat(u),
                          ),
                        ]),
                      )),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  const Text('Employees',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),

                  // Employees grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.85,
                    children: _users
                        .where((u) => !u.isAdmin)
                        .map((u) => GestureDetector(
                              onTap: () => _openChat(u),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      UserAvatar(
                                          name: u.name,
                                          size: 42,
                                          status: u.status),
                                      const SizedBox(height: 8),
                                      Text(u.name,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(u.role,
                                          style: const TextStyle(
                                              fontSize: 9,
                                              color: AppColors.textMuted),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Icon(Icons.chat_bubble_outline,
                                          size: 14, color: themeColor),
                                    ]),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 90),
                ]),
              ]),
      ),
    );
  }
}

// ── Contact Tile ──────────────────────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onMessage;
  const _ContactTile({required this.user, required this.onMessage});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: UserAvatar(name: user.name, size: 46, status: user.status),
        title: Text(user.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${user.role} · ${user.department}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Row(children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 4, top: 2),
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _statusColor(user.status)),
            ),
            Text(user.status,
                style: TextStyle(
                    fontSize: 11,
                    color: _statusColor(user.status),
                    fontWeight: FontWeight.w500)),
          ]),
        ]),
        // ✅ Only message button — no call button
        trailing: ElevatedButton.icon(
          onPressed: onMessage,
          icon: const Icon(Icons.chat_bubble_outline, size: 14),
          label: const Text('Message', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        onTap: () => _showProfile(context),
      );

  Color _statusColor(String s) {
    switch (s) {
      case 'online':
        return AppColors.online;
      case 'busy':
        return AppColors.busy;
      case 'away':
        return AppColors.away;
      default:
        return AppColors.textMuted;
    }
  }

  void _showProfile(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            UserAvatar(name: user.name, size: 72, status: user.status),
            const SizedBox(height: 14),
            Text(user.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(user.role,
                style: const TextStyle(color: AppColors.textSecondary)),
            Text(user.email,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: _statusColor(user.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(user.status,
                  style: TextStyle(
                      color: _statusColor(user.status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 24),
            // ✅ Message + Email only
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Btn(Icons.chat_bubble_outline, 'Message', AppColors.primary, () {
                Navigator.pop(context);
                onMessage();
              }),
              const SizedBox(width: 20),
              _Btn(Icons.email_outlined, 'Email', AppColors.purple,
                  () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 20),
          ]),
        ),
      );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Btn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24)),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}
