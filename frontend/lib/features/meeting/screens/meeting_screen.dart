import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';
import 'meeting_service.dart';

class WebRTCMeetingScreen extends StatefulWidget {
  final String meetingCode;
  final String meetingTitle;
  final String meetingId;
  final bool isHost;

  const WebRTCMeetingScreen({
    super.key,
    required this.meetingCode,
    required this.meetingTitle,
    required this.meetingId,
    required this.isHost,
  });

  @override
  State<WebRTCMeetingScreen> createState() => _WebRTCMeetingScreenState();
}

class _WebRTCMeetingScreenState extends State<WebRTCMeetingScreen> {
  late MeetingService _service;
  bool _chatOpen = false;
  bool _participantsOpen = false;
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _service = MeetingService();
    _service.onAdmitted = () {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ You have been admitted!'),
              backgroundColor: Colors.green),
        );
    };
    _service.onRejected = () {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Request rejected'), backgroundColor: Colors.red));
      }
    };
    _service.onRemoved = () {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You were removed'), backgroundColor: Colors.red));
      }
    };
    _service.onMeetingEnded = () {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Meeting ended'), backgroundColor: Colors.orange));
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final auth = context.read<AuthProvider>();
    await _service.connect(
      roomCode: widget.meetingCode,
      meetingId: widget.meetingId,
      userId: auth.user?.id ?? '',
      userName: auth.user?.name ?? 'Guest',
      token: auth.token ?? '',
      isHost: widget.isHost,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _service.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _service,
      child: Consumer<MeetingService>(builder: (ctx, svc, _) {
        if (svc.status == MeetingStatus.connecting) return _buildConnecting();
        if (svc.status == MeetingStatus.waiting) return _buildWaiting(svc);
        if (svc.status == MeetingStatus.inMeeting)
          return _buildMeeting(ctx, svc);
        return _buildConnecting();
      }),
    );
  }

  Widget _buildConnecting() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(widget.meetingTitle,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Setting up camera & mic...',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 40),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
        ])),
      );

  Widget _buildWaiting(MeetingService svc) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 120,
              height: 90,
              decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(svc.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
            ),
            const SizedBox(height: 24),
            Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2)),
                child: const Icon(Icons.hourglass_empty_rounded,
                    color: Colors.blue, size: 40)),
            const SizedBox(height: 20),
            Text(widget.meetingTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('Waiting for the host to admit you',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 40),
            if (svc.isHost && svc.waitingRoom.isNotEmpty)
              _buildWaitingRoomPanel(svc),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              GestureDetector(
                  onTap: () => svc.toggleMic(),
                  child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color: svc.micEnabled ? Colors.white12 : Colors.red,
                          shape: BoxShape.circle),
                      child: Icon(
                          svc.micEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          color: Colors.white,
                          size: 24))),
              const SizedBox(width: 16),
              GestureDetector(
                  onTap: () => svc.toggleCamera(),
                  child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                          color:
                              svc.cameraEnabled ? Colors.white12 : Colors.red,
                          shape: BoxShape.circle),
                      child: Icon(
                          svc.cameraEnabled
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          color: Colors.white,
                          size: 24))),
            ]),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.exit_to_app, color: Colors.red),
              label: const Text('Leave', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red)),
            ),
          ]),
        )),
      );

  Widget _buildWaitingRoomPanel(MeetingService svc) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white10, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Waiting (${svc.waitingRoom.length})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...svc.waitingRoom.map((u) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  CircleAvatar(
                      backgroundColor: Colors.blue,
                      radius: 18,
                      child: Text(
                          u.userName.isNotEmpty
                              ? u.userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(u.userName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600))),
                  TextButton(
                      onPressed: () => svc.rejectUser(u.userId),
                      child: const Text('Deny',
                          style: TextStyle(color: Colors.red))),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: () => svc.admitUser(u.userId),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8)),
                      child: const Text('Admit')),
                ]),
              )),
        ]),
      );

  Widget _buildMeeting(BuildContext ctx, MeetingService svc) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
          child: Column(children: [
        _buildTopBar(svc),
        Expanded(
            child: Row(children: [
          Expanded(child: _buildVideoGrid(svc)),
          if (_chatOpen) _buildChatPanel(svc),
          if (_participantsOpen) _buildParticipantsPanel(svc),
        ])),
        _buildControls(svc),
      ])),
    );
  }

  Widget _buildTopBar(MeetingService svc) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFF1A1A1A),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.meetingTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text('${svc.participants.length + 1} in call',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
          if (svc.isHost && svc.waitingRoom.isNotEmpty)
            GestureDetector(
                onTap: () => setState(() {
                      _participantsOpen = true;
                      _chatOpen = false;
                    }),
                child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${svc.waitingRoom.length} waiting',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)))),
          GestureDetector(
              onTap: () => setState(() {
                    _participantsOpen = !_participantsOpen;
                    _chatOpen = false;
                  }),
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _participantsOpen ? Colors.blue : Colors.white12,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.people_rounded,
                      color: Colors.white, size: 20))),
          const SizedBox(width: 8),
          GestureDetector(
              onTap: () => setState(() {
                    _chatOpen = !_chatOpen;
                    _participantsOpen = false;
                  }),
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _chatOpen ? Colors.blue : Colors.white12,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.chat_rounded,
                      color: Colors.white, size: 20))),
        ]),
      );

  Widget _buildVideoGrid(MeetingService svc) {
    final myName = context.read<AuthProvider>().user?.name ?? 'You';
    if (svc.participants.isEmpty) {
      return Container(
          color: const Color(0xFF0F0F0F),
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                SizedBox(
                    width: 280,
                    height: 200,
                    child: _buildLocalTile(svc, myName)),
                const SizedBox(height: 16),
                const Text('Waiting for others to join...',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ])));
    }
    final total = svc.participants.length + 1;
    final crossCount = total <= 2 ? 1 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          childAspectRatio: 4 / 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6),
      itemCount: total,
      itemBuilder: (ctx, i) {
        if (i == 0) return _buildLocalTile(svc, myName);
        return _buildRemoteTile(svc.participants[i - 1]);
      },
    );
  }

  Widget _buildLocalTile(MeetingService svc, String name) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              svc.cameraEnabled
                  ? RTCVideoView(svc.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.blue.withOpacity(0.3),
                              child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'Y',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(height: 8),
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ])),
              Positioned(
                  bottom: 8,
                  left: 8,
                  child: _nameTag(
                      'You${svc.isHost ? ' (Host)' : ''}', svc.micEnabled)),
              if (svc.handRaised)
                Positioned(top: 8, right: 8, child: _handBadge()),
            ])),
      );

  Widget _buildRemoteTile(MeetingParticipant p) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              p.videoEnabled && p.renderer != null
                  ? RTCVideoView(p.renderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.purple.withOpacity(0.3),
                              child: Text(
                                  p.userName.isNotEmpty
                                      ? p.userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(height: 8),
                          Text(p.userName,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ])),
              Positioned(
                  bottom: 8,
                  left: 8,
                  child: _nameTag(p.userName, p.audioEnabled)),
              if (p.isHost)
                Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('Host',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    )),
              if (p.handRaised)
                Positioned(top: 8, right: 8, child: _handBadge()),
            ])),
      );

  Widget _nameTag(String name, bool audioOn) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!audioOn) ...[
            const Icon(Icons.mic_off, color: Colors.red, size: 11),
            const SizedBox(width: 4)
          ],
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _handBadge() => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: Colors.orange, borderRadius: BorderRadius.circular(20)),
        child: const Text('✋', style: TextStyle(fontSize: 14)),
      );

  Widget _buildControls(MeetingService svc) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: const Color(0xFF1A1A1A),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrl(
              svc.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
              svc.micEnabled ? Colors.white : Colors.red,
              svc.micEnabled ? 'Mute' : 'Unmute',
              () => svc.toggleMic()),
          _ctrl(
              svc.cameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              svc.cameraEnabled ? Colors.white : Colors.red,
              svc.cameraEnabled ? 'Camera' : 'No Cam',
              () => svc.toggleCamera()),
          _ctrl(
              svc.screenSharing
                  ? Icons.stop_screen_share_rounded
                  : Icons.screen_share_rounded,
              svc.screenSharing ? Colors.blue : Colors.white,
              'Share\nScreen',
              () => svc.toggleScreenShare()),
          _ctrl(
              svc.handRaised
                  ? Icons.back_hand_rounded
                  : Icons.back_hand_outlined,
              svc.handRaised ? Colors.orange : Colors.white,
              'Raise\nHand',
              () => svc.toggleHand()),
          _ctrl(
              Icons.chat_rounded,
              _chatOpen ? Colors.blue : Colors.white,
              'Chat',
              () => setState(() {
                    _chatOpen = !_chatOpen;
                    _participantsOpen = false;
                  })),
          _ctrl(
              Icons.people_rounded,
              _participantsOpen ? Colors.blue : Colors.white,
              'People',
              () => setState(() {
                    _participantsOpen = !_participantsOpen;
                    _chatOpen = false;
                  })),
          GestureDetector(
              onTap: () => _showEndDialog(svc),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.call_end_rounded,
                        color: Colors.white, size: 22)),
                const SizedBox(height: 3),
                const Text('End',
                    style: TextStyle(color: Colors.white60, fontSize: 9)),
              ])),
        ]),
      );

  Widget _ctrl(IconData icon, Color color, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 9),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _buildChatPanel(MeetingService svc) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients)
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
    return Container(
      width: 260,
      decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(left: BorderSide(color: Colors.white12))),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Expanded(
                  child: Text('Chat',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700))),
              GestureDetector(
                  onTap: () => setState(() => _chatOpen = false),
                  child:
                      const Icon(Icons.close, color: Colors.white54, size: 18)),
            ])),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
            child: svc.chatMessages.isEmpty
                ? const Center(
                    child: Text('No messages yet',
                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(10),
                    itemCount: svc.chatMessages.length,
                    itemBuilder: (ctx, i) {
                      final msg = svc.chatMessages[i];
                      return Align(
                        alignment: msg.isOwn
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 200),
                          decoration: BoxDecoration(
                              color: msg.isOwn ? Colors.blue : Colors.white12,
                              borderRadius: BorderRadius.circular(12)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!msg.isOwn)
                                  Text(msg.userName,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                Text(msg.content,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13)),
                              ]),
                        ),
                      );
                    })),
        const Divider(color: Colors.white12, height: 1),
        Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                controller: _chatCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                    hintText: 'Message...',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none)),
                onSubmitted: (v) {
                  svc.sendChat(v);
                  _chatCtrl.clear();
                },
              )),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: () {
                    svc.sendChat(_chatCtrl.text);
                    _chatCtrl.clear();
                  },
                  child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(17)),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 16))),
            ])),
      ]),
    );
  }

  Widget _buildParticipantsPanel(MeetingService svc) {
    final myName = context.read<AuthProvider>().user?.name ?? 'You';
    return Container(
      width: 260,
      decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(left: BorderSide(color: Colors.white12))),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: Text('People (${svc.participants.length + 1})',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700))),
              GestureDetector(
                  onTap: () => setState(() => _participantsOpen = false),
                  child:
                      const Icon(Icons.close, color: Colors.white54, size: 18)),
            ])),
        const Divider(color: Colors.white12, height: 1),
        if (svc.isHost && svc.waitingRoom.isNotEmpty) ...[
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Waiting (${svc.waitingRoom.length})',
                  style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 13))),
          ...svc.waitingRoom.map((u) => ListTile(
                dense: true,
                leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.orange.withOpacity(0.2),
                    child: Text(
                        u.userName.isNotEmpty
                            ? u.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 11))),
                title: Text(u.userName,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                      onTap: () => svc.rejectUser(u.userId),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5)),
                          child: const Text('Deny',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 10)))),
                  const SizedBox(width: 5),
                  GestureDetector(
                      onTap: () => svc.admitUser(u.userId),
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5)),
                          child: const Text('Admit',
                              style: TextStyle(
                                  color: Colors.green, fontSize: 10)))),
                ]),
              )),
          const Divider(color: Colors.white12),
        ],
        Expanded(
            child: ListView(padding: const EdgeInsets.all(8), children: [
          _pTile(myName, svc.micEnabled, svc.cameraEnabled,
              isMe: true,
              isHost: svc.isHost,
              handRaised: svc.handRaised,
              svc: svc),
          ...svc.participants.map((p) => _pTile(
              p.userName, p.audioEnabled, p.videoEnabled,
              isMe: false,
              isHost: p.isHost,
              handRaised: p.handRaised,
              svc: svc,
              userId: p.userId)),
        ])),
      ]),
    );
  }

  Widget _pTile(String name, bool audio, bool video,
      {required bool isMe,
      required bool isHost,
      bool handRaised = false,
      required MeetingService svc,
      String? userId}) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
          radius: 14,
          backgroundColor: Colors.blue.withOpacity(0.2),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.blue, fontSize: 11))),
      title: Row(children: [
        Flexible(
            child: Text(isMe ? 'You' : name,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis)),
        if (isHost) ...[
          const SizedBox(width: 4),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.blue, borderRadius: BorderRadius.circular(3)),
              child: const Text('Host',
                  style: TextStyle(color: Colors.white, fontSize: 8)))
        ],
        if (handRaised) const Text(' ✋', style: TextStyle(fontSize: 11)),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(audio ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: audio ? Colors.white54 : Colors.red, size: 14),
        const SizedBox(width: 4),
        Icon(video ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            color: video ? Colors.white54 : Colors.red, size: 14),
        if (svc.isHost && !isMe && userId != null) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white54, size: 14),
            color: const Color(0xFF2A2A2A),
            onSelected: (v) {
              if (v == 'mute') svc.muteUser(userId);
              if (v == 'remove') svc.removeParticipant(userId);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'mute',
                  child: Text('Mute',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
              const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove',
                      style: TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ),
        ],
      ]),
    );
  }

  void _showEndDialog(MeetingService svc) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: Text(svc.isHost ? 'End Meeting?' : 'Leave Meeting?',
                  style: const TextStyle(color: Colors.white)),
              content: Text(
                  svc.isHost
                      ? 'This ends the meeting for everyone.'
                      : 'Are you sure?',
                  style: const TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (svc.isHost) svc.endMeeting();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(svc.isHost ? 'End for All' : 'Leave'),
                ),
              ],
            ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// USER MEETING LIST SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});
  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  List<MeetingModel> _meetings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await ApiService.getMeetings();
      if (mounted)
        setState(() {
          _meetings = m;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _meetings = [];
          _loading = false;
        });
    }
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

  void _openRoom(MeetingModel m, UserModel? user, {required bool isHost}) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WebRTCMeetingScreen(
                  meetingCode: m.code,
                  meetingTitle: m.title,
                  meetingId: m.id,
                  isHost: isHost,
                )));
  }

  Future<void> _deleteMeeting(MeetingModel m) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Delete Meeting?'),
              content: Text('Permanently delete "${m.title}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Delete')),
              ],
            ));
    if (confirm != true) return;
    try {
      await ApiService.deleteMeeting(m.id);
      _snack('Deleted', Colors.red);
      _load();
    } catch (e) {
      _snack('Failed: $e', AppColors.busy);
    }
  }

  void _showJoinWithCode(UserModel? user) {
    final codeCtrl = TextEditingController();
    String error = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  const Row(children: [
                    Icon(Icons.login_rounded,
                        size: 28, color: AppColors.accent),
                    SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Join with Code',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('Enter the code from the host',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8),
                    decoration: InputDecoration(
                        hintText: 'ABC123',
                        errorText: error.isNotEmpty ? error : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final code = codeCtrl.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            setS(() => error = 'Enter the code');
                            return;
                          }
                          try {
                            final meeting =
                                await ApiService.getMeetingByCode(code);
                            if (context.mounted) Navigator.pop(context);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => WebRTCMeetingScreen(
                                          meetingCode: meeting.code,
                                          meetingTitle: meeting.title,
                                          meetingId: meeting.id,
                                          isHost:
                                              meeting.organizerId == user?.id,
                                        )));
                          } catch (e) {
                            setS(() => error = e.toString().contains('404')
                                ? 'Meeting not found'
                                : e.toString());
                          }
                        },
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Join Meeting'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      )),
                ]),
              )),
    );
  }

  void _showCreateMeeting(UserModel? user) {
    final titleCtrl = TextEditingController(text: 'Team Meeting');
    bool loading = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Container(
                decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  Row(children: [
                    Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: context.read<AuthProvider>().themeColor,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.videocam_rounded,
                            color: Colors.white, size: 26)),
                    const SizedBox(width: 14),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Create Meeting',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          Text('Code generated automatically',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Meeting Title',
                          prefixIcon: Icon(Icons.title_rounded))),
                  const SizedBox(height: 20),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                if (titleCtrl.text.trim().isEmpty) return;
                                setS(() => loading = true);
                                try {
                                  final meeting =
                                      await ApiService.createMeeting({
                                    'title': titleCtrl.text.trim(),
                                    'description': '',
                                    'start_time': DateTime.now()
                                        .toUtc()
                                        .toIso8601String(),
                                    'end_time': DateTime.now()
                                        .add(const Duration(hours: 1))
                                        .toUtc()
                                        .toIso8601String(),
                                    'participant_ids': <String>[],
                                  });
                                  if (context.mounted) Navigator.pop(context);
                                  _load();
                                  if (mounted) _showCreated(meeting, user);
                                } catch (e) {
                                  setS(() => loading = false);
                                  _snack('Failed: $e', AppColors.busy);
                                }
                              },
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.add_rounded),
                        label: Text(loading ? 'Creating...' : 'Create Meeting'),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      )),
                ]),
              )),
    );
  }

  void _showCreated(MeetingModel meeting, UserModel? user) {
    bool codeCopied = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        final themeColor = ctx.watch<AuthProvider>().themeColor;
        return Container(
          decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.online.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.online.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.online, size: 24),
                  SizedBox(width: 10),
                  Text('Meeting Created! ✅',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.online)),
                ])),
            const SizedBox(height: 20),
            const Text('MEETING CODE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: themeColor.withOpacity(0.3))),
              child: Row(children: [
                Expanded(
                    child: Text(meeting.code,
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 10,
                            color: themeColor),
                        textAlign: TextAlign.center)),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: meeting.code));
                    setS(() => codeCopied = true);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (ctx.mounted) setS(() => codeCopied = false);
                    });
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: codeCopied ? AppColors.online : themeColor,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(codeCopied ? '✅ Copied' : 'Copy',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700))),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('Share this code with others to join',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                final msg =
                    '📹 Meeting: ${meeting.title}\nCode: ${meeting.code}\nJoin via WorkSpace Pro → Meetings → Join with Code';
                Clipboard.setData(ClipboardData(text: msg));
                _snack('✅ Copied!', AppColors.online);
              },
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy Invite',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openRoom(meeting, user, isHost: true);
                  },
                  icon: const Icon(Icons.videocam_rounded, size: 22),
                  label: const Text('Start Meeting Now',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.online),
                )),
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Meetings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, size: 20), onPressed: _load)
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(
                child: _ActionBtn(
                    icon: Icons.login_rounded,
                    label: 'Join with\nCode',
                    color: AppColors.accent,
                    onTap: () => _showJoinWithCode(user))),
            const SizedBox(width: 12),
            Expanded(
                child: _ActionBtn(
                    icon: Icons.videocam_rounded,
                    label: 'Create\nMeeting',
                    color: themeColor,
                    onTap: () => _showCreateMeeting(user))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _meetings.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.videocam_off_outlined,
                              size: 64,
                              color: AppColors.textMuted.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          const Text('No meetings yet',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          const Text('Join with a code or create one',
                              style: TextStyle(color: AppColors.textMuted)),
                        ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _meetings.length,
                      itemBuilder: (ctx, i) {
                        final m = _meetings[i];
                        final isHost = m.organizerId == user?.id;
                        final isLive = m.status == 'ongoing';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isLive
                                      ? AppColors.online.withOpacity(0.5)
                                      : AppColors.border)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: isLive
                                              ? AppColors.online
                                                  .withOpacity(0.15)
                                              : themeColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Icon(Icons.videocam_rounded,
                                          color: isLive
                                              ? AppColors.online
                                              : themeColor,
                                          size: 22)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(m.title,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700)),
                                        Text(m.organizer,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted)),
                                      ])),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: isLive
                                              ? AppColors.online
                                                  .withOpacity(0.1)
                                              : AppColors.primary
                                                  .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(
                                          isLive
                                              ? '🔴 LIVE'
                                              : m.status.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isLive
                                                  ? AppColors.online
                                                  : AppColors.primary))),
                                ]),
                                if (m.code.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: themeColor.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color:
                                                themeColor.withOpacity(0.2))),
                                    child: Row(children: [
                                      Icon(Icons.tag_rounded,
                                          size: 14, color: themeColor),
                                      const SizedBox(width: 8),
                                      Text('Code',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: themeColor,
                                              fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(m.code,
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 4,
                                              color: themeColor)),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                          onTap: () {
                                            Clipboard.setData(
                                                ClipboardData(text: m.code));
                                            _snack('Copied!', themeColor);
                                          },
                                          child: Icon(Icons.copy_rounded,
                                              size: 16, color: themeColor)),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                      child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _openRoom(m, user, isHost: isHost),
                                    icon: Icon(
                                        isHost
                                            ? Icons.videocam_rounded
                                            : Icons.login_rounded,
                                        size: 16),
                                    label: Text(
                                        isHost
                                            ? (isLive ? 'Rejoin' : 'Start')
                                            : 'Join',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: isLive
                                            ? AppColors.online
                                            : themeColor,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8)),
                                  )),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                      onTap: () => _deleteMeeting(m),
                                      child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                              color:
                                                  Colors.red.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: Colors.red
                                                      .withOpacity(0.3))),
                                          child: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.red,
                                              size: 18))),
                                ]),
                              ]),
                        );
                      }),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}
