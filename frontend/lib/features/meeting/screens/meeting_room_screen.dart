import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';
import '../../../data/services/meeting_webrtc_service.dart';

class MeetingRoomScreen extends StatefulWidget {
  final String meetingId;
  final String meetingCode;
  final String inviteLink;
  final bool isHost;
  final String meetingTitle;
  final String userName;

  const MeetingRoomScreen({
    super.key,
    this.meetingId = '',
    this.meetingCode = '',
    this.inviteLink = '',
    this.isHost = false,
    this.meetingTitle = 'Meeting',
    this.userName = 'Guest',
  });

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  late final MeetingWebRTCService _svc;
  bool _initialized = false;

  // UI state
  bool _showChat = false;
  bool _showParticipants = false;
  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _svc = MeetingWebRTCService();
    _svc.addListener(_onServiceUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (_initialized || !mounted) return;
    _initialized = true;

    final auth = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey) ?? '';

    if (!mounted) return;
    await _svc.connect(
      roomCode: widget.meetingCode,
      meetingId: widget.meetingId,
      userId: auth.user?.id ?? '',
      userName: auth.user?.name ?? widget.userName,
      token: token,
      isHost: widget.isHost,
    );

    // Callbacks for navigation
    _svc.onMeetingEnded = _onEnded;
    _svc.onRemoved = _onRemoved;
    _svc.onRejected = _onRejected;
    _svc.onAdmitted = () => setState(() {});
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onEnded() {
    if (!mounted) return;
    _showBanner('Meeting ended', AppColors.textSecondary);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onRemoved() {
    if (!mounted) return;
    _showBanner('You were removed from the meeting', AppColors.busy);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onRejected() {
    if (!mounted) return;
    _showBanner('Your request to join was declined', AppColors.away);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _showBanner(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceUpdate);
    _svc.dispose();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  // ── Leave / End ────────────────────────────────────────────────────────────

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Meeting?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(widget.isHost
            ? 'End the meeting for all participants?'
            : 'Are you sure you want to leave?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          if (widget.isHost)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _svc.endMeeting();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
              child: const Text('End for All'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: widget.isHost ? AppColors.away : AppColors.busy),
            child: Text(widget.isHost ? 'Just Leave' : 'Leave'),
          ),
        ],
      ),
    );
  }

  // ── Waiting room screen ────────────────────────────────────────────────────

  Widget _buildWaiting() {
    final themeColor = context.watch<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(color: themeColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.hourglass_empty_rounded, color: themeColor, size: 50),
          ),
          const SizedBox(height: 28),
          Text(widget.meetingTitle,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Waiting for host to admit you…',
              style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 40),
          const SizedBox(
              width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white)),
          const SizedBox(height: 40),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
            label: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ]),
      ),
    );
  }

  Widget _buildRejected() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(color: AppColors.busy.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.cancel_rounded, color: AppColors.busy, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Request Declined',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('The host did not admit you to this meeting.',
              style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
            child: const Text('Go Back'),
          ),
        ]),
      ),
    );
  }

  // ── Video grid ─────────────────────────────────────────────────────────────

  Widget _buildVideoGrid() {
    final entries = _svc.remoteRenderers.entries.toList();
    final totalCount = entries.length + 1; // +1 for local

    // Grid configuration
    int crossCount;
    if (totalCount <= 1) {
      crossCount = 1;
    } else if (totalCount <= 4) {
      crossCount = 2;
    } else {
      crossCount = 3;
    }

    final allTiles = <Widget>[
      // Local tile
      _buildVideoTile(
        renderer: _svc.localRenderer,
        label: 'You',
        isLocal: true,
        isHost: widget.isHost,
        audioEnabled: _svc.micEnabled,
        videoEnabled: _svc.cameraEnabled,
        handRaised: _svc.handRaised,
      ),
      // Remote tiles
      for (final e in entries)
        _buildVideoTile(
          renderer: e.value,
          label: _svc.participants[e.key]?.userName ?? 'Participant',
          isLocal: false,
          isHost: _svc.participants[e.key]?.isHost ?? false,
          audioEnabled: _svc.participants[e.key]?.audioEnabled ?? true,
          videoEnabled: _svc.participants[e.key]?.videoEnabled ?? true,
          handRaised: _svc.participants[e.key]?.handRaised ?? false,
          userId: e.key,
        ),
    ];

    if (totalCount == 1) {
      return allTiles.first;
    }

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossCount,
      crossAxisSpacing: 2,
      mainAxisSpacing: 2,
      children: allTiles,
    );
  }

  Widget _buildVideoTile({
    required RTCVideoRenderer renderer,
    required String label,
    required bool isLocal,
    required bool isHost,
    required bool audioEnabled,
    required bool videoEnabled,
    required bool handRaised,
    String? userId,
  }) {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(children: [
        // Video
        Positioned.fill(
          child: videoEnabled
              ? RTCVideoView(renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: isLocal)
              : Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.2), shape: BoxShape.circle),
                    child: Icon(Icons.person_rounded, color: themeColor, size: 34),
                  ),
                ),
        ),

        // Gradient overlay bottom
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.7), Colors.transparent],
              ),
            ),
          ),
        ),

        // Name + icons
        Positioned(
          bottom: 6, left: 8, right: 8,
          child: Row(children: [
            Expanded(
              child: Text(
                isHost ? '$label (Host)' : label,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!audioEnabled)
              const Icon(Icons.mic_off_rounded, color: AppColors.busy, size: 14),
            if (!videoEnabled)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.videocam_off_rounded, color: AppColors.away, size: 14),
              ),
            if (handRaised)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('✋', style: TextStyle(fontSize: 14)),
              ),
          ]),
        ),

        // Admin context menu (host only, on remote tiles)
        if (widget.isHost && !isLocal && userId != null)
          Positioned(
            top: 4, right: 4,
            child: PopupMenuButton<String>(
              iconColor: Colors.white70,
              iconSize: 18,
              color: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (action) {
                switch (action) {
                  case 'mute':
                    _svc.muteUser(userId);
                  case 'video':
                    _svc.disableUserVideo(userId);
                  case 'remove':
                    _confirmRemove(userId, label);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'mute',
                    child: Row(children: [Icon(Icons.mic_off_rounded, size: 16), SizedBox(width: 8), Text('Mute')])),
                const PopupMenuItem(value: 'video',
                    child: Row(children: [Icon(Icons.videocam_off_rounded, size: 16), SizedBox(width: 8), Text('Disable Camera')])),
                const PopupMenuItem(value: 'remove',
                    child: Row(children: [Icon(Icons.person_remove_rounded, size: 16, color: AppColors.busy), SizedBox(width: 8), Text('Remove', style: TextStyle(color: AppColors.busy))])),
              ],
            ),
          ),
      ]),
    );
  }

  void _confirmRemove(String userId, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Remove $name?', style: const TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('They will be disconnected from the meeting.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _svc.removeParticipant(userId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ── Controls bar ───────────────────────────────────────────────────────────

  Widget _buildControls() {
    final themeColor = context.read<AuthProvider>().themeColor;
    final waitingCount = _svc.waitingRoom.length;

    return Container(
      color: const Color(0xFF111122),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ctrlBtn(
          icon: _svc.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: _svc.micEnabled ? 'Mute' : 'Unmute',
          active: !_svc.micEnabled,
          activeColor: AppColors.busy,
          onTap: _svc.toggleMic,
        ),
        _ctrlBtn(
          icon: _svc.cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          label: _svc.cameraEnabled ? 'Stop Video' : 'Start Video',
          active: !_svc.cameraEnabled,
          activeColor: AppColors.busy,
          onTap: _svc.toggleCamera,
        ),
        _ctrlBtn(
          icon: Icons.screen_share_rounded,
          label: _svc.screenSharing ? 'Stop Share' : 'Share',
          active: _svc.screenSharing,
          activeColor: themeColor,
          onTap: _svc.toggleScreenShare,
        ),
        _ctrlBtn(
          icon: _svc.handRaised ? Icons.back_hand_rounded : Icons.back_hand_outlined,
          label: _svc.handRaised ? 'Lower Hand' : 'Raise Hand',
          active: _svc.handRaised,
          activeColor: AppColors.away,
          onTap: _svc.toggleHandRaise,
        ),
        _ctrlBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chat',
          active: _showChat,
          activeColor: themeColor,
          badge: _showChat ? 0 : _svc.chatMessages.length,
          onTap: () => setState(() {
            _showChat = !_showChat;
            if (_showChat) _showParticipants = false;
                      }),
        ),
        _ctrlBtn(
          icon: Icons.people_outline_rounded,
          label: 'People',
          active: _showParticipants,
          activeColor: themeColor,
          badge: widget.isHost ? waitingCount : 0,
          onTap: () => setState(() {
            _showParticipants = !_showParticipants;
            if (_showParticipants) _showChat = false;
                      }),
        ),
        _ctrlBtn(
          icon: Icons.call_end_rounded,
          label: widget.isHost ? 'End' : 'Leave',
          active: true,
          activeColor: AppColors.busy,
          onTap: _confirmLeave,
        ),
      ]),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (badge > 0)
            Positioned(
              right: 0, top: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(color: AppColors.busy, shape: BoxShape.circle),
                child: Center(
                  child: Text('$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    );
  }

  // ── Chat panel ─────────────────────────────────────────────────────────────

  Widget _buildChatPanel() {
    return Container(
      width: 300,
      color: AppColors.surface,
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            const Expanded(
                child: Text('Meeting Chat',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _showChat = false)),
          ]),
        ),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _chatScroll,
            padding: const EdgeInsets.all(12),
            itemCount: _svc.chatMessages.length,
            itemBuilder: (_, i) {
              final m = _svc.chatMessages[i];
              return _buildChatBubble(m);
            },
          ),
        ),
        // Input
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                  filled: true,
                  fillColor: AppColors.bg,
                ),
                onSubmitted: (v) {
                  _svc.sendChat(v);
                  _chatCtrl.clear();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_chatScroll.hasClients) {
                      _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (_chatCtrl.text.trim().isNotEmpty) {
                  _svc.sendChat(_chatCtrl.text);
                  _chatCtrl.clear();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_chatScroll.hasClients) {
                      _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                    }
                  });
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: context.read<AuthProvider>().themeColor, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildChatBubble(MeetingChatMsg m) {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment:
          m.isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        Text(m.userName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: m.isOwn ? themeColor : AppColors.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(m.content,
              style: TextStyle(
                  fontSize: 13,
                  color: m.isOwn ? Colors.white : AppColors.textPrimary)),
        ),
      ]),
    );
  }

  // ── Participants panel ─────────────────────────────────────────────────────

  Widget _buildParticipantsPanel() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Container(
      width: 280,
      color: AppColors.surface,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            const Expanded(
                child: Text('Participants',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _showParticipants = false)),
          ]),
        ),

        // Waiting room (admin only)
        if (widget.isHost && _svc.waitingRoom.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.away.withOpacity(0.08),
            child: Row(children: [
              const Icon(Icons.hourglass_empty_rounded, size: 14, color: AppColors.away),
              const SizedBox(width: 6),
              Text('Waiting (${_svc.waitingRoom.length})',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.away)),
            ]),
          ),
          ..._svc.waitingRoom.map((w) => ListTile(
                dense: true,
                leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: themeColor.withOpacity(0.15),
                    child: Text(w.userName.isNotEmpty ? w.userName[0].toUpperCase() : '?',
                        style: TextStyle(color: themeColor, fontWeight: FontWeight.w700))),
                title: Text(w.userName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text('Waiting to join', style: TextStyle(fontSize: 11)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () => _svc.admitUser(w.userId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.online, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Admit',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _svc.rejectUser(w.userId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.busy, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Deny',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              )),
          const Divider(height: 1),
        ],

        // Admitted participants
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.people_rounded, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('In Meeting (${_svc.participants.length + 1})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.textMuted)),
          ]),
        ),

        // Myself
        _buildParticipantTile(
          name: 'You',
          isHost: widget.isHost,
          audioEnabled: _svc.micEnabled,
          videoEnabled: _svc.cameraEnabled,
          handRaised: _svc.handRaised,
          isMe: true,
        ),

        // Others
        Expanded(
          child: ListView(
            children: _svc.participants.values.map((p) => _buildParticipantTile(
              name: p.userName,
              isHost: p.isHost,
              audioEnabled: p.audioEnabled,
              videoEnabled: p.videoEnabled,
              handRaised: p.handRaised,
              isMe: false,
              userId: p.userId,
            )).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildParticipantTile({
    required String name,
    required bool isHost,
    required bool audioEnabled,
    required bool videoEnabled,
    required bool handRaised,
    required bool isMe,
    String? userId,
  }) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
          radius: 16,
          backgroundColor: isHost
              ? AppColors.away.withOpacity(0.2)
              : AppColors.primary.withOpacity(0.1),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: isHost ? AppColors.away : AppColors.primary))),
      title: Text(isHost ? '$name (Host)' : name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (handRaised) const Text('✋', style: TextStyle(fontSize: 14)),
        if (!audioEnabled)
          const Icon(Icons.mic_off_rounded, color: AppColors.busy, size: 16),
        if (!videoEnabled)
          const Icon(Icons.videocam_off_rounded, color: AppColors.away, size: 16),
        if (widget.isHost && !isMe && userId != null)
          PopupMenuButton<String>(
            iconSize: 16,
            padding: EdgeInsets.zero,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (action) {
              if (action == 'mute') _svc.muteUser(userId);
              if (action == 'video') _svc.disableUserVideo(userId);
              if (action == 'remove') _confirmRemove(userId, name);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'mute',
                  child: Text('Mute', style: TextStyle(fontSize: 13))),
              const PopupMenuItem(value: 'video',
                  child: Text('Disable Camera', style: TextStyle(fontSize: 13))),
              const PopupMenuItem(value: 'remove',
                  child: Text('Remove', style: TextStyle(fontSize: 13, color: AppColors.busy))),
            ],
          ),
      ]),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final themeColor = context.read<AuthProvider>().themeColor;
    final admitted = _svc.participants.length + 1;
    final waiting = _svc.waitingRoom.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(children: [
        // Meeting info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.circle, color: AppColors.online, size: 8),
            const SizedBox(width: 6),
            Text(widget.meetingTitle,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            if (widget.isHost) ...[
              const SizedBox(width: 6),
              const Text('· Host',
                  style: TextStyle(color: AppColors.away, fontSize: 11)),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white12, borderRadius: BorderRadius.circular(10)),
              child: Text('$admitted', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ]),
        ),
        const Spacer(),

        // Waiting badge (admin)
        if (widget.isHost && waiting > 0)
          GestureDetector(
            onTap: () => setState(() {
              _showParticipants = true;
              _showChat = false;
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.away,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 13),
                const SizedBox(width: 4),
                Text('$waiting waiting',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

        // Code chip
        if (widget.meetingCode.isNotEmpty)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.meetingCode));
              _showBanner('Code ${widget.meetingCode} copied', themeColor);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.tag_rounded, color: Colors.white70, size: 12),
                const SizedBox(width: 4),
                Text(widget.meetingCode,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w800, letterSpacing: 2)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Route based on status
    switch (_svc.status) {
      case MeetingStatus.connecting:
        return _buildConnecting();
      case MeetingStatus.waiting:
        return _buildWaiting();
      case MeetingStatus.rejected:
        return _buildRejected();
      case MeetingStatus.removed:
      case MeetingStatus.ended:
        return _buildEnded();
      case MeetingStatus.inMeeting:
        return _buildMeetingRoom();
    }
  }

  Widget _buildConnecting() {
    final themeColor = context.read<AuthProvider>().themeColor;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle),
              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 40)),
          const SizedBox(height: 24),
          Text(widget.meetingTitle,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Connecting…',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 32),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildEnded() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.call_end_rounded, color: AppColors.busy, size: 64),
          const SizedBox(height: 20),
          Text(
            _svc.status == MeetingStatus.removed
                ? 'You were removed from the meeting'
                : 'Meeting ended',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Go Back'),
          ),
        ]),
      ),
    );
  }

  Widget _buildMeetingRoom() {
    final sideVisible = _showChat || _showParticipants;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          // Video area + side panel
          Expanded(
            child: Row(children: [
              // Main video grid
              Expanded(
                child: Stack(children: [
                  // Video grid
                  Positioned.fill(child: _buildVideoGrid()),
                  // Top bar overlay
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                ]),
              ),
              // Side panel
              if (sideVisible)
                _showChat
                    ? _buildChatPanel()
                    : _buildParticipantsPanel(),
            ]),
          ),
          // Controls
          _buildControls(),
        ]),
      ),
    );
  }
}
