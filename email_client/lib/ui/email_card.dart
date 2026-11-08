import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/email_item.dart';
import '../state/email_client_state.dart';

class EmailCard extends StatelessWidget {
  final EmailItem item;
  final bool isSelected;
  final bool isColumnFocused;
  final ColumnType columnType;
  final VoidCallback onTap;
  final VoidCallback onPreview;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback? onDelete;

  const EmailCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isColumnFocused,
    required this.columnType,
    required this.onTap,
    required this.onPreview,
    required this.onMoveLeft,
    required this.onMoveRight,
    this.onDelete,
  });

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0 && now.day == date.day) {
      return DateFormat('HH:mm').format(date);
    } else if (diff.inDays < 7) {
      return DateFormat('EEE HH:mm').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Selection styling
    Color borderColor = Colors.transparent;
    Color? backgroundColor;

    if (isSelected) {
      if (isColumnFocused) {
        borderColor = colorScheme.primary;
        backgroundColor = colorScheme.primary.withValues(alpha: 0.12);
      } else {
        borderColor = colorScheme.outline.withValues(alpha: 0.4);
        backgroundColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
      }
    } else {
      backgroundColor = colorScheme.surfaceContainer;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: isSelected && isColumnFocused ? 2 : 1,
        ),
        boxShadow: isSelected && isColumnFocused
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onPreview,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Sender & Date
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.fromName.isNotEmpty ? item.fromName : item.fromEmail,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected && isColumnFocused
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(item.date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),

                // From email subtitle (if display name differs)
                if (item.fromName.isNotEmpty && item.fromName != item.fromEmail)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      item.fromEmail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 5),

                // Subject
                Text(
                  item.subject.isNotEmpty ? item.subject : '(no subject)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Bottom row: Badges + Quick Action Buttons
                Row(
                  children: [
                    // Classification / Approved badge
                    _buildBadge(context),

                    const Spacer(),

                    // Quick Action Buttons
                    if (columnType == ColumnType.aiSpam) ...[
                      _ActionButton(
                        icon: Icons.arrow_back,
                        label: 'Inbox',
                        tooltip: 'Move to Inbox (Left Arrow) & Train as Ham',
                        color: Colors.green.shade400,
                        onPressed: onMoveLeft,
                      ),
                      const SizedBox(width: 6),
                      _ActionButton(
                        icon: Icons.arrow_forward,
                        label: 'Spam',
                        tooltip: 'Move to Spam (Right Arrow) & Train as Spam',
                        color: Colors.red.shade400,
                        onPressed: onMoveRight,
                      ),
                    ] else if (columnType == ColumnType.inbox) ...[
                      _ActionButton(
                        icon: Icons.arrow_forward,
                        label: 'Spam',
                        tooltip: 'Move to Spam (Right Arrow)',
                        color: Colors.red.shade400,
                        onPressed: onMoveRight,
                      ),
                    ] else if (columnType == ColumnType.spam) ...[
                      _ActionButton(
                        icon: Icons.arrow_back,
                        label: 'Inbox',
                        tooltip: 'Move to Inbox (Left Arrow)',
                        color: Colors.green.shade400,
                        onPressed: onMoveLeft,
                      ),
                    ],

                    const SizedBox(width: 4),

                    // Detail preview button
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      tooltip: 'View details & body (Enter)',
                      onPressed: onPreview,
                    ),

                    if (onDelete != null) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        tooltip: 'Move to Trash (Delete / Backspace)',
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        onPressed: onDelete,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    if (item.isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 12, color: Colors.cyan),
            SizedBox(width: 3),
            Text(
              'Approved',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.cyan,
              ),
            ),
          ],
        ),
      );
    }

    final cls = item.classification;
    if (cls != null) {
      final isSpam = cls.isSpam;
      final percent = (cls.confidence * 100).toInt();
      final color = isSpam
          ? (cls.confidence >= 0.8 ? Colors.redAccent : Colors.orangeAccent)
          : Colors.green;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSpam ? 'SPAM $percent%' : 'OK $percent%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (cls.category.isNotEmpty && cls.category != 'unknown') ...[
              const SizedBox(width: 4),
              Text(
                '• ${cls.category}',
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

