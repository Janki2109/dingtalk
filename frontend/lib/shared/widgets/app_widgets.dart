import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

// ── User Avatar ───────────────────────────────────────────────────────────────
class UserAvatar extends StatelessWidget {
  final String name;
  final String? status;
  final double size;
  final Color? color;
  final String? avatarUrl;

  const UserAvatar({super.key, required this.name, this.status, this.size = 40, this.color, this.avatarUrl});

  Color _bg() {
    if (color != null) return color!;
    final colors = [AppColors.primary, AppColors.purple, AppColors.accent, AppColors.orange, const Color(0xFFE91E63), const Color(0xFF009688)];
    return colors[name.hashCode.abs() % colors.length];
  }

  Color _statusColor() {
    switch (status) {
      case 'online': return AppColors.online;
      case 'away':   return AppColors.away;
      case 'busy':   return AppColors.busy;
      default:       return AppColors.offline;
    }
  }

  Widget _buildPhoto() {
    final url = avatarUrl ?? '';
    if (url.isEmpty) return _initials();

    // base64 stored locally (local:base64data)
    if (url.startsWith('local:')) {
      try {
        final bytes = base64Decode(url.substring(6));
        return ClipOval(
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {
        return _initials();
      }
    }

    // Remote URL (/uploads/... or https://...)
    final fullUrl = url.startsWith('http') ? url : '${AppConstants.serverUrl}$url';
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initials(),
        placeholder: (_, __) => _initials(),
      ),
    );
  }

  Widget _initials() => Center(
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        width: size, height: size,
        decoration: BoxDecoration(color: _bg(), shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: _bg().withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))]),
        child: _buildPhoto(),
      ),
      if (status != null)
        Positioned(right: 0, bottom: 0, child: Container(
          width: size * 0.3, height: size * 0.3,
          decoration: BoxDecoration(color: _statusColor(), shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2)),
        )),
    ]);
  }
}

// ── Group Avatar ──────────────────────────────────────────────────────────────
class GroupAvatar extends StatelessWidget {
  final double size;
  const GroupAvatar({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: const BoxDecoration(gradient: AppColors.primaryGrad, shape: BoxShape.circle),
    child: Icon(Icons.group, color: Colors.white, size: size * 0.5),
  );
}

// ── AI Avatar ─────────────────────────────────────────────────────────────────
class AIAvatar extends StatelessWidget {
  final double size;
  const AIAvatar({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: const BoxDecoration(gradient: AppColors.purpleGrad, shape: BoxShape.circle),
    child: Icon(Icons.auto_awesome, color: Colors.white, size: size * 0.45),
  );
}

// ── Unread Badge ──────────────────────────────────────────────────────────────
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge({super.key, required this.count});
  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
      child: Text(count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────
class AppChip extends StatelessWidget {
  final String label;
  final Color color;
  const AppChip({super.key, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

// ── Section Header ────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const Spacer(),
      if (action != null) GestureDetector(onTap: onAction,
        child: Text(action!, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );
}

// ── Search Bar ────────────────────────────────────────────────────────────────
class AppSearchBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  const AppSearchBar({super.key, required this.hint, this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: AppColors.surfaceVar, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
        hintText: hint, border: InputBorder.none, enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none, filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}

// ── Loading Overlay ───────────────────────────────────────────────────────────
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black38,
    child: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 64, color: AppColors.textMuted.withOpacity(0.4)),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.textMuted), textAlign: TextAlign.center),
      if (actionLabel != null) ...[
        const SizedBox(height: 20),
        ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ]),
  );
}

// ── Time helpers ──────────────────────────────────────────────────────────────
String formatTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  if (diff.inDays == 1) return 'Yesterday';
  return '${dt.month}/${dt.day}';
}

String formatHM(DateTime? dt) {
  if (dt == null) return '--:--';
  return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

String formatDate(DateTime dt) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[dt.month-1]} ${dt.day}, ${dt.year}';
}
