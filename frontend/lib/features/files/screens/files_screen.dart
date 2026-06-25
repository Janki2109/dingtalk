import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/auth_provider.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _uploading = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getFiles();
      if (mounted) {
        setState(() {
          _files = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _files = []; _loading = false; });
    }
  }

  Future<void> _uploadFile() async {
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        int successCount = 0;
        for (final file in result.files) {
          try {
            if (file.bytes == null) continue;

            // Step 1: upload actual bytes to server → get real URL
            final uploadResult = await ApiService.uploadMedia(file.name, file.bytes!);
            final serverUrl = uploadResult['url'] as String? ?? '';

            // Step 2: save metadata + real URL to files table (persists in DB)
            final saved = await ApiService.uploadFile(
              file.name,
              file.extension ?? 'file',
              file.size,
              url: serverUrl,
            );
            if (mounted) setState(() => _files.insert(0, Map<String, dynamic>.from(saved)));
            successCount++;
          } catch (e) {
            debugPrint('Upload error: $e');
          }
        }
        if (mounted && successCount > 0) {
          _snack(
            successCount == 1
                ? '✅ "${result.files.first.name}" saved!'
                : '✅ $successCount files saved!',
            AppColors.online,
          );
        }
      }
    } catch (_) {
      if (mounted) _snack('Could not open file picker', AppColors.busy);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    try {
      await ApiService.deleteFile(file['id'].toString());
      if (mounted) {
        setState(() => _files.removeWhere((f) => f['id'] == file['id']));
        _snack('File deleted', AppColors.busy);
      }
    } catch (_) {
      if (mounted) _snack('Could not delete file', AppColors.busy);
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

  int get _totalBytes =>
      _files.fold(0, (sum, f) => sum + ((f['size_bytes'] as num?)?.toInt() ?? 0));

  List<Map<String, dynamic>> get _filtered => _files
      .where((f) => (f['name'] as String? ?? '')
          .toLowerCase()
          .contains(_search.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AuthProvider>().themeColor;
    final totalMB = _totalBytes / (1024 * 1024);
    final usedGB = totalMB / 1024;
    final percent = (usedGB / 5.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Files', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
          IconButton(
            icon: _uploading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file_outlined),
            tooltip: 'Upload File',
            onPressed: _uploading ? null : _uploadFile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              // ── Storage Card ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [themeColor, themeColor.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.cloud_outlined, color: Colors.white, size: 26),
                      const SizedBox(width: 10),
                      const Text('File Storage',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                          totalMB < 1
                              ? '${_totalBytes ~/ 1024} KB / 5 GB'
                              : '${totalMB.toStringAsFixed(1)} MB / 5 GB',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percent == 0 ? 0.002 : percent,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.folder_outlined, color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text('${_files.length} file${_files.length != 1 ? 's' : ''} — permanently saved',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const Spacer(),
                      Text(percent == 0 ? 'Empty' : '${(percent * 100).toStringAsFixed(2)}% used',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                ),
              ),

              // ── Upload Button ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: _uploading ? null : _uploadFile,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: themeColor.withValues(alpha: 0.3), width: 1.5)),
                    child: Column(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: _uploading
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: CircularProgressIndicator(strokeWidth: 2, color: themeColor))
                            : Icon(Icons.cloud_upload_outlined, color: themeColor, size: 28),
                      ),
                      const SizedBox(height: 12),
                      Text('Tap to Upload Files',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: themeColor)),
                      const SizedBox(height: 4),
                      const Text('PDF, images, docs, videos — any type',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      const Text('Files saved to server — available after logout & refresh',
                          style: TextStyle(fontSize: 11, color: AppColors.online, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Search ───────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search files...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Files List ───────────────────────────────────────────────────
              if (_filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Icon(Icons.upload_file, size: 64, color: AppColors.textMuted.withValues(alpha: 0.25)),
                    const SizedBox(height: 16),
                    Text(_search.isNotEmpty ? 'No files match "$_search"' : 'No files yet',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    const Text('Tap upload to add files.\nFiles are saved permanently on the server.',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                        textAlign: TextAlign.center),
                  ]),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('Your Files', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('${_filtered.length}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: themeColor)),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                ..._filtered.map((f) => _FileCard(
                      file: f,
                      themeColor: themeColor,
                      onDelete: () => _deleteFile(f),
                    )),
              ],

              const SizedBox(height: 90),
            ]),
    );
  }
}

// ── File Card ──────────────────────────────────────────────────────────────────
class _FileCard extends StatelessWidget {
  final Map<String, dynamic> file;
  final Color themeColor;
  final VoidCallback onDelete;

  const _FileCard({required this.file, required this.themeColor, required this.onDelete});

  String get _type => (file['file_type'] as String? ?? '').toLowerCase();
  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'avif', 'bmp'].contains(_type);

  Color get _typeColor {
    switch (_type) {
      case 'pdf': return const Color(0xFFEF4444);
      case 'doc': case 'docx': return const Color(0xFF1A73E8);
      case 'xls': case 'xlsx': return const Color(0xFF22C55E);
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'avif':
        return const Color(0xFF7C4DFF);
      case 'mp4': case 'mov': return const Color(0xFFFF6B35);
      case 'zip': case 'rar': return const Color(0xFFF59E0B);
      case 'mp3': case 'wav': return const Color(0xFF00BCD4);
      default: return const Color(0xFF607D8B);
    }
  }

  IconData get _typeIcon {
    switch (_type) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'avif':
        return Icons.image;
      case 'mp4': case 'mov': return Icons.video_file;
      case 'zip': case 'rar': return Icons.folder_zip;
      case 'mp3': case 'wav': return Icons.audio_file;
      default: return Icons.insert_drive_file;
    }
  }

  // FIX BUG #63: use tryParse instead of parse+catch — no exceptions for control flow
  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _openFile(BuildContext context) async {
    final rawUrl = file['url'] as String? ?? '';
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('File not available for download'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    final fullUrl = rawUrl.startsWith('http') ? rawUrl : '${AppConstants.serverUrl}$rawUrl';
    final uri = Uri.parse(fullUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = file['size_str'] as String? ?? '';
    final upAt = _formatDate(file['uploaded_at'] as String? ?? '');
    final name = file['name'] as String? ?? '';
    final rawUrl = file['url'] as String? ?? '';
    final hasUrl = rawUrl.isNotEmpty;
    final fullUrl = hasUrl
        ? (rawUrl.startsWith('http') ? rawUrl : '${AppConstants.serverUrl}$rawUrl')
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Image thumbnail (for image files with a real URL) ──────────────
        if (_isImage && hasUrl)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: GestureDetector(
              onTap: () => _openFile(context),
              child: CachedNetworkImage(
                imageUrl: fullUrl,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 160,
                  color: _typeColor.withValues(alpha: 0.05),
                  child: Center(child: Icon(Icons.image, color: _typeColor, size: 40)),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 60,
                  color: _typeColor.withValues(alpha: 0.05),
                  child: Center(child: Icon(Icons.broken_image, color: _typeColor, size: 28)),
                ),
              ),
            ),
          ),

        // ── File info row ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            if (!(_isImage && hasUrl))
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                    color: _typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(_typeIcon, color: _typeColor, size: 24),
              )
            else
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: _typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.image, color: _typeColor, size: 20),
              ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('$sizeStr · $upAt',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              if (hasUrl)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(Icons.check_circle, size: 10, color: AppColors.online),
                    SizedBox(width: 4),
                    Text('Saved on server', style: TextStyle(fontSize: 10, color: AppColors.online, fontWeight: FontWeight.w500)),
                  ]),
                ),
            ])),
            const SizedBox(width: 8),
            // Download / open button
            if (hasUrl)
              GestureDetector(
                onTap: () => _openFile(context),
                child: Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.open_in_new, color: AppColors.primary, size: 17),
                ),
              ),
            // Delete button
            GestureDetector(
              onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Delete File', style: TextStyle(fontWeight: FontWeight.w700)),
                        content: Text('Delete "$name"?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () { Navigator.pop(context); onDelete(); },
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.busy),
                            child: const Text('Delete'),
                          ),
                        ],
                      )),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppColors.busy.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: AppColors.busy, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
