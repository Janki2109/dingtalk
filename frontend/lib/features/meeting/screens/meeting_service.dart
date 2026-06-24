import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants/app_constants.dart';

enum MeetingStatus { connecting, waiting, inMeeting, rejected, removed, ended }

class MeetingParticipant {
  final String userId;
  final String userName;
  final bool isHost;
  bool audioEnabled;
  bool videoEnabled;
  bool handRaised;
  RTCVideoRenderer? renderer;

  MeetingParticipant({
    required this.userId,
    required this.userName,
    required this.isHost,
    this.audioEnabled = true,
    this.videoEnabled = true,
    this.handRaised = false,
    this.renderer,
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
  final bool isOwn;
  MeetingChatMsg({
    required this.userId,
    required this.userName,
    required this.content,
    this.isOwn = false,
  });
}

class MeetingService extends ChangeNotifier {
  String? _myUserId;
  String? _myUserName;
  bool _isHost = false;

  MeetingStatus status = MeetingStatus.connecting;
  bool micEnabled = true;
  bool cameraEnabled = true;
  bool handRaised = false;
  bool screenSharing = false;
  bool _togglingScreenShare = false; // FIX BUG 24: re-entrancy guard

  final List<MeetingParticipant> participants = [];
  final List<WaitingUser> waitingRoom = [];
  final List<MeetingChatMsg> chatMessages = [];

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  MediaStream? _screenStream;
  bool _localRendererInit = false;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;

  VoidCallback? onAdmitted;
  VoidCallback? onRejected;
  VoidCallback? onRemoved;
  VoidCallback? onMeetingEnded;

  bool get isHost => _isHost;

  static const _iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
      {
        'urls': ['turn:openrelay.metered.ca:80'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': ['turn:openrelay.metered.ca:443'],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ]
  };

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
    _notify();

    await localRenderer.initialize();
    _localRendererInit = true;

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Media error: $e');
      try {
        // FIX BUG 21: set srcObject even for audio-only fallback
        _localStream = await navigator.mediaDevices
            .getUserMedia({'audio': true, 'video': false});
        localRenderer.srcObject = _localStream;
      } catch (_) {}
    }

    final wsBase = AppConstants.serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    // FIX BUG 27: remove token from URL — send as first WebSocket message
    final uri = Uri.parse(
      '$wsBase/ws/meeting'
      '?room=${Uri.encodeComponent(roomCode)}'
      '&meeting_id=${Uri.encodeComponent(meetingId)}'
      '&name=${Uri.encodeComponent(userName)}',
    );

    try {
      _channel = WebSocketChannel.connect(uri);

      // FIX BUG 27: send token as first message instead of URL param
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      // FIX BUG 10: set inMeeting AFTER WebSocket connects, not before
      if (isHost) {
        status = MeetingStatus.inMeeting;
        _notify();
      }

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
      );
    } catch (e) {
      debugPrint('WS error: $e');
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';

      switch (type) {
        case 'waiting_room':
          if (!_isHost) {
            status = MeetingStatus.waiting;
            _notify();
          }
          break;

        case 'admitted':
          status = MeetingStatus.inMeeting;
          onAdmitted?.call();
          _notify();
          break;

        case 'rejected':
          status = MeetingStatus.rejected;
          onRejected?.call();
          _notify();
          break;

        case 'existing_participants':
          final list = (msg['payload'] as List?) ?? [];
          for (final p in list) {
            final mp = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
            if (mp.userId != _myUserId) {
              participants.removeWhere((e) => e.userId == mp.userId);
              participants.add(mp);
              _createOffer(mp.userId);
            }
          }
          _notify();
          break;

        case 'participants_update':
          final list = (msg['payload'] as List?) ?? [];
          // FIX BUG 06: rebuild list from scratch to remove stale/ghost entries
          final incomingIds =
              list.map((p) => p['user_id'] as String? ?? '').toSet();
          participants.removeWhere(
              (e) => e.userId != _myUserId && !incomingIds.contains(e.userId));
          for (final p in list) {
            final mp = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
            if (mp.userId != _myUserId &&
                !participants.any((e) => e.userId == mp.userId)) {
              participants.add(mp);
            }
          }
          _notify();
          break;

        case 'participant_joined':
          final p = msg['payload'];
          if (p != null) {
            final mp = MeetingParticipant.fromMap(Map<String, dynamic>.from(p));
            if (mp.userId != _myUserId) {
              participants.removeWhere((e) => e.userId == mp.userId);
              participants.add(mp);
              _notify();
            }
          }
          break;

        case 'participant_left':
          final payload = msg['payload'];
          final uid =
              payload is Map ? (payload['user_id'] as String? ?? '') : '';
          if (uid.isNotEmpty) {
            _closePeer(uid);
            _notify();
          }
          break;

        case 'waiting_update':
          waitingRoom.clear();
          final list = (msg['payload'] as List?) ?? [];
          for (final w in list)
            waitingRoom.add(WaitingUser.fromMap(Map<String, dynamic>.from(w)));
          _notify();
          break;

        case 'offer':
          final fromId = msg['from_id'] as String? ?? '';
          final sdp = msg['sdp'] as String? ?? '';
          if (fromId.isNotEmpty && sdp.isNotEmpty) _handleOffer(fromId, sdp);
          break;

        case 'answer':
          final fromId = msg['from_id'] as String? ?? '';
          final sdp = msg['sdp'] as String? ?? '';
          if (fromId.isNotEmpty && sdp.isNotEmpty) _handleAnswer(fromId, sdp);
          break;

        case 'ice_candidate':
          final fromId = msg['from_id'] as String? ?? '';
          final cand = msg['candidate'];
          if (fromId.isNotEmpty && cand != null) _handleIce(fromId, cand);
          break;

        case 'hand_raised':
          final payload = msg['payload'];
          if (payload is Map) {
            final uid = payload['user_id'] as String? ?? '';
            for (final p in participants) {
              if (p.userId == uid) {
                p.handRaised = payload['raised'] as bool? ?? false;
                break;
              }
            }
            _notify();
          }
          break;

        case 'chat_message':
          final payload = msg['payload'];
          if (payload is Map) {
            final senderId = payload['user_id'] as String? ?? '';
            // Only add if not our own message (we add it in sendChat already)
            if (senderId != _myUserId) {
              chatMessages.add(MeetingChatMsg(
                userId: senderId,
                userName: payload['user_name'] ?? '',
                content: payload['content'] ?? '',
                isOwn: false,
              ));
              _notify();
            }
          }
          break;

        case 'media_state_update':
          final payload = msg['payload'];
          if (payload is Map) {
            final uid = payload['user_id'] as String? ?? '';
            for (final p in participants) {
              if (p.userId == uid) {
                if (payload['audio_enabled'] != null)
                  p.audioEnabled = payload['audio_enabled'] as bool;
                if (payload['video_enabled'] != null)
                  p.videoEnabled = payload['video_enabled'] as bool;
                break;
              }
            }
            _notify();
          }
          break;

        case 'muted':
          micEnabled = false;
          _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
          _notify();
          break;

        case 'removed':
          status = MeetingStatus.removed;
          onRemoved?.call();
          _notify();
          break;

        case 'meeting_ended':
          status = MeetingStatus.ended;
          onMeetingEnded?.call();
          _notify();
          break;
      }
    } catch (e) {
      debugPrint('WS msg error: $e');
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

  Future<RTCPeerConnection> _getOrCreatePC(String peerId) async {
    if (_peerConnections.containsKey(peerId)) return _peerConnections[peerId]!;

    final pc = await createPeerConnection(_iceServers);
    _peerConnections[peerId] = pc;

    _localStream
        ?.getTracks()
        .forEach((track) => pc.addTrack(track, _localStream!));

    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        final idx = participants.indexWhere((p) => p.userId == peerId);
        if (idx >= 0) {
          if (participants[idx].renderer == null) {
            final renderer = RTCVideoRenderer();
            await renderer.initialize();
            participants[idx].renderer = renderer;
          }
          participants[idx].renderer!.srcObject = stream;
          _notify();
        }
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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _closePeer(peerId);
        _notify();
      }
    };

    return pc;
  }

  Future<void> _createOffer(String peerId) async {
    final pc = await _getOrCreatePC(peerId);
    final offer = await pc.createOffer(
        {'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(offer);
    _send({'type': 'offer', 'target_id': peerId, 'sdp': offer.sdp});
  }

  Future<void> _handleOffer(String fromId, String sdp) async {
    // FIX BUG 07: look up real name from participants list instead of using UUID
    String realName = fromId;
    final existing = participants.where((p) => p.userId == fromId).firstOrNull;
    if (existing != null &&
        existing.userName.isNotEmpty &&
        existing.userName != fromId) {
      realName = existing.userName;
    }

    if (!participants.any((p) => p.userId == fromId)) {
      participants.add(MeetingParticipant(
        userId: fromId,
        userName: realName,
        isHost: false,
      ));
    }
    final pc = await _getOrCreatePC(fromId);
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await pc.createAnswer(
        {'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(answer);
    _send({'type': 'answer', 'target_id': fromId, 'sdp': answer.sdp});
  }

  Future<void> _handleAnswer(String fromId, String sdp) async {
    final pc = _peerConnections[fromId];
    if (pc != null)
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _handleIce(String fromId, dynamic candidate) async {
    final pc = _peerConnections[fromId];
    if (pc != null && candidate is Map) {
      await pc.addCandidate(RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ));
    }
  }

  void _closePeer(String peerId) {
    _peerConnections[peerId]?.close();
    _peerConnections.remove(peerId);
    final idx = participants.indexWhere((p) => p.userId == peerId);
    if (idx >= 0) {
      participants[idx].renderer?.dispose();
      // FIX BUG 08: remove from list after disposing renderer
      participants.removeAt(idx);
    }
  }

  void toggleMic() {
    micEnabled = !micEnabled;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = micEnabled);
    _send({
      'type': 'media_state',
      'audio_enabled': micEnabled,
      'video_enabled': cameraEnabled,
    });
    _notify();
  }

  void toggleCamera() {
    cameraEnabled = !cameraEnabled;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = cameraEnabled);
    _send({
      'type': 'media_state',
      'audio_enabled': micEnabled,
      'video_enabled': cameraEnabled,
    });
    _notify();
  }

  // FIX BUG 24: re-entrancy guard prevents double-tap creating two streams
  Future<void> toggleScreenShare() async {
    if (_togglingScreenShare) return;
    _togglingScreenShare = true;
    try {
      if (screenSharing) {
        _screenStream?.getTracks().forEach((t) => t.stop());
        _screenStream = null;
        screenSharing = false;
        final camTrack = _localStream?.getVideoTracks().firstOrNull;
        if (camTrack != null) {
          for (final pc in _peerConnections.values) {
            final senders = await pc.getSenders();
            for (final s in senders) {
              if (s.track?.kind == 'video') await s.replaceTrack(camTrack);
            }
          }
        }
      } else {
        try {
          _screenStream = await navigator.mediaDevices
              .getDisplayMedia({'video': true, 'audio': false});
          final screenTrack = _screenStream?.getVideoTracks().firstOrNull;
          if (screenTrack != null) {
            screenSharing = true;
            for (final pc in _peerConnections.values) {
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
        } catch (e) {
          debugPrint('Screen share error: $e');
          screenSharing = false;
        }
      }
    } finally {
      _togglingScreenShare = false;
    }
    _notify();
  }

  void toggleHand() {
    handRaised = !handRaised;
    _send({'type': 'raise_hand', 'raised': handRaised});
    _notify();
  }

  void sendChat(String content) {
    if (content.trim().isEmpty) return;
    _send({'type': 'chat', 'content': content.trim()});
    // Add own message immediately — server will NOT echo it back (BUG 09 fix)
    chatMessages.add(MeetingChatMsg(
      userId: _myUserId ?? '',
      userName: _myUserName ?? 'You',
      content: content.trim(),
      isOwn: true,
    ));
    _notify();
  }

  void admitUser(String userId) =>
      _send({'type': 'admit_user', 'user_id': userId});
  void rejectUser(String userId) =>
      _send({'type': 'reject_user', 'user_id': userId});
  void muteUser(String userId) =>
      _send({'type': 'mute_user', 'user_id': userId});
  void removeParticipant(String userId) =>
      _send({'type': 'remove_participant', 'user_id': userId});
  void endMeeting() => _send({'type': 'end_meeting'});

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _channel?.sink.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.getTracks().forEach((t) => t.stop());
    for (final pc in _peerConnections.values) pc.close();
    for (final p in participants) p.renderer?.dispose();
    if (_localRendererInit) localRenderer.dispose();
    super.dispose();
  }
}
