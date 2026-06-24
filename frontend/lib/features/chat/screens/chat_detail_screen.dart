import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatModel chat;
  final String currentUserId;
  const ChatDetailScreen(
      {super.key, required this.chat, required this.currentUserId});
  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  List<MessageModel> _messages = [];
  List<UserModel> _allUsers = [];
  bool _loading = false;
  bool _sending = false;
  bool _isAI = false;
  bool _showMentions = false;
  String _chatTitle = '';
  List<UserModel> _mentionList = [];
  MessageModel? _replyTo;

  @override
  void initState() {
    super.initState();
    _chatTitle = widget.chat.name;
    _isAI = widget.chat.id == 'ai';
    _load();
    _loadUsers();
    _poll();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    if (cursor <= 0) {
      setState(() => _showMentions = false);
      return;
    }
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    if (atIdx == -1) {
      setState(() => _showMentions = false);
      return;
    }
    final query = before.substring(atIdx + 1).toLowerCase();
    if (query.contains(' ')) {
      setState(() => _showMentions = false);
      return;
    }
    final filtered = _allUsers
        .where((u) =>
            u.name.toLowerCase().contains(query) &&
            u.id != widget.currentUserId)
        .toList();
    setState(() {
      _showMentions = filtered.isNotEmpty;
      _mentionList = filtered;
    });
  }

  void _insertMention(UserModel user) {
    final text = _ctrl.text;
    final cursor = _ctrl.selection.baseOffset;
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    final after = text.substring(cursor);
    final newText = '${text.substring(0, atIdx)}@${user.name} $after';
    _ctrl.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.collapsed(offset: atIdx + user.name.length + 2));
    setState(() {
      _showMentions = false;
      _mentionList = [];
    });
    _focus.requestFocus();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ApiService.getUsers();
      if (mounted) setState(() => _allUsers = users);
    } catch (_) {}
  }

  void _poll() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      if (_sending) return mounted;
      final hasTemp = _messages.any((m) => m.id.startsWith('temp_'));
      if (hasTemp) return mounted;
      try {
        final msgs = await ApiService.getMessages(widget.chat.id);
        if (!mounted) return false;
        if (msgs.length != _messages.length) {
          setState(() => _messages = msgs);
          _scrollBottom();
        }
      } catch (_) {}
      return mounted;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final msgs = await ApiService.getMessages(widget.chat.id);
      if (mounted)
        setState(() {
          _messages = msgs;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _messages = [];
          _loading = false;
        });
    }
    _scrollBottom();
  }

  Future<void> _send(
      {String? text,
      String type = 'text',
      String fileUrl = '',
      String fileName = ''}) async {
    final content = text ?? _ctrl.text.trim();
    if (content.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() {
      _sending = true;
      _replyTo = null;
      _showMentions = false;
    });

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final temp = MessageModel(
        id: tempId,
        chatId: widget.chat.id,
        senderId: widget.currentUserId,
        senderName: 'You',
        content: content,
        messageType: type,
        fileUrl: fileUrl,
        fileName: fileName,
        isRead: false,
        createdAt: DateTime.now());
    setState(() => _messages.add(temp));
    _scrollBottom();

    try {
      if (_isAI) {
        final reply = await ApiService.aiChat(widget.currentUserId, content);
        if (mounted)
          setState(() {
            _messages.removeWhere((m) => m.id == tempId);
            _messages.add(MessageModel(
                id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
                chatId: widget.chat.id,
                senderId: 'ai',
                senderName: 'AI',
                content: reply,
                messageType: 'text',
                isRead: true,
                createdAt: DateTime.now()));
          });
      } else {
        final saved = await ApiService.sendMessage(widget.chat.id, content,
            type: type,
            fileUrl: fileUrl.isNotEmpty ? fileUrl : null,
            fileName: fileName.isNotEmpty ? fileName : null);
        if (mounted)
          setState(() {
            final i = _messages.indexWhere((m) => m.id == tempId);
            if (i != -1) {
              _messages[i] = saved;
            } else {
              _messages.add(saved);
            }
          });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final msgs = await ApiService.getMessages(widget.chat.id);
        if (mounted) setState(() => _messages = msgs);
      } catch (_) {
        if (mounted)
          setState(() => _messages.removeWhere((m) => m.id == tempId));
      }
    }
    if (mounted) setState(() => _sending = false);
    _scrollBottom();
  }

  // ── Delete message ─────────────────────────────────────────────────────────
  void _deleteMessage(MessageModel msg) async {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Delete Message?',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              content: const Text('This message will be deleted for everyone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(
                        () => _messages.removeWhere((m) => m.id == msg.id));
                    try {
                      await ApiService.deleteMessage(widget.chat.id, msg.id);
                    } catch (_) {
                      // Already removed from UI, reload to sync
                      _load();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ));
  }

  Future<void> _sendLocation() async {
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.location_on, color: Color(0xFF22C55E)),
                SizedBox(width: 8),
                Text('Share Location',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))
              ]),
              content: const Text(
                  'Share your current GPS location?\nRecipient can open it in Google Maps.',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white54))),
                ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E))),
              ],
            ));
    if (confirmed != true) return;
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        _snack('Enable location services', Colors.orange);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied', Colors.orange);
        return;
      }
      _snack('Getting location...', const Color(0xFF6C63FF));
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _send(
          text:
              'LOCATION|${pos.latitude.toStringAsFixed(5)}|${pos.longitude.toStringAsFixed(5)}',
          type: 'location');
    } catch (_) {
      _snack('Could not get location', Colors.red);
    }
  }

  Future<void> _pickPhoto() async {
    Navigator.pop(context);
    try {
      final r = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      if (f.bytes == null) return;
      _snack('Uploading photo...', const Color(0xFF6C63FF));
      final result = await ApiService.uploadMedia(f.name, f.bytes!);
      final url = result['url'] as String? ?? '';
      await _send(text: f.name, type: 'image', fileUrl: url, fileName: f.name);
    } catch (e) {
      _snack('Photo upload failed', Colors.red);
    }
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      if (f.bytes == null) return;
      _snack('Uploading file...', const Color(0xFF3B82F6));
      final result = await ApiService.uploadMedia(f.name, f.bytes!);
      final url = result['url'] as String? ?? '';
      await _send(text: f.name, type: 'file', fileUrl: url, fileName: f.name);
    } catch (e) {
      _snack('File upload failed', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _attachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const Text('Share',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _AttBtn(Icons.photo_library_rounded, 'Photo',
                const Color(0xFF6C63FF), _pickPhoto),
            _AttBtn(Icons.attach_file_rounded, 'File', const Color(0xFF3B82F6),
                _pickFile),
            _AttBtn(Icons.my_location_rounded, 'Location',
                const Color(0xFF22C55E), _sendLocation),
          ]),
        ]),
      ),
    );
  }

  void _msgMenu(MessageModel msg) {
    final isOwn = msg.senderId == widget.currentUserId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          _ActBtn(Icons.reply_rounded, 'Reply', const Color(0xFF6C63FF), () {
            Navigator.pop(context);
            setState(() => _replyTo = msg);
          }),
          _ActBtn(Icons.copy_rounded, 'Copy', const Color(0xFF3B82F6), () {
            Navigator.pop(context);
            Clipboard.setData(ClipboardData(text: msg.content));
            _snack('Copied!', const Color(0xFF6C63FF));
          }),
          if (isOwn)
            _ActBtn(
                Icons.delete_rounded, 'Delete Message', const Color(0xFFEF4444),
                () {
              Navigator.pop(context);
              _deleteMessage(msg);
            }),
        ]),
      ),
    );
  }

  void _scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients)
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
      });

  Widget _buildMessageText(String content, bool isMe) {
    if (!content.contains('@'))
      return Text(content,
          style: TextStyle(
              color: isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 15,
              height: 1.4));
    final spans = <TextSpan>[];
    for (final part in content.split(' ')) {
      if (part.startsWith('@')) {
        spans.add(TextSpan(
            text: '$part ',
            style: TextStyle(
                color: isMe ? Colors.yellow.shade200 : const Color(0xFF6C63FF),
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.4)));
      } else {
        spans.add(TextSpan(
            text: '$part ',
            style: TextStyle(
                color: isMe ? Colors.white : AppColors.textPrimary,
                fontSize: 15,
                height: 1.4)));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final isGroup = widget.chat.isGroup;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: Row(children: [
          Stack(children: [
            isGroup
                ? const GroupAvatar(size: 40)
                : _isAI
                    ? const AIAvatar(size: 40)
                    : UserAvatar(name: _chatTitle, size: 40),
            if (!isGroup && !_isAI)
              Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF1A1A2E), width: 2)))),
          ]),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_chatTitle,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                Text(
                    _isAI
                        ? 'AI Assistant'
                        : isGroup
                            ? 'Group chat'
                            : 'Direct message',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.online,
                        fontWeight: FontWeight.w500)),
              ])),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white60),
              onPressed: _load)
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      const Color(0xFF6C63FF).withOpacity(0.1)),
                              child: const Icon(Icons.chat_bubble_outline,
                                  size: 36, color: Color(0xFF6C63FF))),
                          const SizedBox(height: 16),
                          Text('Say hi to $_chatTitle! 👋',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14)),
                        ]))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = _messages[i];
                        final isMe = msg.senderId == widget.currentUserId;
                        final showDate = i == 0 ||
                            !_sameDay(
                                _messages[i - 1].createdAt, msg.createdAt);
                        return Column(children: [
                          if (showDate) _DateBar(msg.createdAt),
                          GestureDetector(
                            onLongPress: () => _msgMenu(msg),
                            child: _Bubble(
                                msg: msg,
                                isMe: isMe,
                                isAI: msg.senderId == 'ai',
                                showName: isGroup,
                                color: themeColor,
                                messageBuilder: _buildMessageText),
                          ),
                        ]);
                      },
                    ),
        ),
        if (_showMentions && _mentionList.isNotEmpty)
          Container(
            color: const Color(0xFF1A1A2E),
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView.builder(
                shrinkWrap: true,
                itemCount: _mentionList.length,
                itemBuilder: (_, i) {
                  final u = _mentionList[i];
                  return ListTile(
                      dense: true,
                      leading:
                          UserAvatar(name: u.name, size: 32, status: u.status),
                      title: Text('@${u.name}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(u.role,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      onTap: () => _insertMention(u));
                }),
          ),
        if (_replyTo != null)
          Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('↩ ${_replyTo!.senderName}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w600)),
                    Text(_replyTo!.content,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
              IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white38, size: 16),
                  onPressed: () => setState(() => _replyTo = null)),
            ]),
          ),
        Container(
          color: const Color(0xFF12122A),
          padding: EdgeInsets.fromLTRB(
              8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
                onPressed: _attachMenu,
                icon: const Icon(Icons.add_circle_outline_rounded,
                    color: Color(0xFF6C63FF), size: 28)),
            Expanded(
                child: Container(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300)),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: 5,
                minLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                    color: Colors.black87, fontSize: 15, height: 1.4),
                cursorColor: const Color(0xFF6C63FF),
                decoration: InputDecoration(
                    hintText: _isAI ? 'Ask AI...' : 'Message...',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade500, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10)),
                onSubmitted: (_) => _send(),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(),
              child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DateBar extends StatelessWidget {
  final DateTime date;
  const _DateBar(this.date);
  String get _label {
    final now = DateTime.now();
    final d = DateTime(date.year, date.month, date.day);
    final t = DateTime(now.year, now.month, now.day);
    if (d == t) return 'Today';
    if (d == t.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Container(height: 1, color: Colors.white10)),
          const SizedBox(width: 8),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF22223A),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(_label,
                  style: const TextStyle(fontSize: 11, color: Colors.white38))),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: Colors.white10)),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe, isAI, showName;
  final Color color;
  final Widget Function(String, bool) messageBuilder;
  const _Bubble(
      {required this.msg,
      required this.isMe,
      required this.isAI,
      required this.showName,
      required this.color,
      required this.messageBuilder});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            bottom: 6, left: isMe ? 50 : 0, right: isMe ? 0 : 50),
        child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                isAI
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            gradient: AppColors.purpleGrad,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 16))
                    : UserAvatar(name: msg.senderName, size: 30),
                const SizedBox(width: 6),
              ],
              Flexible(
                  child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                    if (!isMe && showName)
                      Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(msg.senderName,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color))),
                    _buildContent(context),
                    Padding(
                        padding:
                            const EdgeInsets.only(top: 2, left: 4, right: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_time,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.white38)),
                          if (isMe) ...[
                            const SizedBox(width: 3),
                            Icon(msg.isRead ? Icons.done_all : Icons.done,
                                size: 13,
                                color: msg.isRead
                                    ? const Color(0xFF6C63FF)
                                    : Colors.white38)
                          ],
                        ])),
                  ])),
            ]),
      );

  Widget _buildContent(BuildContext context) {
    if (msg.messageType == 'location') {
      final parts = msg.content.split('|');
      final lat = parts.length > 1 ? parts[1] : '';
      final lng = parts.length > 2 ? parts[2] : '';
      return GestureDetector(
        onTap: () async {
          final url = Uri.parse('https://maps.google.com/?q=$lat,$lng');
          if (await canLaunchUrl(url))
            await launchUrl(url, mode: LaunchMode.externalApplication);
        },
        child: Container(
          width: 220,
          decoration: BoxDecoration(
              color: isMe ? const Color(0xFF5855D6) : const Color(0xFF22223A),
              borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                    height: 110,
                    color: const Color(0xFF1A2744),
                    child: const Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Icon(Icons.location_on,
                              color: Color(0xFFEF4444), size: 36),
                          Text('You are here',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 9)),
                        ])))),
            Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  const Row(children: [
                    Icon(Icons.location_on, color: Color(0xFF22C55E), size: 14),
                    SizedBox(width: 4),
                    Text('My Location',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700))
                  ]),
                  const SizedBox(height: 2),
                  Text('$lat, $lng',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 9)),
                  const SizedBox(height: 8),
                  Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.open_in_new,
                                color: Color(0xFF22C55E), size: 12),
                            SizedBox(width: 4),
                            Text('Open Google Maps',
                                style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600))
                          ])),
                ])),
          ]),
        ),
      );
    }

    if (msg.messageType == 'image' && msg.fileUrl.isNotEmpty) {
      final imageUrl = msg.fileUrl.startsWith('http')
          ? msg.fileUrl
          : '${AppConstants.serverUrl}${msg.fileUrl}';
      return GestureDetector(
        onTap: () async {
          final url = Uri.parse(imageUrl);
          if (await canLaunchUrl(url))
            await launchUrl(url, mode: LaunchMode.externalApplication);
        },
        child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    width: 200,
                    height: 200,
                    color: const Color(0xFF22223A),
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF6C63FF), strokeWidth: 2))),
                errorWidget: (_, __, ___) => _fileCard(
                    msg.fileName.isNotEmpty ? msg.fileName : msg.content, '',
                    isImage: true))),
      );
    }

    if (msg.messageType == 'file' || msg.messageType == 'image') {
      String name = msg.fileName.isNotEmpty ? msg.fileName : msg.content;
      return GestureDetector(
        onTap: msg.fileUrl.isNotEmpty
            ? () async {
                final fileUrl = msg.fileUrl.startsWith('http')
                    ? msg.fileUrl
                    : '${AppConstants.serverUrl}${msg.fileUrl}';
                final url = Uri.parse(fileUrl);
                if (await canLaunchUrl(url))
                  await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            : null,
        child: _fileCard(name, '', isImage: msg.messageType == 'image'),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        color: isMe ? null : const Color(0xFF22223A),
        borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 16)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)
        ],
      ),
      child: messageBuilder(msg.content, isMe),
    );
  }

  String get _time {
    final h = msg.createdAt.hour % 12 == 0 ? 12 : msg.createdAt.hour % 12;
    final m = msg.createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m ${msg.createdAt.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _fileCard(String name, String size, {bool isImage = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            gradient: isMe
                ? const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])
                : null,
            color: isMe ? null : const Color(0xFF22223A),
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15)),
              child: Icon(isImage ? Icons.image : Icons.attach_file,
                  color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 130,
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            const Text('Tap to open',
                style: TextStyle(color: Colors.white60, fontSize: 10)),
          ]),
        ]),
      );
}

class _AttBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttBtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.4))),
            child: Icon(icon, color: color, size: 26)),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]));
}

class _ActBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActBtn(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withOpacity(0.15)),
            child: Icon(icon, color: color, size: 20)),
        title: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
}
