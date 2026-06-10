import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// REMOTE PARTICIPANT MODEL
// ══════════════════════════════════════════════════════════════════════════════

class RemoteParticipant {
  final String userId;
  final String userName;
  final bool isHost;
  bool audioEnabled;
  bool videoEnabled;
  bool handRaised;
  RTCPeerConnection? pc;
  MediaStream? stream;
  final RTCVideoRenderer renderer;

  RemoteParticipant({
    required this.userId,
    required this.userName,
    required this.isHost,
    this.audioEnabled = true,
    this.videoEnabled = true,
    this.handRaised = false,
  }) : renderer = RTCVideoRenderer();

  Future<void> initRenderer() async => await renderer.initialize();

  Future<void> dispose() async {
    await pc?.close();
    await stream?.dispose();
    await renderer.dispose();
  }
}

class WaitingUser {
  final String userId;
  final String userName;
  WaitingUser({required this.userId, required this.userName});
}

// ══════════════════════════════════════════════════════════════════════════════
// WEBRTC MEETING SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class WebRTCMeetingScreen extends StatefulWidget {
  final String meetingCode;
  final String meetingTitle;
  final bool isHost;

  const WebRTCMeetingScreen({
    super.key,
    required this.meetingCode,
    required this.meetingTitle,
    required this.isHost,
  });

  @override
  State<WebRTCMeetingScreen> createState() => _WebRTCMeetingScreenState();
}

class _WebRTCMeetingScreenState extends State<WebRTCMeetingScreen> {
  String _status = 'connecting';
  String _myUserId = '';
  String _myUserName = '';

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _audioEnabled = true;
  bool _videoEnabled = true;
  bool _frontCamera = true;

  final Map<String, RemoteParticipant> _participants = {};
  final List<WaitingUser> _waitingRoom = [];

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    _myUserId = auth.user?.id ?? '';
    _myUserName = auth.user?.name ?? 'Guest';
    final token = await ApiService.getToken() ?? '';
    await _localRenderer.initialize();
    await _startLocalMedia();
    await _connectWS(token);
  }

  Future<void> _startLocalMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Local media error: $e');
    }
  }

  Future<void> _connectWS(String token) async {
    final wsUrl =
        'wss://dingtalk-1b41.onrender.com/ws?token=$token&room=${widget.meetingCode}&is_host=${widget.isHost}&name=${Uri.encodeComponent(_myUserName)}';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _channel!.stream.listen(
        _onMessage,
        onError: (e) => debugPrint('WS error: $e'),
        onDone: () {
          if (mounted && _status != 'ended') setState(() => _status = 'ended');
        },
      );
      if (mounted)
        setState(() => _status = widget.isHost ? 'admitted' : 'waiting');
    } catch (e) {
      debugPrint('WS connect error: $e');
      if (mounted) setState(() => _status = 'admitted');
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) async {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case 'waiting_room':
        if (mounted) setState(() => _status = 'waiting');
        break;
      case 'admitted':
        if (mounted) setState(() => _status = 'admitted');
        break;
      case 'existing_participants':
        final list = msg['payload'] as List? ?? [];
        for (final p in list) {
          final uid = p['user_id'] as String;
          if (uid != _myUserId) {
            await _addParticipant(
                uid, p['user_name'] ?? '', p['is_host'] ?? false);
            await _createOffer(uid);
          }
        }
        break;
      case 'participants_update':
        final list = msg['payload'] as List? ?? [];
        for (final p in list) {
          final uid = p['user_id'] as String;
          if (uid != _myUserId && !_participants.containsKey(uid)) {
            await _addParticipant(
                uid, p['user_name'] ?? '', p['is_host'] ?? false);
          }
        }
        if (mounted) setState(() {});
        break;
      case 'waiting_update':
        final list = msg['payload'] as List? ?? [];
        if (mounted)
          setState(() {
            _waitingRoom.clear();
            for (final w in list) {
              _waitingRoom.add(WaitingUser(
                  userId: w['user_id'] ?? '', userName: w['user_name'] ?? ''));
            }
          });
        break;
      case 'participant_joined':
        final p = msg['payload'] as Map<String, dynamic>? ?? {};
        final uid = p['user_id'] as String? ?? '';
        if (uid.isNotEmpty &&
            uid != _myUserId &&
            !_participants.containsKey(uid)) {
          await _addParticipant(
              uid, p['user_name'] ?? '', p['is_host'] ?? false);
          await _createOffer(uid);
          if (mounted) setState(() {});
        }
        break;
      case 'participant_left':
        final p = msg['payload'] as Map<String, dynamic>? ?? {};
        await _removeParticipant(p['user_id'] as String? ?? '');
        break;
      case 'offer':
        await _handleOffer(msg);
        break;
      case 'answer':
        await _handleAnswer(msg);
        break;
      case 'ice_candidate':
        await _handleIceCandidate(msg);
        break;
      case 'media_state_update':
        final p = msg['payload'] as Map<String, dynamic>? ?? {};
        final uid = p['user_id'] as String? ?? '';
        if (_participants.containsKey(uid) && mounted)
          setState(() {
            if (p.containsKey('audio_enabled'))
              _participants[uid]!.audioEnabled = p['audio_enabled'] as bool;
            if (p.containsKey('video_enabled'))
              _participants[uid]!.videoEnabled = p['video_enabled'] as bool;
          });
        break;
      case 'muted':
        if (mounted) setState(() => _audioEnabled = false);
        _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
        _snack('You were muted by the host', AppColors.away);
        break;
      case 'video_disabled':
        if (mounted) setState(() => _videoEnabled = false);
        _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
        _snack('Your video was disabled by the host', AppColors.away);
        break;
      case 'removed':
        _snack('You were removed from the meeting', AppColors.busy);
        await _leaveMeeting();
        break;
      case 'rejected':
        if (mounted) setState(() => _status = 'rejected');
        break;
      case 'meeting_ended':
        _snack('Meeting ended by host', AppColors.busy);
        await _leaveMeeting();
        break;
      case 'hand_raised':
        final p = msg['payload'] as Map<String, dynamic>? ?? {};
        final uid = p['user_id'] as String? ?? '';
        if (_participants.containsKey(uid) && mounted) {
          setState(() =>
              _participants[uid]!.handRaised = p['raised'] as bool? ?? false);
        }
        break;
    }
  }

  Future<void> _addParticipant(
      String userId, String userName, bool isHost) async {
    if (_participants.containsKey(userId)) return;
    final p =
        RemoteParticipant(userId: userId, userName: userName, isHost: isHost);
    await p.initRenderer();
    _participants[userId] = p;
  }

  Future<void> _removeParticipant(String userId) async {
    final p = _participants.remove(userId);
    await p?.dispose();
    if (mounted) setState(() {});
  }

  Future<RTCPeerConnection> _createPC(String remoteUserId) async {
    final pc = await createPeerConnection(_iceConfig);
    _localStream
        ?.getTracks()
        .forEach((track) => pc.addTrack(track, _localStream!));
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted)
        setState(() {
          if (_participants.containsKey(remoteUserId)) {
            _participants[remoteUserId]!.renderer.srcObject = event.streams[0];
            _participants[remoteUserId]!.stream = event.streams[0];
          }
        });
    };
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _send({
          'type': 'ice_candidate',
          'target_id': remoteUserId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };
    return pc;
  }

  Future<void> _createOffer(String remoteUserId) async {
    final p = _participants[remoteUserId];
    if (p == null) return;
    final pc = await _createPC(remoteUserId);
    p.pc = pc;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({'type': 'offer', 'target_id': remoteUserId, 'sdp': offer.sdp});
  }

  Future<void> _handleOffer(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String? ?? '';
    final sdp = msg['sdp'] as String? ?? '';
    if (fromId.isEmpty || sdp.isEmpty) return;
    if (!_participants.containsKey(fromId))
      await _addParticipant(fromId, fromId, false);
    final p = _participants[fromId]!;
    final pc = await _createPC(fromId);
    p.pc = pc;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'target_id': fromId, 'sdp': answer.sdp});
    if (mounted) setState(() {});
  }

  Future<void> _handleAnswer(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String? ?? '';
    final sdp = msg['sdp'] as String? ?? '';
    final p = _participants[fromId];
    if (p?.pc == null) return;
    await p!.pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String? ?? '';
    final candidateMap = msg['candidate'] as Map<String, dynamic>?;
    if (candidateMap == null) return;
    final p = _participants[fromId];
    if (p?.pc == null) return;
    await p!.pc!.addCandidate(RTCIceCandidate(
      candidateMap['candidate'] as String?,
      candidateMap['sdpMid'] as String?,
      candidateMap['sdpMLineIndex'] as int?,
    ));
  }

  void _toggleAudio() {
    setState(() => _audioEnabled = !_audioEnabled);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _audioEnabled);
    _send({'type': 'media_state', 'audio_enabled': _audioEnabled});
  }

  void _toggleVideo() {
    setState(() => _videoEnabled = !_videoEnabled);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _videoEnabled);
    _send({'type': 'media_state', 'video_enabled': _videoEnabled});
  }

  void _flipCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    final tracks = _localStream?.getVideoTracks() ?? [];
    for (final track in tracks) await Helper.switchCamera(track);
  }

  void _admitUser(String userId) {
    _send({'type': 'admit_user', 'user_id': userId});
    setState(() => _waitingRoom.removeWhere((w) => w.userId == userId));
  }

  void _rejectUser(String userId) {
    _send({'type': 'reject_user', 'user_id': userId});
    setState(() => _waitingRoom.removeWhere((w) => w.userId == userId));
  }

  void _muteUser(String userId) =>
      _send({'type': 'mute_user', 'user_id': userId});
  void _removeUser(String userId) =>
      _send({'type': 'remove_participant', 'user_id': userId});

  void _endMeeting() {
    _send({'type': 'end_meeting'});
    _leaveMeeting();
  }

  Future<void> _leaveMeeting() async {
    if (mounted) setState(() => _status = 'ended');
    await _cleanUp();
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.pop(context);
    }
  }

  Future<void> _cleanUp() async {
    _wsSub?.cancel();
    _channel?.sink.close();
    for (final p in _participants.values) await p.dispose();
    _participants.clear();
    await _localStream?.dispose();
    await _localRenderer.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _cleanUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case 'connecting':
        return _buildConnecting();
      case 'waiting':
        return _buildWaiting();
      case 'rejected':
        return _buildRejected();
      case 'ended':
        return _buildEnded();
      default:
        return _buildMeeting();
    }
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
          const Text('Connecting…', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 32),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
        ])),
      );

  Widget _buildWaiting() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.hourglass_top_rounded,
                color: Colors.orange, size: 64),
            const SizedBox(height: 24),
            Text(widget.meetingTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('Waiting for the host to admit you…',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(14)),
              child: Text(widget.meetingCode,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6)),
            ),
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: () {
                _channel?.sink.close();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.exit_to_app, color: Colors.white54),
              label:
                  const Text('Leave', style: TextStyle(color: Colors.white54)),
            ),
          ]),
        )),
      );

  Widget _buildRejected() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.cancel_rounded, color: AppColors.busy, size: 64),
          const SizedBox(height: 20),
          const Text('Request Declined',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back')),
        ])),
      );

  Widget _buildEnded() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.call_end_rounded, color: AppColors.busy, size: 64),
          const SizedBox(height: 20),
          const Text('Meeting ended',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back')),
        ])),
      );

  Widget _buildMeeting() {
    final allParticipants = _participants.values.toList();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
          child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF1A1A2E),
          child: Row(children: [
            Expanded(
                child: Text(widget.meetingTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.online.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${allParticipants.length + 1} 👥',
                  style: const TextStyle(
                      color: AppColors.online,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            if (_waitingRoom.isNotEmpty) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showWaitingRoom,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.away.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_waitingRoom.length} waiting',
                      style: const TextStyle(
                          color: AppColors.away,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.meetingCode));
                _snack('Code copied!', AppColors.online);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(widget.meetingCode,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
              ),
            ),
          ]),
        ),
        Expanded(
            child: allParticipants.isEmpty
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Container(
                            width: 120,
                            height: 120,
                            decoration: const BoxDecoration(
                                color: Color(0xFF2A2A4A),
                                shape: BoxShape.circle),
                            child: Center(
                                child: Text(
                                    _myUserName.isNotEmpty
                                        ? _myUserName[0].toUpperCase()
                                        : 'Y',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w800)))),
                        const SizedBox(height: 16),
                        Text(_myUserName,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('Waiting for others to join…',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 13)),
                      ]))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: allParticipants.length == 1 ? 1 : 2,
                      childAspectRatio: 3 / 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: allParticipants.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) return _buildLocalTile();
                      return _buildRemoteTile(allParticipants[i - 1]);
                    },
                  )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          color: const Color(0xFF1A1A2E),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _ControlBtn(
                icon: _audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                label: _audioEnabled ? 'Mute' : 'Unmute',
                color: _audioEnabled ? Colors.white : AppColors.busy,
                onTap: _toggleAudio),
            _ControlBtn(
                icon: _videoEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: _videoEnabled ? 'Video' : 'No Video',
                color: _videoEnabled ? Colors.white : AppColors.busy,
                onTap: _toggleVideo),
            _ControlBtn(
                icon: Icons.flip_camera_ios_rounded,
                label: 'Flip',
                color: Colors.white,
                onTap: _flipCamera),
            if (widget.isHost)
              _ControlBtn(
                  icon: Icons.people_rounded,
                  label: 'People',
                  color: Colors.white,
                  onTap: _showParticipantsList,
                  badge: _waitingRoom.isNotEmpty ? _waitingRoom.length : null),
            _ControlBtn(
                icon: Icons.call_end_rounded,
                label: widget.isHost ? 'End' : 'Leave',
                color: AppColors.busy,
                bgColor: AppColors.busy,
                onTap: widget.isHost ? _confirmEnd : () => _leaveMeeting()),
          ]),
        ),
      ])),
    );
  }

  Widget _buildLocalTile() => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF2A2A4A),
            borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(fit: StackFit.expand, children: [
            if (_videoEnabled && _localRenderer.srcObject != null)
              RTCVideoView(_localRenderer,
                  mirror: _frontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              Center(
                  child: Text(
                      _myUserName.isNotEmpty
                          ? _myUserName[0].toUpperCase()
                          : 'Y',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800))),
            Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!_audioEnabled)
                      const Icon(Icons.mic_off_rounded,
                          color: AppColors.busy, size: 12),
                    const SizedBox(width: 4),
                    const Text('You',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                )),
          ]),
        ),
      );

  Widget _buildRemoteTile(RemoteParticipant p) => GestureDetector(
        onLongPress: widget.isHost ? () => _showParticipantOptions(p) : null,
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF2A2A4A),
              borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              if (p.videoEnabled && p.renderer.srcObject != null)
                RTCVideoView(p.renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              else
                Center(
                    child: Text(
                        p.userName.isNotEmpty
                            ? p.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800))),
              if (p.handRaised)
                const Positioned(
                    top: 8,
                    right: 8,
                    child: Text('✋', style: TextStyle(fontSize: 24))),
              Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!p.audioEnabled)
                        const Icon(Icons.mic_off_rounded,
                            color: AppColors.busy, size: 12),
                      if (p.isHost)
                        const Icon(Icons.star_rounded,
                            color: AppColors.away, size: 12),
                      const SizedBox(width: 4),
                      Text(p.userName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                  )),
            ]),
          ),
        ),
      );

  void _showWaitingRoom() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Waiting Room',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700))),
        ..._waitingRoom.map((w) => ListTile(
              leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: Color(0xFF2A2A4A), shape: BoxShape.circle),
                  child: Center(
                      child: Text(
                          w.userName.isNotEmpty
                              ? w.userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)))),
              title:
                  Text(w.userName, style: const TextStyle(color: Colors.white)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _rejectUser(w.userId);
                    },
                    child: const Text('Deny',
                        style: TextStyle(color: AppColors.busy))),
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _admitUser(w.userId);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.online),
                    child: const Text('Admit')),
              ]),
            )),
        const SizedBox(height: 16),
      ]),
    );
  }

  void _showParticipantsList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scroll) => Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Text('Participants',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_waitingRoom.isNotEmpty)
                  TextButton(
                      onPressed: _showWaitingRoom,
                      child: Text('${_waitingRoom.length} waiting',
                          style: const TextStyle(color: AppColors.away))),
              ])),
          Expanded(
              child: ListView(controller: scroll, children: [
            ListTile(
              leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: Color(0xFF2A2A4A), shape: BoxShape.circle),
                  child: Center(
                      child: Text(
                          _myUserName.isNotEmpty
                              ? _myUserName[0].toUpperCase()
                              : 'Y',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)))),
              title: Text('$_myUserName (You)',
                  style: const TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.star_rounded,
                  color: AppColors.away, size: 16),
            ),
            ..._participants.values.map((p) => ListTile(
                  leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          color: Color(0xFF2A2A4A), shape: BoxShape.circle),
                      child: Center(
                          child: Text(
                              p.userName.isNotEmpty
                                  ? p.userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)))),
                  title: Text(p.userName,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Row(children: [
                    Icon(
                        p.audioEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        size: 14,
                        color:
                            p.audioEnabled ? Colors.white54 : AppColors.busy),
                    const SizedBox(width: 4),
                    Icon(
                        p.videoEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        size: 14,
                        color:
                            p.videoEnabled ? Colors.white54 : AppColors.busy),
                  ]),
                  trailing: widget.isHost
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white54),
                          color: const Color(0xFF2A2A4A),
                          onSelected: (val) {
                            Navigator.pop(context);
                            if (val == 'mute') _muteUser(p.userId);
                            if (val == 'remove') _removeUser(p.userId);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'mute',
                                child: Text('Mute',
                                    style: TextStyle(color: Colors.white))),
                            const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove',
                                    style: TextStyle(color: AppColors.busy))),
                          ],
                        )
                      : null,
                )),
          ])),
        ]),
      ),
    );
  }

  void _showParticipantOptions(RemoteParticipant p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Text(p.userName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700))),
        ListTile(
            leading: const Icon(Icons.mic_off_rounded, color: AppColors.away),
            title: const Text('Mute', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _muteUser(p.userId);
            }),
        ListTile(
            leading:
                const Icon(Icons.person_remove_rounded, color: AppColors.busy),
            title: const Text('Remove from meeting',
                style: TextStyle(color: AppColors.busy)),
            onTap: () {
              Navigator.pop(context);
              _removeUser(p.userId);
            }),
        const SizedBox(height: 16),
      ]),
    );
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title:
            const Text('End Meeting?', style: TextStyle(color: Colors.white)),
        content: const Text('This will end the meeting for everyone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _endMeeting();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
            child: const Text('End for All'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONTROL BUTTON WIDGET
// ══════════════════════════════════════════════════════════════════════════════

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? bgColor;
  final VoidCallback onTap;
  final int? badge;

  const _ControlBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      this.bgColor,
      this.badge});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Stack(children: [
            Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: bgColor != null
                        ? bgColor!.withOpacity(0.2)
                        : Colors.white12,
                    shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24)),
            if (badge != null)
              Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                        color: AppColors.busy, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$badge',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))),
                  )),
          ]),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// MEETING SCREEN (main tab)
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

  void _openRoom(MeetingModel meeting, UserModel? user,
      {required bool isHost}) {
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebRTCMeetingScreen(
            meetingCode: meeting.code,
            meetingTitle: meeting.title,
            isHost: isHost,
          ),
        ));
  }

  void _showNewMeeting(UserModel? user) {
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
                          Text('New Meeting',
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

  void _showJoinWithCode(UserModel? user) {
    final codeCtrl = TextEditingController();
    bool loading = false;
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
                          Text('Join Meeting',
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
                        onPressed: loading
                            ? null
                            : () async {
                                final code = codeCtrl.text.trim().toUpperCase();
                                if (code.isEmpty) {
                                  setS(() => error = 'Enter the code');
                                  return;
                                }
                                setS(() {
                                  loading = true;
                                  error = '';
                                });
                                try {
                                  final meeting =
                                      await ApiService.getMeetingByCode(code);
                                  if (context.mounted) Navigator.pop(context);
                                  if (mounted)
                                    _openRoom(meeting, user, isHost: false);
                                } catch (_) {
                                  setS(() {
                                    loading = false;
                                    error =
                                        'Meeting not found. Check the code.';
                                  });
                                }
                              },
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.login_rounded),
                        label: Text(loading ? 'Joining...' : 'Join Meeting'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: codeCopied ? AppColors.online : themeColor,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(codeCopied ? '✅ Copied' : 'Copy',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Text('Share this code with employees to let them join',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final chats = await ApiService.getChats();
                if (!mounted) return;
                if (context.mounted) Navigator.pop(context);
                if (mounted) _showShareInChat(meeting, chats);
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Invite to Employee Chat',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                final msg =
                    '📹 Meeting Invite\nTitle: ${meeting.title}\nCode: ${meeting.code}\n\nOpen WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
                Clipboard.setData(ClipboardData(text: msg));
                _snack('✅ Invite copied!', AppColors.online);
              },
              icon: const Icon(Icons.copy_all_rounded, size: 16),
              label: const Text('Copy Invite Text',
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

  void _showShareInChat(MeetingModel meeting, List<ChatModel> chats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                const Expanded(
                    child: Text('Send Invite to Chat',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ])),
          Expanded(
              child: chats.isEmpty
                  ? const Center(child: Text('No chats available'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: chats.length,
                      itemBuilder: (ctx, i) {
                        final chat = chats[i];
                        return ListTile(
                          leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle),
                              child: Icon(
                                  chat.isGroup
                                      ? Icons.group_rounded
                                      : Icons.person_rounded,
                                  color: AppColors.primary,
                                  size: 22)),
                          title: Text(chat.name.isEmpty ? 'Chat' : chat.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          trailing: const Icon(Icons.send_rounded,
                              color: AppColors.primary),
                          onTap: () async {
                            Navigator.pop(context);
                            final msg =
                                '📹 Meeting Invite\n━━━━━━━━━━━━━━━━━\nTitle: ${meeting.title}\nCode:  ${meeting.code}\n━━━━━━━━━━━━━━━━━\nOpen WorkSpace Pro → Meetings → Join with Code → ${meeting.code}';
                            try {
                              await ApiService.sendMessage(chat.id, msg);
                              _snack('✅ Invite sent to ${chat.name}!',
                                  AppColors.online);
                            } catch (e) {
                              _snack('Failed: $e', AppColors.busy);
                            }
                          },
                        );
                      })),
        ]),
      ),
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
                child: ElevatedButton.icon(
              onPressed: () => _showNewMeeting(user),
              icon: const Icon(Icons.videocam_rounded),
              label: const Text('New Meeting',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton.icon(
              onPressed: () => _showJoinWithCode(user),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Join with Code',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
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
                          const Text('Tap New Meeting to create one',
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
                                            ? AppColors.online.withOpacity(0.1)
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
                                                : AppColors.primary)),
                                  ),
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
                                          _snack('Code ${m.code} copied!',
                                              themeColor);
                                        },
                                        child: Icon(Icons.copy_rounded,
                                            size: 16, color: themeColor),
                                      ),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(children: [
                                  if (isHost && m.code.isNotEmpty) ...[
                                    Expanded(
                                        child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final chats =
                                            await ApiService.getChats();
                                        if (mounted) _showShareInChat(m, chats);
                                      },
                                      icon: const Icon(Icons.share_rounded,
                                          size: 14),
                                      label: const Text('Share',
                                          style: TextStyle(fontSize: 13)),
                                      style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8)),
                                    )),
                                    const SizedBox(width: 8),
                                  ],
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
                                ]),
                              ]),
                        );
                      }),
        ),
      ]),
    );
  }
}
