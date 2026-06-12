import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_provider.dart';

const String _agoraAppId = '';
const String _agoraToken =
    '007eJxTYNBafGJhpBez6u7i02Z5jx4t4J7Cv3rJzDjZ9Yx7jGddK72qwGBiaZCSZGGQmpximWSSbJKSmGaeZJJmmWSQZpGWZJ6a2L9EO6shkJHh75twBkYoBPHZGXJTU0sy89IZGADa5SI2';

class AgoraMeetingScreen extends StatefulWidget {
  final String channelName;
  final String meetingTitle;
  final String meetingId;
  final bool isHost;
  final int uid;

  const AgoraMeetingScreen({
    super.key,
    required this.channelName,
    required this.meetingTitle,
    required this.meetingId,
    required this.isHost,
    required this.uid,
  });

  @override
  State<AgoraMeetingScreen> createState() => _AgoraMeetingScreenState();
}

class _AgoraMeetingScreenState extends State<AgoraMeetingScreen> {
  RtcEngine? _engine;
  bool _localUserJoined = false;
  bool _micMuted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _chatOpen = false;
  bool _participantsOpen = false;
  bool _handRaised = false;
  bool _loading = true;
  String _statusMsg = 'Connecting...';

  final List<int> _remoteUids = [];
  final List<_ChatMsg> _chatMessages = [];
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initAgora();
  }

  Future<void> _initAgora() async {
    await [Permission.microphone, Permission.camera].request();
    setState(() => _statusMsg = 'Setting up camera & mic...');

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: _agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    await _engine!.enableVideo();
    await _engine!.enableAudio();
    await _engine!.startPreview();
    await _engine!.setEnableSpeakerphone(true);

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        if (mounted)
          setState(() {
            _localUserJoined = true;
            _loading = false;
          });
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (mounted)
          setState(() {
            if (!_remoteUids.contains(remoteUid)) _remoteUids.add(remoteUid);
          });
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (mounted) setState(() => _remoteUids.remove(remoteUid));
      },
      onError: (err, msg) {
        if (mounted)
          setState(() {
            _loading = false;
            _statusMsg = 'Error: $msg';
          });
      },
    ));

    setState(() => _statusMsg = 'Joining meeting...');

    await _engine!.joinChannel(
      token: _agoraToken,
      channelId: widget.channelName,
      uid: widget.uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _engine?.leaveChannel();
    _engine?.release();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toggleMic() async {
    _micMuted = !_micMuted;
    await _engine?.muteLocalAudioStream(_micMuted);
    setState(() {});
  }

  void _toggleCamera() async {
    _cameraOff = !_cameraOff;
    await _engine?.muteLocalVideoStream(_cameraOff);
    setState(() {});
  }

  void _switchCamera() async => await _engine?.switchCamera();
  void _toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await _engine?.setEnableSpeakerphone(_speakerOn);
    setState(() {});
  }

  void _endCall() {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(widget.isHost ? 'End Meeting?' : 'Leave Meeting?'),
              content: Text(widget.isHost
                  ? 'This will end for everyone.'
                  : 'Are you sure?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(widget.isHost ? 'End for All' : 'Leave'),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
          child: Column(children: [
        _buildTopBar(),
        Expanded(
            child: Row(children: [
          Expanded(child: _buildVideoGrid()),
          if (_chatOpen) _buildChatPanel(),
          if (_participantsOpen) _buildParticipantsPanel(),
        ])),
        _buildControls(),
      ])),
    );
  }

  Widget _buildLoading() => Scaffold(
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
          Text(_statusMsg, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 40),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
        ])),
      );

  Widget _buildTopBar() => Container(
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
                Text('${_remoteUids.length + 1} in call',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
          GestureDetector(
              onTap: _switchCamera,
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.flip_camera_ios_rounded,
                      color: Colors.white, size: 20))),
          const SizedBox(width: 8),
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

  Widget _buildVideoGrid() {
    final myName = context.read<AuthProvider>().user?.name ?? 'You';
    if (_remoteUids.isEmpty) {
      return Container(
          color: const Color(0xFF0F0F0F),
          child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                SizedBox(
                    width: 280, height: 200, child: _buildLocalVideo(myName)),
                const SizedBox(height: 16),
                const Text('Waiting for others to join...',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ])));
    }
    final total = _remoteUids.length + 1;
    final crossCount = total <= 2 ? 1 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          childAspectRatio: 4 / 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6),
      itemCount: total,
      itemBuilder: (ctx, i) => i == 0
          ? _buildLocalVideo(myName)
          : _buildRemoteVideo(_remoteUids[i - 1]),
    );
  }

  Widget _buildLocalVideo(String name) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              _cameraOff
                  ? Center(
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
                        ]))
                  : (_localUserJoined
                      ? AgoraVideoView(
                          controller: VideoViewController(
                              rtcEngine: _engine!,
                              canvas: const VideoCanvas(uid: 0)))
                      : const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white))),
              Positioned(
                  bottom: 8,
                  left: 8,
                  child: _nameTag(
                      'You${widget.isHost ? ' (Host)' : ''}', _micMuted)),
              if (_handRaised)
                Positioned(top: 8, right: 8, child: _handBadge()),
            ])),
      );

  Widget _buildRemoteVideo(int uid) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              AgoraVideoView(
                  controller: VideoViewController.remote(
                      rtcEngine: _engine!,
                      canvas: VideoCanvas(uid: uid),
                      connection:
                          RtcConnection(channelId: widget.channelName))),
              Positioned(
                  bottom: 8, left: 8, child: _nameTag('User $uid', false)),
            ])),
      );

  Widget _nameTag(String name, bool muted) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (muted) ...[
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

  Widget _buildControls() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: const Color(0xFF1A1A1A),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ctrl(
              _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              _micMuted ? Colors.red : Colors.white,
              _micMuted ? 'Unmute' : 'Mute',
              _toggleMic),
          _ctrl(
              _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              _cameraOff ? Colors.red : Colors.white,
              _cameraOff ? 'Start\nCam' : 'Stop\nCam',
              _toggleCamera),
          _ctrl(
              _speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              _speakerOn ? Colors.white : Colors.red,
              'Speaker',
              _toggleSpeaker),
          _ctrl(
              _handRaised ? Icons.back_hand_rounded : Icons.back_hand_outlined,
              _handRaised ? Colors.orange : Colors.white,
              'Raise\nHand',
              () => setState(() => _handRaised = !_handRaised)),
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
              onTap: _endCall,
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

  Widget _buildChatPanel() {
    final myName = context.read<AuthProvider>().user?.name ?? 'You';
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
            child: _chatMessages.isEmpty
                ? const Center(
                    child: Text('No messages yet',
                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(10),
                    itemCount: _chatMessages.length,
                    itemBuilder: (ctx, i) {
                      final msg = _chatMessages[i];
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
                                  Text(msg.sender,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                Text(msg.text,
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
                  if (v.trim().isNotEmpty) {
                    setState(() => _chatMessages.add(
                        _ChatMsg(sender: myName, text: v.trim(), isOwn: true)));
                    _chatCtrl.clear();
                  }
                },
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_chatCtrl.text.trim().isNotEmpty) {
                    setState(() => _chatMessages.add(_ChatMsg(
                        sender: myName,
                        text: _chatCtrl.text.trim(),
                        isOwn: true)));
                    _chatCtrl.clear();
                  }
                },
                child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(17)),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 16)),
              ),
            ])),
      ]),
    );
  }

  Widget _buildParticipantsPanel() => Container(
        width: 260,
        decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(left: BorderSide(color: Colors.white12))),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: Text('People (${_remoteUids.length + 1})',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700))),
                GestureDetector(
                    onTap: () => setState(() => _participantsOpen = false),
                    child: const Icon(Icons.close,
                        color: Colors.white54, size: 18)),
              ])),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
              child: ListView(padding: const EdgeInsets.all(8), children: [
            _pTile(context.read<AuthProvider>().user?.name ?? 'You',
                isMe: true, isHost: widget.isHost),
            ..._remoteUids
                .map((uid) => _pTile('User $uid', isMe: false, isHost: false)),
          ])),
        ]),
      );

  Widget _pTile(String name, {required bool isMe, required bool isHost}) =>
      ListTile(
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
        ]),
      );
}

class _ChatMsg {
  final String sender, text;
  final bool isOwn;
  _ChatMsg({required this.sender, required this.text, required this.isOwn});
}
