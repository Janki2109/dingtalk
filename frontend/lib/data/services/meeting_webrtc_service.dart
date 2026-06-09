import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/app_constants.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

enum MeetingStatus { connecting, waiting, inMeeting, rejected, removed, ended }

class MeetingParticipant {
  final String userId;
  final String userName;
  final bool isHost;
  bool audioEnabled;
  bool videoEnabled;
  bool handRaised;

  MeetingParticipant({
    required this.userId,
    required this.userName,
    required this.isHost,
    this.audioEnabled = true,
    this.videoEnabled = true,
    this.handRaised = false,
  });

  factory MeetingParticipant.fromMap(Map<String, dynamic> m) =>
      MeetingParticipant(
        userId: m['user_id'] ?? '',
        userName: m['user_name'] ?? '',
        isHost: m['is_host'] ?? false,
        audioEnabled: m['audio_enabled'] ?? true,
        videoEnabled: m['video_enabled'] ?? true,
        handRaised: m['hand_raised'] ?? false,
      );
}

class WaitingUser {
  final String userId;
  final String userName;

  WaitingUser({required this.userId, required this.userName});

  factory WaitingUser.fromMap(Map<String, dynamic> m) =>
      WaitingUser(userId: m['user_id'] ?? '', userName: m['user_name'] ?? '');
}

class MeetingChatMsg {
  final String userId;
  final String userName;
  final String content;
  final String time;
  final bool isOwn;

  MeetingChatMsg({
    required this.userId,
    required this.userName,
    required this.content,
    required this.time,
    this.isOwn = false,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class MeetingWebRTCService extends ChangeNotifier {
  // ── Local state ────────────────────────────────────────────────────────────
  String? _myUserId;
  String? _myUserName;
  bool _isHost = false;

  MeetingStatus status = MeetingStatus.connecting;
  bool micEnabled = true;
  bool cameraEnabled = true;
  bool screenSharing = false;
  bool handRaised = false;

  // ── Participants & waiting ─────────────────────────────────────────────────
  final Map<String, MeetingParticipant> participants = {};
  final List<WaitingUser> waitingRoom = [];
  final List<MeetingChatMsg> chatMessages = [];

  // ── WebRTC ─────────────────────────────────────────────────────────────────
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> remoteRenderers = {};
  final Map<String, RTCPeerConnection> peerConnections = {};
  MediaStream? _localStream;
  MediaStream? _screenStream;

  // ── WebSocket ──────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  bool _disposed = false;

  // ── Callbacks for navigation ───────────────────────────────────────────────
  VoidCallback? onMeetingEnded;
  VoidCallback? onRemoved;
  VoidCallback? onRejected;
  VoidCallback? onAdmitted;

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<void> connect({
    required String roomCode,
    required String meetingId,
    required String userId,
    required String userName,
    required String token,
    required bool isHost,
  }) async {
    _myUserId = userId;
    _myUserName = userName;
    _isHost = isHost;
    status = MeetingStatus.connecting;

    await localRenderer.initialize();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user'},
      });
      localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Media error: $e');
    }

    final wsBase = AppConstants.serverUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse(
      '$wsBase/ws/meeting?room=${Uri.encodeComponent(roomCode)}'
      '&meeting_id=${Uri.encodeComponent(meetingId)}'
      '&is_host=$isHost'
      '&name=${Uri.encodeComponent(userName)}'
      '&token=${Uri.encodeComponent(token)}',
    );

    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(_onMessage, onDone: _onDisconnect, onError: (_) => _onDisconnect());

    if (isHost) {
      status = MeetingStatus.inMeeting;
    } else {
      status = MeetingStatus.waiting;
    }
    _notify();
  }

  // ── Message handler ────────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['type'] as String? ?? '';

    switch (type) {
      case 'waiting_room':
        status = MeetingStatus.waiting;
        _notify();

      case 'admitted':
        status = MeetingStatus.inMeeting;
        onAdmitted?.call();
        _notify();

      case 'rejected':
        status = MeetingStatus.rejected;
        onRejected?.call();
        _notify();

      case 'existing_participants':
        // Admitted user gets list of current participants → initiate offers
        final list = (msg['payload'] as List?) ?? [];
        for (final p in list) {
          final peerId = p['user_id'] as String? ?? '';
          if (peerId.isNotEmpty && peerId != _myUserId) {
            participants[peerId] = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
            _createOfferTo(peerId);
          }
        }
        _notify();

      case 'participants_update':
        final list = (msg['payload'] as List?) ?? [];
        participants.clear();
        for (final p in list) {
          final peerId = p['user_id'] as String? ?? '';
          if (peerId.isNotEmpty && peerId != _myUserId) {
            participants[peerId] = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
          }
        }
        _notify();

      case 'participant_joined':
        final p = msg['payload'];
        if (p != null) {
          final peerId = p['user_id'] as String? ?? '';
          if (peerId.isNotEmpty && peerId != _myUserId) {
            participants[peerId] = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
          }
        }
        _notify();

      case 'participant_left':
        final payload = msg['payload'];
        final peerId = payload is Map ? (payload['user_id'] as String? ?? '') : '';
        if (peerId.isNotEmpty) {
          _removePeer(peerId);
          participants.remove(peerId);
          _notify();
        }

      case 'waiting_update':
        waitingRoom.clear();
        final list = (msg['payload'] as List?) ?? [];
        for (final w in list) {
          waitingRoom.add(WaitingUser.fromMap(Map<String, dynamic>.from(w)));
        }
        _notify();

      // ── WebRTC signaling ──────────────────────────────────────────────────

      case 'offer':
        final fromId = msg['from_id'] as String? ?? '';
        final sdp = msg['sdp'] as String? ?? '';
        if (fromId.isNotEmpty && sdp.isNotEmpty) _handleOffer(fromId, sdp);

      case 'answer':
        final fromId = msg['from_id'] as String? ?? '';
        final sdp = msg['sdp'] as String? ?? '';
        if (fromId.isNotEmpty && sdp.isNotEmpty) _handleAnswer(fromId, sdp);

      case 'ice_candidate':
        final fromId = msg['from_id'] as String? ?? '';
        final cand = msg['candidate'];
        if (fromId.isNotEmpty && cand != null) _handleIce(fromId, cand);

      // ── Room events ───────────────────────────────────────────────────────

      case 'hand_raised':
        final payload = msg['payload'];
        if (payload is Map) {
          final uid = payload['user_id'] as String? ?? '';
          final raised = payload['raised'] as bool? ?? false;
          if (participants.containsKey(uid)) {
            participants[uid]!.handRaised = raised;
            _notify();
          }
        }

      case 'chat_message':
        final payload = msg['payload'];
        if (payload is Map) {
          chatMessages.add(MeetingChatMsg(
            userId: payload['user_id'] ?? '',
            userName: payload['user_name'] ?? '',
            content: payload['content'] ?? '',
            time: msg['time'] ?? '',
            isOwn: payload['user_id'] == _myUserId,
          ));
          _notify();
        }

      case 'media_state_update':
        final payload = msg['payload'];
        if (payload is Map) {
          final uid = payload['user_id'] as String? ?? '';
          if (participants.containsKey(uid)) {
            if (payload['audio_enabled'] != null) {
              participants[uid]!.audioEnabled = payload['audio_enabled'] as bool;
            }
            if (payload['video_enabled'] != null) {
              participants[uid]!.videoEnabled = payload['video_enabled'] as bool;
            }
            _notify();
          }
        }

      case 'muted':
        final payload = msg['payload'];
        if (payload is Map && (payload['user_id'] == _myUserId)) {
          micEnabled = false;
          _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
          _notify();
        }

      case 'video_disabled':
        final payload = msg['payload'];
        if (payload is Map && (payload['user_id'] == _myUserId)) {
          cameraEnabled = false;
          _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
          _notify();
        }

      case 'removed':
        status = MeetingStatus.removed;
        onRemoved?.call();
        _notify();

      case 'meeting_ended':
        status = MeetingStatus.ended;
        onMeetingEnded?.call();
        _notify();
    }
  }

  void _onDisconnect() {
    if (_disposed) return;
    if (status != MeetingStatus.ended &&
        status != MeetingStatus.removed &&
        status != MeetingStatus.rejected) {
      status = MeetingStatus.ended;
      onMeetingEnded?.call();
      _notify();
    }
  }

  // ── WebRTC helpers ─────────────────────────────────────────────────────────

  static const _iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      }
    ],
  };

  Future<RTCPeerConnection> _getOrCreatePC(String peerId) async {
    if (peerConnections.containsKey(peerId)) return peerConnections[peerId]!;

    final pc = await createPeerConnection(_iceServers);
    peerConnections[peerId] = pc;

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    remoteRenderers[peerId] = renderer;

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderers[peerId]?.srcObject = event.streams.first;
        _notify();
      }
    };

    pc.onIceCandidate = (cand) {
      if (cand.candidate != null) {
        _send({
          'type': 'ice_candidate',
          'target_id': peerId,
          'candidate': {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          },
        });
      }
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _removePeer(peerId);
        _notify();
      }
    };

    return pc;
  }

  Future<void> _createOfferTo(String peerId) async {
    final pc = await _getOrCreatePC(peerId);
    final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(offer);
    _send({'type': 'offer', 'target_id': peerId, 'sdp': offer.sdp});
  }

  Future<void> _handleOffer(String fromId, String sdp) async {
    if (!participants.containsKey(fromId)) {
      participants[fromId] = MeetingParticipant(userId: fromId, userName: fromId, isHost: false);
    }
    final pc = await _getOrCreatePC(fromId);
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await pc.createAnswer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'target_id': fromId, 'sdp': answer.sdp});
  }

  Future<void> _handleAnswer(String fromId, String sdp) async {
    final pc = peerConnections[fromId];
    if (pc != null) {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    }
  }

  Future<void> _handleIce(String fromId, dynamic candidate) async {
    final pc = peerConnections[fromId];
    if (pc != null && candidate is Map) {
      await pc.addCandidate(RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ));
    }
  }

  void _removePeer(String peerId) {
    peerConnections[peerId]?.close();
    peerConnections.remove(peerId);
    remoteRenderers[peerId]?.dispose();
    remoteRenderers.remove(peerId);
  }

  // ── Controls ───────────────────────────────────────────────────────────────

  void toggleMic() {
    micEnabled = !micEnabled;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = micEnabled);
    _send({'type': 'media_state', 'audio_enabled': micEnabled, 'video_enabled': cameraEnabled});
    _notify();
  }

  void toggleCamera() {
    cameraEnabled = !cameraEnabled;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = cameraEnabled);
    _send({'type': 'media_state', 'audio_enabled': micEnabled, 'video_enabled': cameraEnabled});
    _notify();
  }

  Future<void> toggleScreenShare() async {
    if (screenSharing) {
      _screenStream?.getTracks().forEach((t) => t.stop());
      _screenStream = null;
      screenSharing = false;
      // Restore camera video track
      final camTrack = _localStream?.getVideoTracks().firstOrNull;
      if (camTrack != null) {
        for (final pc in peerConnections.values) {
          final senders = await pc.getSenders();
          for (final s in senders) {
            if (s.track?.kind == 'video') await s.replaceTrack(camTrack);
          }
        }
      }
    } else {
      try {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({'video': true});
        final screenTrack = _screenStream?.getVideoTracks().firstOrNull;
        if (screenTrack != null) {
          screenSharing = true;
          for (final pc in peerConnections.values) {
            final senders = await pc.getSenders();
            for (final s in senders) {
              if (s.track?.kind == 'video') await s.replaceTrack(screenTrack);
            }
          }
          screenTrack.onEnded = () {
            screenSharing = false;
            _screenStream = null;
            _notify();
          };
        }
      } catch (_) {
        screenSharing = false;
      }
    }
    _notify();
  }

  void toggleHandRaise() {
    handRaised = !handRaised;
    _send({'type': 'raise_hand', 'raised': handRaised});
    _notify();
  }

  void sendChat(String content) {
    if (content.trim().isEmpty) return;
    _send({'type': 'chat', 'content': content.trim()});
    chatMessages.add(MeetingChatMsg(
      userId: _myUserId ?? '',
      userName: _myUserName ?? 'You',
      content: content.trim(),
      time: DateTime.now().toIso8601String(),
      isOwn: true,
    ));
    _notify();
  }

  // ── Admin controls ─────────────────────────────────────────────────────────

  void admitUser(String userId) => _send({'type': 'admit_user', 'user_id': userId});
  void rejectUser(String userId) => _send({'type': 'reject_user', 'user_id': userId});
  void muteUser(String userId) => _send({'type': 'mute_user', 'user_id': userId});
  void disableUserVideo(String userId) => _send({'type': 'disable_video', 'user_id': userId});
  void removeParticipant(String userId) => _send({'type': 'remove_participant', 'user_id': userId});
  void endMeeting() => _send({'type': 'end_meeting'});

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isHost => _isHost;
  String? get myUserId => _myUserId;

  @override
  void dispose() {
    _disposed = true;
    _localStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.getTracks().forEach((t) => t.stop());
    for (final pc in peerConnections.values) {
      pc.close();
    }
    for (final r in remoteRenderers.values) {
      r.dispose();
    }
    localRenderer.dispose();
    try {
      _channel?.sink.close();
    } catch (_) {}
    super.dispose();
  }
}
