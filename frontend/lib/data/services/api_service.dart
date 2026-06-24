import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/app_models.dart';

class ApiService {
  static const _base = AppConstants.apiUrl;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String _parseError(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map) {
        return body['error'] ?? body['message'] ?? 'Error ${r.statusCode}';
      }
    } catch (_) {}
    return 'Error ${r.statusCode}';
  }

  static Future<dynamic> _get(String path) async {
    final r = await http
        .get(Uri.parse('$_base$path'), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception(_parseError(r));
    return jsonDecode(r.body);
  }

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$_base$path'),
            headers: await _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception(_parseError(r));
    return jsonDecode(r.body);
  }

  static Future<void> _patch(String path, Map<String, dynamic> body) async {
    final r = await http
        .patch(Uri.parse('$_base$path'),
            headers: await _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception(_parseError(r));
  }

  static Future<void> _delete(String path) async {
    final headers = await _headers();
    final r = await http
        .delete(Uri.parse('$_base$path'), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw Exception(_parseError(r));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String email, String password) =>
      _post('/auth/login', {'email': email, 'password': password});

  static Future<Map<String, dynamic>> register(
          String name, String email, String password, String role, String dept,
          {String userRole = 'employee'}) =>
      _post('/auth/register', {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'department': dept,
        'user_role': userRole,
      });

  static Future<UserModel> getMe() async {
    final d = await _get('/auth/me');
    return UserModel.fromJson(d);
  }

  static Future<void> logout() async {
    await _post('/auth/logout', {}).catchError((_) => <String, dynamic>{});
    await clearToken();
  }

  // ── Users ─────────────────────────────────────────────────────────────────
  static Future<List<UserModel>> getUsers() async {
    final list = await _get('/users') as List;
    return list.map((j) => UserModel.fromJson(j)).toList();
  }

  // ── Chats ─────────────────────────────────────────────────────────────────
  static Future<List<ChatModel>> getChats() async {
    final list = await _get('/chats') as List;
    return list.map((j) => ChatModel.fromJson(j)).toList();
  }

  static Future<String> createDirectChat(String otherUserId) async {
    final d = await _post('/chats', {
      'is_group': false,
      'member_ids': [otherUserId]
    });
    return d['id'] as String;
  }

  static Future<String> createGroupChat(
      String name, List<String> memberIds) async {
    final d = await _post(
        '/chats', {'name': name, 'is_group': true, 'member_ids': memberIds});
    return d['id'] as String;
  }

  static Future<List<MessageModel>> getMessages(String chatId) async {
    final list = await _get('/chats/$chatId/messages') as List;
    return list.map((j) => MessageModel.fromJson(j)).toList();
  }

  static Future<MessageModel> sendMessage(String chatId, String content,
      {String type = 'text', String? fileUrl, String? fileName}) async {
    final d = await _post('/chats/$chatId/messages', {
      'chat_id': chatId,
      'content': content,
      'message_type': type,
      if (fileUrl != null && fileUrl.isNotEmpty) 'file_url': fileUrl,
      if (fileName != null && fileName.isNotEmpty) 'file_name': fileName,
    });
    return MessageModel.fromJson(d);
  }

  static Future<Map<String, dynamic>> uploadMedia(
      String name, Uint8List bytes) async {
    final token = await getToken();
    final request = http.MultipartRequest('POST', Uri.parse('$_base/upload'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) throw Exception('Upload failed: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<void> markChatRead(String chatId) =>
      _patch('/chats/$chatId/read', {});
  static Future<void> deleteChat(String chatId) => _delete('/chats/$chatId');

  static Future<String> aiChat(String userId, String message) async {
    final d = await _post('/chat/ai', {'user_id': userId, 'message': message});
    return d['reply'] ?? '';
  }

  // ── Meetings ──────────────────────────────────────────────────────────────
  static Future<List<MeetingModel>> getMeetings() async {
    final list = await _get('/meetings') as List;
    return list.map((j) => MeetingModel.fromJson(j)).toList();
  }

  static Future<MeetingModel> createMeeting(Map<String, dynamic> body) async {
    final d = await _post('/meetings', body);
    return MeetingModel.fromJson(d);
  }

  static Future<MeetingModel> getMeetingByCode(String code) async {
    final token = await getToken();
    if (token == null) throw Exception('Not logged in');
    final d = await _get('/meetingcode/${code.toUpperCase().trim()}');
    return MeetingModel.fromJson(d as Map<String, dynamic>);
  }

  static Future<void> updateMeetingStatus(String id, String status) =>
      _patch('/meetings/$id/status', {'status': status});

  static Future<void> deleteMeeting(String id) => _delete('/meetings/$id');

  static Future<List<Map<String, dynamic>>> getMeetingParticipants(
      String meetingId) async {
    try {
      final list = await _get('/meetings/$meetingId/participants') as List;
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // FIX BUG 13: use correct DELETE path matching backend route
  static Future<void> removeParticipant(String meetingId, String userId) async {
    await _delete('/meetings/$meetingId/participants/$userId');
  }

  static Future<void> inviteToMeeting(
      String meetingId, List<String> userIds) async {
    try {
      await _post('/meetings/$meetingId/invite', {'user_ids': userIds});
    } catch (_) {}
  }

  static Future<void> requestMeeting(String meetingId,
      {String message = ''}) async {
    try {
      await _post('/meetings/$meetingId/request', {'message': message});
    } catch (_) {}
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────
  static Future<List<TaskModel>> getTasks({String filter = ''}) async {
    final path = filter.isNotEmpty ? '/tasks?filter=$filter' : '/tasks';
    final list = await _get(path) as List;
    return list.map((j) => TaskModel.fromJson(j)).toList();
  }

  // FIX BUG 15: return created task so caller gets server-assigned ID and defaults
  static Future<Map<String, dynamic>> createTask(Map<String, dynamic> body) =>
      _post('/tasks', body);

  static Future<void> updateTaskStatus(String id, String status) =>
      _patch('/tasks/$id/status', {'status': status});

  // ── Attendance ────────────────────────────────────────────────────────────
  static Future<List<AttendanceModel>> getAttendance() async {
    final list = await _get('/attendance') as List;
    return list.map((j) => AttendanceModel.fromJson(j)).toList();
  }

  static Future<AttendanceModel> checkIn(String location) async {
    final d = await _post('/attendance/checkin', {'location': location});
    return AttendanceModel.fromJson(d);
  }

  // FIX BUG 16: return attendance record so UI gets server-side checkout timestamp
  static Future<AttendanceModel> checkOut() async {
    final d = await _post('/attendance/checkout', {});
    return AttendanceModel.fromJson(d);
  }

  // ── Notifications ─────────────────────────────────────────────────────────
  static Future<List<NotificationModel>> getNotifications() async {
    final list = await _get('/notifications') as List;
    return list.map((j) => NotificationModel.fromJson(j)).toList();
  }

  static Future<void> markNotificationRead(String id) =>
      _patch('/notifications/$id/read', {});

  static Future<void> markAllNotificationsRead() =>
      _post('/notifications/read-all', {});

  // ── Approvals ─────────────────────────────────────────────────────────────
  static Future<List<ApprovalModel>> getApprovals() async {
    final list = await _get('/approvals') as List;
    return list.map((j) => ApprovalModel.fromJson(j)).toList();
  }

  static Future<Map<String, dynamic>> createApproval(
      Map<String, dynamic> body) async {
    try {
      return await _post('/approvals', body);
    } catch (e) {
      throw Exception('Failed to create approval: $e');
    }
  }

  // FIX BUG 14: removed useless PUT fallback — only PATCH route exists
  static Future<void> updateApprovalStatus(String id, String status) async {
    await _patch('/approvals/$id/status', {'status': status});
  }

  // ── Files ─────────────────────────────────────────────────────────────────
  static Future<List<dynamic>> getFiles() async {
    final list = await _get('/files') as List;
    return list;
  }

  static Future<Map<String, dynamic>> uploadFile(
      String name, String fileType, int size,
      {String url = ''}) async {
    return await _post('/files', {
      'name': name,
      'file_type': fileType,
      'size': size,
      if (url.isNotEmpty) 'url': url,
    });
  }

  static Future<void> deleteFile(String id) => _delete('/files/$id');
}
