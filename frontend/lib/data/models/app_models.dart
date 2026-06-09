import 'package:flutter/material.dart';

class UserModel {
  final String id, name, email, role, department, status;
  final String avatarUrl, phone, userRole, bio;
  final DateTime? lastSeen;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.role = '',
    this.department = '',
    this.status = 'offline',
    this.avatarUrl = '',
    this.phone = '',
    this.userRole = 'employee',
    this.bio = '',
    this.lastSeen,
  });

  bool get isAdmin => userRole == 'admin';
  bool get isEmployee => userRole == 'employee';
  bool get isOnline => status == 'online';

  String get lastSeenText {
    if (status == 'online') return 'Online';
    if (lastSeen == null) return 'Offline';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${diff.inDays}d ago';
  }

  Color get statusColor {
    switch (status) {
      case 'online':
        return const Color(0xFF22C55E);
      case 'busy':
        return const Color(0xFFEF4444);
      case 'away':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF6B7280);
    }
  }

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        email: j['email'] ?? '',
        role: j['role'] ?? '',
        department: j['department'] ?? '',
        status: j['status'] ?? 'offline',
        avatarUrl: j['avatar_url'] ?? '',
        phone: j['phone'] ?? '',
        userRole: j['user_role'] ?? 'employee',
        bio: j['bio'] ?? '',
        lastSeen:
            j['last_seen'] != null ? DateTime.tryParse(j['last_seen']) : null,
      );
}

class ChatModel {
  final String id, name, lastMessage, avatarUrl;
  final bool isGroup, isPinned, isMuted;
  final DateTime lastTime;
  final int unreadCount;

  const ChatModel({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastTime,
    this.avatarUrl = '',
    this.isGroup = false,
    this.isPinned = false,
    this.isMuted = false,
    this.unreadCount = 0,
  });

  factory ChatModel.fromJson(Map<String, dynamic> j) => ChatModel(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        isGroup: j['is_group'] ?? false,
        lastMessage: j['last_message'] ?? '',
        avatarUrl: j['avatar_url'] ?? '',
        isPinned: j['is_pinned'] ?? false,
        isMuted: j['is_muted'] ?? false,
        unreadCount: j['unread_count'] ?? 0,
        lastTime: j['last_time'] != null
            ? DateTime.parse(j['last_time'])
            : DateTime.now(),
      );
}

class MessageModel {
  final String id, chatId, senderId, senderName, content, messageType;
  final String fileUrl, fileName, senderAvatarUrl;
  final DateTime createdAt;
  final bool isRead;

  const MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.messageType = 'text',
    this.fileUrl = '',
    this.fileName = '',
    this.senderAvatarUrl = '',
    required this.createdAt,
    this.isRead = false,
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
        id: j['id'] ?? '',
        chatId: j['chat_id'] ?? '',
        senderId: j['sender_id'] ?? '',
        senderName: j['sender_name'] ?? 'Unknown',
        content: j['content'] ?? '',
        messageType: j['message_type'] ?? 'text',
        fileUrl: j['file_url'] ?? '',
        fileName: j['file_name'] ?? '',
        senderAvatarUrl: j['sender_avatar'] ?? '',
        isRead: j['is_read'] ?? false,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'])
            : DateTime.now(),
      );
}

class MeetingModel {
  final String id, title, description, organizerId, organizer, status;
  final String meetingLink, code, inviteLink;
  final DateTime startTime, endTime, createdAt;
  final List<UserModel> participants;

  const MeetingModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.organizerId,
    required this.organizer,
    required this.startTime,
    required this.endTime,
    this.status = 'upcoming',
    this.meetingLink = '',
    this.code = '',
    this.inviteLink = '',
    required this.createdAt,
    this.participants = const [],
  });

  factory MeetingModel.fromJson(Map<String, dynamic> j) => MeetingModel(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        organizerId: j['organizer_id'] ?? '',
        organizer: j['organizer'] ?? '',
        status: j['status'] ?? 'upcoming',
        meetingLink: j['meeting_link'] ?? '',
        code: j['code'] ?? '',
        inviteLink: j['invite_link'] ?? j['meeting_link'] ?? '',
        startTime: j['start_time'] != null
            ? DateTime.parse(j['start_time'])
            : DateTime.now(),
        endTime: j['end_time'] != null
            ? DateTime.parse(j['end_time'])
            : DateTime.now().add(const Duration(hours: 1)),
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'])
            : DateTime.now(),
        participants: (j['participants'] as List?)
                ?.map((p) => UserModel.fromJson(p))
                .toList() ??
            [],
      );

  bool get isUpcoming => status == 'upcoming';
  bool get isOngoing => status == 'ongoing';
  bool get isEnded => status == 'ended';
}

class TaskModel {
  final String id,
      title,
      description,
      assigneeId,
      assigneeName,
      projectName,
      priority,
      status,
      createdBy,
      creatorName;
  final DateTime dueDate, createdAt;
  final bool isMine, iCreated;

  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.assigneeId,
    required this.assigneeName,
    this.projectName = 'General',
    required this.dueDate,
    this.priority = 'medium',
    this.status = 'todo',
    required this.createdAt,
    this.createdBy = '',
    this.creatorName = '',
    this.isMine = false,
    this.iCreated = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> j) => TaskModel(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        assigneeId: j['assignee_id'] ?? '',
        assigneeName: j['assignee_name'] ?? '',
        projectName: j['project_name'] ?? 'General',
        priority: j['priority'] ?? 'medium',
        status: j['status'] ?? 'todo',
        createdBy: j['created_by'] ?? '',
        creatorName: j['creator_name'] ?? '',
        isMine: j['is_mine'] ?? false,
        iCreated: j['i_created'] ?? false,
        dueDate: j['due_date'] != null
            ? DateTime.parse(j['due_date'])
            : DateTime.now().add(const Duration(days: 7)),
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'])
            : DateTime.now(),
      );

  bool get isOverdue =>
      dueDate.isBefore(DateTime.now()) &&
      status != 'done' &&
      status != 'approved';
}

class AttendanceModel {
  final String id, userId, status, location;
  final DateTime date;
  final DateTime? checkIn, checkOut;

  const AttendanceModel({
    required this.id,
    required this.userId,
    required this.date,
    this.status = 'absent',
    this.location = '',
    this.checkIn,
    this.checkOut,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> j) => AttendanceModel(
        id: j['id'] ?? '',
        userId: j['user_id'] ?? '',
        status: j['status'] ?? 'absent',
        location: j['location'] ?? '',
        date: j['date'] != null ? DateTime.parse(j['date']) : DateTime.now(),
        checkIn: j['check_in'] != null ? DateTime.parse(j['check_in']) : null,
        checkOut:
            j['check_out'] != null ? DateTime.parse(j['check_out']) : null,
      );
}

class NotificationModel {
  final String id, userId, title, body, type, actionId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    this.body = '',
    required this.type,
    this.isRead = false,
    this.actionId = '',
    required this.createdAt,
  });

  String? get meetingCode {
    final m = RegExp(r'Code:\s+([A-Z0-9]{4,8})').firstMatch(body);
    return m?.group(1);
  }

  factory NotificationModel.fromJson(Map<String, dynamic> j) =>
      NotificationModel(
        id: j['id'] ?? '',
        userId: j['user_id'] ?? '',
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        type: j['notification_type'] ?? 'system',
        isRead: j['is_read'] ?? false,
        actionId: j['action_id'] ?? '',
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'])
            : DateTime.now(),
      );
}

class ApprovalModel {
  final String id,
      title,
      approvalType,
      requesterId,
      requesterName,
      approverId,
      approverName,
      description,
      status;
  final DateTime createdAt;

  const ApprovalModel({
    required this.id,
    required this.title,
    required this.approvalType,
    required this.requesterId,
    required this.requesterName,
    this.approverId = '',
    this.approverName = '',
    this.description = '',
    this.status = 'pending',
    required this.createdAt,
  });

  factory ApprovalModel.fromJson(Map<String, dynamic> j) => ApprovalModel(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        approvalType: j['approval_type'] ?? '',
        requesterId: j['requester_id'] ?? '',
        requesterName: j['requester_name'] ?? '',
        approverId: j['approver_id'] ?? '',
        approverName: j['approver_name'] ?? '',
        description: j['description'] ?? '',
        status: j['status'] ?? 'pending',
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'])
            : DateTime.now(),
      );
}
