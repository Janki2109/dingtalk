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

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatModel> _chats = [];
  Map<String, UserModel> _userMap = {};
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      await _loadSilent();
      return mounted;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getChats(),
        ApiService.getUsers(),
      ]);
      final chats = results[0] as List<ChatModel>;
      final users = results[1] as List<UserModel>;
      if (mounted)
        setState(() {
          _chats = chats;
          _userMap = {for (final u in users) u.id: u};
          _loading = false;
        });
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
        if (idx != -1) {
          _chats[idx] = ChatModel(
            id: chat.id,
            name: chat.name,
            lastMessage: chat.lastMessage,
            lastTime: chat.lastTime,
            avatarUrl: chat.avatarUrl,
            isGroup: chat.isGroup,
            isPinned: chat.isPinned,
            isMuted: chat.isMuted,
            unreadCount: 0,
          );
        }
      });
      try {
        await ApiService.markChatRead(chat.id);
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chat: chat,
            currentUserId: context.read<AuthProvider>().user?.id ?? '',
          ),
        ));
    _load();
  }

  void _deleteChat(String id) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Delete Chat',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              content: const Text('Remove this chat from your list?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _chats.removeWhere((c) => c.id == id));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Chat removed'),
                      backgroundColor: AppColors.busy,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  },
                  style:
                      ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
                  child: const Text('Delete'),
                ),
              ],
            ));
  }

  void _showNewChatOptions() {
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
          const Text('New Conversation',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showNewChat(isGroup: false);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.primary.withOpacity(0.3))),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                        gradient: AppColors.primaryGrad,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.person,
                        color: Colors.white, size: 24)),
                const SizedBox(width: 14),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Direct Message',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                      Text('Chat one-on-one with someone',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ])),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.primary),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _showNewChat(isGroup: true);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.purple.withOpacity(0.3))),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                        gradient: AppColors.purpleGrad, shape: BoxShape.circle),
                    child:
                        const Icon(Icons.group, color: Colors.white, size: 24)),
                const SizedBox(width: 14),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Group Chat',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.purple)),
                      Text('Create a group with multiple people',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ])),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: AppColors.purple),
              ]),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          title: const Text('Messages',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: AppSearchBar(
                hint: 'Search conversations...',
                onChanged: (v) => setState(() => _search = v)),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
        else if (_filtered.isEmpty)
          SliverFillRemaining(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.chat_bubble_outline,
                  size: 72, color: AppColors.textMuted.withOpacity(0.3)),
              const SizedBox(height: 16),
              const Text('No conversations yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              const Text('Tap + to start chatting',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                  onPressed: _showNewChatOptions,
                  icon: const Icon(Icons.add),
                  label: const Text('Start New Chat')),
            ]),
          )
        else ...[
          if (_pinned.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: '📌 Pinned')),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (ctx, i) => _ChatTile(
                chat: _pinned[i],
                currentUserId: user?.id ?? '',
                userMap: _userMap,
                onTap: () => _openChat(_pinned[i]),
                onDelete: () => _deleteChat(_pinned[i].id),
                onMarkRead: () async {
                  await ApiService.markChatRead(_pinned[i].id);
                  _load();
                },
                themeColor: themeColor,
              ),
              childCount: _pinned.length,
            )),
          ],
          const SliverToBoxAdapter(child: SectionHeader(title: 'Recent')),
          SliverList(
              delegate: SliverChildBuilderDelegate(
            (ctx, i) => _ChatTile(
              chat: _regular[i],
              currentUserId: user?.id ?? '',
              userMap: _userMap,
              onTap: () => _openChat(_regular[i]),
              onDelete: () => _deleteChat(_regular[i].id),
              onMarkRead: () async {
                await ApiService.markChatRead(_regular[i].id);
                _load();
              },
              themeColor: themeColor,
            ),
            childCount: _regular.length,
          )),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewChatOptions,
        backgroundColor: themeColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatModel chat;
  final String currentUserId;
  final Map<String, UserModel> userMap;
  final VoidCallback onTap, onDelete, onMarkRead;
  final Color themeColor;

  const _ChatTile({
    required this.chat,
    required this.currentUserId,
    required this.userMap,
    required this.onTap,
    required this.onDelete,
    required this.onMarkRead,
    required this.themeColor,
  });

  String get _displayName => chat.name;

  UserModel? get _otherUser {
    if (chat.isGroup) return null;
    try {
      return userMap.values
          .firstWhere((u) => u.name == chat.name && u.id != currentUserId);
    } catch (_) {
      return null;
    }
  }

  String get _statusText {
    if (chat.isGroup) return 'Group';
    final u = _otherUser;
    if (u == null || u.id.isEmpty) return '';
    return u.lastSeenText;
  }

  Color get _statusColor {
    if (chat.isGroup) return AppColors.textMuted;
    final u = _otherUser;
    if (u == null || u.id.isEmpty) return AppColors.textMuted;
    return u.statusColor;
  }

  @override
  Widget build(BuildContext context) {
    final isAI = chat.id == 'ai';
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showLongPressMenu(context),
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Stack(children: [
            chat.isGroup
                ? const GroupAvatar(size: 52)
                : isAI
                    ? const AIAvatar(size: 52)
                    : UserAvatar(name: _displayName, size: 52),
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
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 10))),
            if (!chat.isGroup && !isAI)
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
                        margin: const EdgeInsets.only(right: 6),
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
                  if (chat.isGroup)
                    Container(
                        margin: const EdgeInsets.only(right: 6),
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
                              fontWeight: chat.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis)),
                  Text(formatTime(chat.lastTime),
                      style: TextStyle(
                          fontSize: 11,
                          color: chat.unreadCount > 0
                              ? themeColor
                              : AppColors.textMuted)),
                ]),
                const SizedBox(height: 3),
                // ✅ FIXED: Show last message for ALL chats like WhatsApp
                Row(children: [
                  Expanded(
                      child: Text(
                    chat.lastMessage.isNotEmpty
                        ? chat.lastMessage
                        : _statusText,
                    style: TextStyle(
                        fontSize: 13,
                        color: chat.unreadCount > 0
                            ? AppColors.textSecondary
                            : AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                  if (chat.isMuted)
                    const Icon(Icons.volume_off,
                        size: 13, color: AppColors.textMuted),
                  if (chat.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    UnreadBadge(count: chat.unreadCount),
                  ],
                ]),
              ])),
        ]),
      ),
    );
  }

  void _showLongPressMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              chat.isGroup
                  ? const GroupAvatar(size: 44)
                  : UserAvatar(name: _displayName, size: 44),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text(_statusText,
                    style: TextStyle(fontSize: 12, color: _statusColor)),
              ]),
            ]),
          ),
          const Divider(height: 1),
          _Option(
              icon: Icons.mark_chat_read_outlined,
              label: 'Mark as Read',
              color: AppColors.online,
              onTap: () {
                Navigator.pop(context);
                onMarkRead();
              }),
          _Option(
              icon: Icons.push_pin_outlined,
              label: 'Pin Chat',
              color: AppColors.primary,
              onTap: () => Navigator.pop(context)),
          _Option(
              icon: Icons.volume_off_outlined,
              label: 'Mute Notifications',
              color: AppColors.textSecondary,
              onTap: () => Navigator.pop(context)),
          const Divider(height: 1),
          _Option(
              icon: Icons.delete_outline,
              label: 'Delete Chat',
              color: AppColors.busy,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              }),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Option(
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
                borderRadius: BorderRadius.circular(10)),
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
        unreadCount: 0,
      ));
    } catch (_) {
      widget.onChatCreated(ChatModel(
        id: 'local_${user.id}',
        name: user.name,
        lastMessage: 'Tap to start chatting',
        lastTime: DateTime.now(),
        unreadCount: 0,
      ));
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
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    gradient: widget.isGroup
                        ? AppColors.purpleGrad
                        : AppColors.primaryGrad,
                    shape: BoxShape.circle),
                child: Icon(widget.isGroup ? Icons.group : Icons.person,
                    color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Text(widget.isGroup ? 'New Group Chat' : 'New Message',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        if (widget.isGroup)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                  controller: _groupNameCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Group name (optional)',
                      prefixIcon: Icon(Icons.edit, size: 18)))),
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
                            Stack(children: [
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
                                        child: const Icon(Icons.close,
                                            color: Colors.white, size: 10)),
                                  )),
                            ]),
                            Text(name.split(' ').first,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary)),
                          ]),
                        ))
                    .toList(),
              )),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              autofocus: !widget.isGroup,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: widget.isGroup
                    ? 'Search and add people...'
                    : 'Search by name or email...',
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textMuted, size: 20),
                filled: true,
                fillColor: AppColors.surfaceVar,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )),
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
                        fontWeight: FontWeight.w600)),
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
                                              color: Colors.white, width: 2)))),
                            ]),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.email,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted)),
                                  Row(children: [
                                    Text('${u.role} · ${u.department}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                          color: u.statusColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: Text(
                                        u.status == 'online'
                                            ? 'Online'
                                            : u.status == 'busy'
                                                ? 'Busy'
                                                : u.status == 'away'
                                                    ? 'Away'
                                                    : u.lastSeenText,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: u.statusColor),
                                      ),
                                    ),
                                  ]),
                                ]),
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
                                          color: isSelected
                                              ? themeColor
                                              : Colors.transparent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: isSelected
                                                  ? themeColor
                                                  : AppColors.border,
                                              width: 2)),
                                      child: isSelected
                                          ? const Icon(Icons.check,
                                              color: Colors.white, size: 16)
                                          : null,
                                    ),
                                  )
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
                                              color:
                                                  themeColor.withOpacity(0.3))),
                                      child: Text('Message',
                                          style: TextStyle(
                                              color: themeColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ),
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
            child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : _createGroup,
                  icon: const Icon(Icons.group_add),
                  label: Text(_selectedIds.isEmpty
                      ? 'Select people to create group'
                      : 'Create Group (${_selectedIds.length} people)'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      disabledBackgroundColor: AppColors.border,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
          ),
      ]),
    );
  }
}
