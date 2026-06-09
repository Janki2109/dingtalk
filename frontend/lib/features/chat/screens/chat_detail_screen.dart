import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import '../../../shared/widgets/app_widgets.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatModel chat;
  final String currentUserId;

  const ChatDetailScreen({
    super.key,
    required this.chat,
    required this.currentUserId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  List<MessageModel> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _aiLoading = false;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final msgs = await ApiService.getMessages(widget.chat.id);
      if (!mounted) return;
      // Preserve local AI messages (not saved to DB) across polls
      final localAI = _messages.where((m) => m.senderId == 'ai').toList();
      final merged = [...msgs, ...localAI]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final hadMessages = _messages.length;
      setState(() {
        _messages = merged;
        _loading = false;
      });
      if (merged.length != hadMessages) _scrollToBottom();
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    setState(() => _sending = true);
    try {
      final msg = await ApiService.sendMessage(widget.chat.id, text);
      if (!mounted) return;
      setState(() {
        _messages.add(msg);
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _askAI() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    setState(() => _aiLoading = true);
    _scrollToBottom();
    try {
      final reply = await ApiService.aiChat(widget.currentUserId, text);
      if (!mounted) return;
      final aiMsg = MessageModel(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        chatId: widget.chat.id,
        senderId: 'ai',
        senderName: 'AI Assistant',
        content: reply,
        messageType: 'ai',
        createdAt: DateTime.now(),
      );
      setState(() {
        _aiLoading = false;
        _messages.add(aiMsg);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _aiLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'AI error: ${e.toString().replaceAll("Exception: ", "")}'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  bool _showSenderName(int index) {
    final msg = _messages[index];
    if (msg.senderId == widget.currentUserId) return false;
    return true;
  }

  bool _showAvatar(int index) {
    final msg = _messages[index];
    if (msg.senderId == widget.currentUserId) return false;
    if (index == _messages.length - 1) return true;
    return _messages[index + 1].senderId != msg.senderId;
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          widget.chat.isGroup
              ? const GroupAvatar(size: 38)
              : UserAvatar(name: widget.chat.name, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.chat.isGroup ? 'Group chat' : 'Direct message',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => _loadMessages(),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No messages yet',
                      subtitle: 'Be the first to say hello!',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = _messages[i];
                        final isMe =
                            msg.senderId == widget.currentUserId;
                        return _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          showSenderName: _showSenderName(i),
                          showAvatar: _showAvatar(i),
                          themeColor: themeColor,
                        );
                      },
                    ),
        ),
        _InputBar(
          controller: _textCtrl,
          sending: _sending,
          aiLoading: _aiLoading,
          onSend: _sendMessage,
          onAsk: _askAI,
          themeColor: themeColor,
        ),
      ]),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool showSenderName;
  final bool showAvatar;
  final Color themeColor;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSenderName,
    required this.showAvatar,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    const avatarSize = 30.0;
    const avatarGap = 6.0;
    final isAI = message.senderId == 'ai';

    return Padding(
      padding: EdgeInsets.only(
        bottom: showAvatar ? 8 : 2,
        top: showSenderName ? 6 : 0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Left avatar for incoming messages
          if (!isMe)
            SizedBox(
              width: avatarSize + avatarGap,
              child: showAvatar
                  ? (isAI
                      ? Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Colors.deepPurple.shade400,
                                Colors.indigo.shade400
                              ],
                            ),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 16),
                        )
                      : UserAvatar(
                          name: message.senderName,
                          size: avatarSize,
                          avatarUrl: message.senderAvatarUrl.isNotEmpty
                              ? message.senderAvatarUrl
                              : null,
                        ))
                  : const SizedBox(),
            ),

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender name label
                if (showSenderName)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isAI) ...[
                          Icon(Icons.auto_awesome_rounded,
                              size: 12,
                              color: Colors.deepPurple.shade400),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          message.senderName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isAI
                                ? Colors.deepPurple.shade400
                                : themeColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Message bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 9),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  decoration: BoxDecoration(
                    color: isAI
                        ? Colors.deepPurple.shade50
                        : isMe
                            ? themeColor
                            : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                    border: isAI
                        ? Border.all(
                            color: Colors.deepPurple.shade100, width: 1)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 15,
                          color: isAI
                              ? Colors.deepPurple.shade800
                              : isMe
                                  ? Colors.white
                                  : AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatTime(message.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: isAI
                                  ? Colors.deepPurple.shade300
                                  : isMe
                                      ? Colors.white.withOpacity(0.65)
                                      : AppColors.textMuted,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 13,
                              color: message.isRead
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.55),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right spacer for incoming
          if (!isMe) const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ── Input Bar ─────────────────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool aiLoading;
  final VoidCallback onSend;
  final VoidCallback onAsk;
  final Color themeColor;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.aiLoading,
    required this.onSend,
    required this.onAsk,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final busy = sending || aiLoading;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
              color: Color(0x12000000),
              blurRadius: 8,
              offset: Offset(0, -2)),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Type a message…',
              hintStyle: const TextStyle(
                  color: AppColors.textMuted, fontSize: 15),
              filled: true,
              fillColor: AppColors.surfaceVar,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide:
                    BorderSide(color: themeColor.withOpacity(0.4)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // AI button
        GestureDetector(
          onTap: busy ? null : onAsk,
          child: Tooltip(
            message: 'Ask AI',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade400,
                    Colors.indigo.shade400,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: aiLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Send button
        GestureDetector(
          onTap: busy ? null : onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [themeColor, themeColor.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: themeColor.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
