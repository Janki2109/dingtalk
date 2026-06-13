import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  List<ChatModel> _chats = [];
  Map<String, UserModel> _userMap = {};
  bool _loading = true;
  String _search = '';
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _load();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      await _loadSilent();
      return mounted;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results =
          await Future.wait([ApiService.getChats(), ApiService.getUsers()]);
      if (mounted)
        setState(() {
          _chats = results[0] as List<ChatModel>;
          _userMap = {for (final u in results[1] as List<UserModel>) u.id: u};
          _loading = false;
        });
      _anim.forward(from: 0);
    } catch (_) {
      if (mounted)
        setState(() {
          _chats = [];
          _loading = false;
        });
    }
  }

  Future<void> _loadSilent() async {
    try {
      final chats = await ApiService.getChats();
      if (mounted) setState(() => _chats = chats);
    } catch (_) {}
  }

  List<ChatModel> get _filtered => _chats
      .where((c) => c.name.toLowerCase().contains(_search.toLowerCase()))
      .toList();
  List<ChatModel> get _pinned => _filtered.where((c) => c.isPinned).toList();
  List<ChatModel> get _regular => _filtered.where((c) => !c.isPinned).toList();

  Future<void> _openChat(ChatModel chat) async {
    if (chat.unreadCount > 0) {
      setState(() {
        final idx = _chats.indexWhere((c) => c.id == chat.id);
        if (idx != -1)
          _chats[idx] = ChatModel(
              id: chat.id,
              name: chat.name,
              lastMessage: chat.lastMessage,
              lastTime: chat.lastTime,
              avatarUrl: chat.avatarUrl,
              isGroup: chat.isGroup,
              isPinned: chat.isPinned,
              isMuted: chat.isMuted,
              unreadCount: 0);
      });
      try {
        await ApiService.markChatRead(chat.id);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => ChatDetailScreen(
              chat: chat,
              currentUserId: context.read<AuthProvider>().user?.id ?? ''),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
              child: child),
        ));
    _load();
  }

  void _deleteChat(String id) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Delete Chat',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              content: const Text('Permanently delete this chat?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      setState(() => _chats.removeWhere((c) => c.id == id));
                      try {
                        await ApiService.deleteChat(id);
                        _snack('Chat deleted', AppColors.busy);
                      } catch (e) {
                        _snack('Failed to delete', AppColors.busy);
                        _load();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.busy,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Delete')),
              ],
            ));
  }

  void _muteChat(ChatModel chat) {
    _snack(
        chat.isMuted ? 'Chat unmuted' : 'Chat muted', AppColors.textSecondary);
    final idx = _chats.indexWhere((c) => c.id == chat.id);
    if (idx != -1)
      setState(() => _chats[idx] = ChatModel(
          id: chat.id,
          name: chat.name,
          lastMessage: chat.lastMessage,
          lastTime: chat.lastTime,
          avatarUrl: chat.avatarUrl,
          isGroup: chat.isGroup,
          isPinned: chat.isPinned,
          isMuted: !chat.isMuted,
          unreadCount: chat.unreadCount));
  }

  void _markAsRead(String id) async {
    try {
      await ApiService.markChatRead(id);
      final idx = _chats.indexWhere((c) => c.id == id);
      if (idx != -1 && mounted)
        setState(() {
          final c = _chats[idx];
          _chats[idx] = ChatModel(
              id: c.id,
              name: c.name,
              lastMessage: c.lastMessage,
              lastTime: c.lastTime,
              avatarUrl: c.avatarUrl,
              isGroup: c.isGroup,
              isPinned: c.isPinned,
              isMuted: c.isMuted,
              unreadCount: 0);
        });
      _snack('Marked as read', AppColors.online);
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

  void _showNewChatOptions() {
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
                const Text('New Conversation',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                _NewChatOption(
                    icon: Icons.person_rounded,
                    label: 'Direct Message',
                    subtitle: 'Chat one-on-one',
                    gradient: AppColors.primaryGrad,
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.pop(context);
                      _showNewChat(isGroup: false);
                    }),
                const SizedBox(height: 12),
                _NewChatOption(
                    icon: Icons.group_rounded,
                    label: 'Group Chat',
                    subtitle: 'Create a group',
                    gradient: AppColors.purpleGrad,
                    color: AppColors.purple,
                    onTap: () {
                      Navigator.pop(context);
                      _showNewChat(isGroup: true);
                    }),
                const SizedBox(height: 20),
              ]),
            ));
  }

  Future<void> _showNewChat({required bool isGroup}) async {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _NewChatSheet(
            currentUserId: context.read<AuthProvider>().user?.id ?? '',
            isGroup: isGroup,
            onChatCreated: (chat) async {
              setState(() {
                if (!_chats.any((c) => c.id == chat.id)) _chats.insert(0, chat);
              });
              await _openChat(chat);
            }));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final themeColor = context.watch<AuthProvider>().themeColor;
    final totalUnread = _chats.fold<int>(0, (sum, c) => sum + c.unreadCount);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Row(children: [
            const Text('Messages',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            if (totalUnread > 0) ...[
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      gradient: AppColors.primaryGrad,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('$totalUnread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800))),
            ],
          ]),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded), onPressed: _load)
          ],
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                        color: AppColors.surfaceVar,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border)),
                    child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                            hintText: 'Search conversations...',
                            hintStyle: const TextStyle(
                                color: AppColors.textMuted, fontSize: 14),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.textMuted, size: 20),
                            border: InputBorder.none,
                            filled: false,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12))),
                  ))),
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else if (_filtered.isEmpty)
          SliverFillRemaining(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        gradient: AppColors.primaryGrad,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ]),
                    child: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 36, color: Colors.white)),
                const SizedBox(height: 16),
                const Text('No conversations yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('Tap + to start a new chat',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: _showNewChatOptions,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Start New Chat'),
                    style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12))),
              ]))
        else ...[
          if (_pinned.isNotEmpty) ...[
            SliverToBoxAdapter(
                child:
                    _SectionLabel('📌 Pinned', _pinned.length, AppColors.away)),
            SliverList(
                delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _ChatTile(
                        chat: _pinned[i],
                        currentUserId: user?.id ?? '',
                        userMap: _userMap,
                        themeColor: themeColor,
                        onTap: () => _openChat(_pinned[i]),
                        onDelete: () => _deleteChat(_pinned[i].id),
                        onMarkRead: () => _markAsRead(_pinned[i].id),
                        onMute: () => _muteChat(_pinned[i])),
                    childCount: _pinned.length)),
          ],
          SliverToBoxAdapter(
              child: _SectionLabel(
                  'Recent', _regular.length, AppColors.textMuted)),
          SliverList(
              delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ChatTile(
                      chat: _regular[i],
                      currentUserId: user?.id ?? '',
                      userMap: _userMap,
                      themeColor: themeColor,
                      onTap: () => _openChat(_regular[i]),
                      onDelete: () => _deleteChat(_regular[i].id),
                      onMarkRead: () => _markAsRead(_regular[i].id),
                      onMute: () => _muteChat(_regular[i])),
                  childCount: _regular.length)),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ]),
      floatingActionButton: FloatingActionButton(
          onPressed: _showNewChatOptions,
          backgroundColor: themeColor,
          elevation: 4,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionLabel(this.title, this.count, this.color);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
        const SizedBox(width: 6),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color))),
      ]));
}

class _ChatTile extends StatefulWidget {
  final ChatModel chat;
  final String currentUserId;
  final Map<String, UserModel> userMap;
  final VoidCallback onTap, onDelete, onMarkRead, onMute;
  final Color themeColor;
  const _ChatTile(
      {required this.chat,
      required this.currentUserId,
      required this.userMap,
      required this.onTap,
      required this.onDelete,
      required this.onMarkRead,
      required this.onMute,
      required this.themeColor});
  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  bool _pressed = false;

  String get _displayName => widget.chat.name;
  UserModel? get _otherUser {
    if (widget.chat.isGroup) return null;
    try {
      return widget.userMap.values.firstWhere(
          (u) => u.name == widget.chat.name && u.id != widget.currentUserId);
    } catch (_) {
      return null;
    }
  }

  String get _statusText {
    if (widget.chat.isGroup) return 'Group';
    final u = _otherUser;
    if (u == null || u.id.isEmpty) return '';
    return u.lastSeenText;
  }

  Color get _statusColor {
    if (widget.chat.isGroup) return AppColors.textMuted;
    final u = _otherUser;
    if (u == null || u.id.isEmpty) return AppColors.textMuted;
    return u.statusColor;
  }

  @override
  Widget build(BuildContext context) {
    final isAI = widget.chat.id == 'ai';
    final hasUnread = widget.chat.unreadCount > 0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: () => _showMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color:
            _pressed ? widget.themeColor.withOpacity(0.05) : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Stack(children: [
            widget.chat.isGroup
                ? const GroupAvatar(size: 54)
                : isAI
                    ? const AIAvatar(size: 54)
                    : UserAvatar(name: _displayName, size: 54),
            if (isAI)
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                          gradient: AppColors.purpleGrad,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 10))),
            if (!widget.chat.isGroup && !isAI)
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: _statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  if (isAI)
                    Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            gradient: AppColors.purpleGrad,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('AI',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800))),
                  if (widget.chat.isGroup)
                    Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('Group',
                            style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 9,
                                fontWeight: FontWeight.w700))),
                  Expanded(
                      child: Text(_displayName,
                          style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis)),
                  Text(formatTime(widget.chat.lastTime),
                      style: TextStyle(
                          fontSize: 11,
                          color: hasUnread
                              ? widget.themeColor
                              : AppColors.textMuted,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w400)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                      child: Text(
                          widget.chat.lastMessage.isNotEmpty
                              ? widget.chat.lastMessage
                              : _statusText,
                          style: TextStyle(
                              fontSize: 13,
                              color: hasUnread
                                  ? AppColors.textSecondary
                                  : AppColors.textMuted,
                              fontWeight: hasUnread
                                  ? FontWeight.w500
                                  : FontWeight.w400),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  if (widget.chat.isMuted)
                    const Icon(Icons.volume_off_rounded,
                        size: 13, color: AppColors.textMuted),
                  if (hasUnread) ...[
                    const SizedBox(width: 6),
                    UnreadBadge(count: widget.chat.unreadCount)
                  ],
                ]),
              ])),
        ]),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
              decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                      widget.chat.isGroup
                          ? const GroupAvatar(size: 44)
                          : UserAvatar(name: _displayName, size: 44),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_displayName,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            Text(_statusText,
                                style: TextStyle(
                                    fontSize: 12, color: _statusColor)),
                          ]),
                    ])),
                const Divider(height: 1),
                _MenuOption(
                    icon: Icons.mark_chat_read_rounded,
                    label: 'Mark as Read',
                    color: AppColors.online,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onMarkRead();
                    }),
                _MenuOption(
                    icon: widget.chat.isMuted
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: widget.chat.isMuted ? 'Unmute' : 'Mute',
                    color: AppColors.textSecondary,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onMute();
                    }),
                const Divider(height: 1),
                _MenuOption(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete Chat',
                    color: AppColors.busy,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    }),
                const SizedBox(height: 16),
              ]),
            ));
  }
}

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuOption(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20)),
        title: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color == AppColors.busy
                    ? AppColors.busy
                    : AppColors.textPrimary)),
        onTap: onTap,
      );
}

class _NewChatOption extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final LinearGradient gradient;
  final Color color;
  final VoidCallback onTap;
  const _NewChatOption(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.gradient,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Row(children: [
            Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    gradient: gradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]),
                child: Icon(icon, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ])),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
          ])));
}

class _NewChatSheet extends StatefulWidget {
  final String currentUserId;
  final bool isGroup;
  final Function(ChatModel) onChatCreated;
  const _NewChatSheet(
      {required this.currentUserId,
      required this.isGroup,
      required this.onChatCreated});
  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  List<UserModel> _users = [];
  bool _loading = true;
  String _search = '';
  Set<String> _selectedIds = {};
  Set<String> _selectedNames = {};
  final _groupNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ApiService.getUsers();
      if (mounted)
        setState(() {
          _users = users.where((u) => u.id != widget.currentUserId).toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<UserModel> get _filtered => _users
      .where((u) =>
          u.name.toLowerCase().contains(_search.toLowerCase()) ||
          u.email.toLowerCase().contains(_search.toLowerCase()))
      .toList();

  Future<void> _startDirectChat(UserModel user) async {
    Navigator.pop(context);
    try {
      final chatId = await ApiService.createDirectChat(user.id);
      widget.onChatCreated(ChatModel(
          id: chatId,
          name: user.name,
          lastMessage: 'Tap to start chatting',
          lastTime: DateTime.now(),
          unreadCount: 0));
    } catch (_) {
      widget.onChatCreated(ChatModel(
          id: 'local_${user.id}',
          name: user.name,
          lastMessage: 'Tap to start chatting',
          lastTime: DateTime.now(),
          unreadCount: 0));
    }
  }

  Future<void> _createGroup() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select at least one person'),
          backgroundColor: AppColors.busy,
          behavior: SnackBarBehavior.floating));
      return;
    }
    final groupName = _groupNameCtrl.text.trim().isNotEmpty
        ? _groupNameCtrl.text.trim()
        : _selectedNames.take(2).join(', ') +
            (_selectedNames.length > 2 ? ' +${_selectedNames.length - 2}' : '');
    Navigator.pop(context);
    try {
      final chatId =
          await ApiService.createGroupChat(groupName, _selectedIds.toList());
      widget.onChatCreated(ChatModel(
          id: chatId,
          name: groupName,
          lastMessage: 'Group created',
          lastTime: DateTime.now(),
          unreadCount: 0,
          isGroup: true));
    } catch (_) {
      widget.onChatCreated(ChatModel(
          id: 'group_${DateTime.now().millisecondsSinceEpoch}',
          name: groupName,
          lastMessage: 'Group created',
          lastTime: DateTime.now(),
          unreadCount: 0,
          isGroup: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      gradient: widget.isGroup
                          ? AppColors.purpleGrad
                          : AppColors.primaryGrad,
                      shape: BoxShape.circle),
                  child: Icon(
                      widget.isGroup
                          ? Icons.group_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 18)),
              const SizedBox(width: 12),
              Text(widget.isGroup ? 'New Group Chat' : 'New Message',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context)),
            ])),
        if (widget.isGroup)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                  controller: _groupNameCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Group name (optional)',
                      prefixIcon: Icon(Icons.edit_rounded, size: 18)))),
        if (widget.isGroup && _selectedIds.isNotEmpty)
          SizedBox(
              height: 70,
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: _selectedNames
                      .map((name) => Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(children: [
                            Stack(
                              children: [
                                UserAvatar(name: name, size: 38),
                                Positioned(
                                    top: -2,
                                    right: -2,
                                    child: GestureDetector(
                                        onTap: () {
                                          final u = _users.firstWhere(
                                              (u) => u.name == name,
                                              orElse: () => const UserModel(
                                                  id: '', name: '', email: ''));
                                          setState(() {
                                            _selectedIds.remove(u.id);
                                            _selectedNames.remove(name);
                                          });
                                        },
                                        child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: const BoxDecoration(
                                                color: AppColors.busy,
                                                shape: BoxShape.circle),
                                            child: const Icon(
                                                Icons.close_rounded,
                                                color: Colors.white,
                                                size: 10))))
                              ],
                            ),
                            Text(name.split(' ').first,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary)),
                          ])))
                      .toList())),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
                autofocus: !widget.isGroup,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                    hintText: widget.isGroup
                        ? 'Search and add people...'
                        : 'Search by name or email...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceVar,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12)))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(children: [
              Text(widget.isGroup ? 'Select People' : 'Registered Users',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              if (widget.isGroup && _selectedIds.isNotEmpty) ...[
                const Spacer(),
                Text('${_selectedIds.length} selected',
                    style: TextStyle(
                        fontSize: 12,
                        color: themeColor,
                        fontWeight: FontWeight.w600))
              ],
            ])),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                            _search.isEmpty
                                ? 'No other users registered yet'
                                : 'No users found',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 14)))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final u = _filtered[i];
                          final isSelected = _selectedIds.contains(u.id);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            leading: Stack(children: [
                              UserAvatar(
                                  name: u.name, size: 46, status: u.status),
                              Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: u.statusColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2))))
                            ]),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: Text(u.email,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                            trailing: widget.isGroup
                                ? GestureDetector(
                                    onTap: () => setState(() {
                                          if (isSelected) {
                                            _selectedIds.remove(u.id);
                                            _selectedNames.remove(u.name);
                                          } else {
                                            _selectedIds.add(u.id);
                                            _selectedNames.add(u.name);
                                          }
                                        }),
                                    child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                            gradient: isSelected
                                                ? AppColors.primaryGrad
                                                : null,
                                            color: isSelected
                                                ? null
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: isSelected
                                                    ? Colors.transparent
                                                    : AppColors.border,
                                                width: 2)),
                                        child: isSelected
                                            ? const Icon(Icons.check_rounded,
                                                color: Colors.white, size: 16)
                                            : null))
                                : GestureDetector(
                                    onTap: () => _startDirectChat(u),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: themeColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: themeColor
                                                    .withOpacity(0.3))),
                                        child: Text('Message',
                                            style: TextStyle(
                                                color: themeColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)))),
                            onTap: widget.isGroup
                                ? () => setState(() {
                                      if (isSelected) {
                                        _selectedIds.remove(u.id);
                                        _selectedNames.remove(u.name);
                                      } else {
                                        _selectedIds.add(u.id);
                                        _selectedNames.add(u.name);
                                      }
                                    })
                                : () => _startDirectChat(u),
                          );
                        })),
        if (widget.isGroup)
          Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                      gradient: AppColors.purpleGrad,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.purple.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6))
                      ]),
                  child: ElevatedButton.icon(
                      onPressed: _selectedIds.isEmpty ? null : _createGroup,
                      icon: const Icon(Icons.group_add_rounded, size: 18),
                      label: Text(
                          _selectedIds.isEmpty
                              ? 'Select people to create group'
                              : 'Create Group (${_selectedIds.length} people)',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: AppColors.border,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)))))),
      ]),
    );
  }
}
