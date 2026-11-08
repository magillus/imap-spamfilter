import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/email_item.dart';
import '../state/email_client_state.dart';

class ColumnRecheckDialog extends StatelessWidget {
  final ColumnRecheckSummary summary;

  const ColumnRecheckDialog({super.key, required this.summary});

  String get _columnTitle {
    switch (summary.column) {
      case ColumnType.inbox:
        return 'Inbox';
      case ColumnType.aiSpam:
        return 'AI-Spam';
      case ColumnType.spam:
        return 'Spam';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = context.read<EmailClientState>();

    final hasSpamInInbox = summary.column == ColumnType.inbox && summary.spamMatches.isNotEmpty;
    final hasApprovedInSpam = (summary.column == ColumnType.aiSpam || summary.column == ColumnType.spam) &&
        summary.approvedMatches.isNotEmpty;
    final hasConfirmedSpamInAi = summary.column == ColumnType.aiSpam && summary.spamMatches.isNotEmpty;

    final displayItems = <EmailItem>[
      ...summary.spamMatches,
      ...summary.approvedMatches,
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.rule_folder_outlined, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recheck: $_columnTitle with Retrained Profile',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${summary.totalScanned} emails evaluated • ${summary.statusChangedCount} classification status update(s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Summary Stat Pills
              Row(
                children: [
                  _StatPill(
                    label: 'Spam Profile Matches',
                    count: summary.spamMatches.length,
                    color: Colors.redAccent,
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    label: 'Approved / Whitelisted',
                    count: summary.approvedMatches.length,
                    color: Colors.cyan,
                    icon: Icons.verified,
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    label: 'Clean',
                    count: summary.cleanEmails.length,
                    color: Colors.green,
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Items Section Title
              Row(
                children: [
                  Text(
                    displayItems.isNotEmpty
                        ? 'Flagged or Updated Messages (${displayItems.length})'
                        : 'All Messages Clean',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (displayItems.isNotEmpty)
                    Text(
                      'Showing matches against profile rules',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Items list preview
              Expanded(
                child: displayItems.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.done_all, color: Colors.green.shade400, size: 40),
                            const SizedBox(height: 10),
                            Text(
                              'All ${summary.totalScanned} emails in $_columnTitle align with the retrained profile.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No spam matches or misplaced approved messages detected.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: ListView.separated(
                          itemCount: displayItems.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                          ),
                          itemBuilder: (context, idx) {
                            final item = displayItems[idx];
                            final isSpam = item.classification?.isSpam ?? false;
                            final hits = item.classification?.profileHits ?? [];

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.isApproved
                                              ? Colors.cyan.withValues(alpha: 0.15)
                                              : isSpam
                                                  ? Colors.redAccent.withValues(alpha: 0.15)
                                                  : Colors.green.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: item.isApproved
                                                ? Colors.cyan.withValues(alpha: 0.5)
                                                : isSpam
                                                    ? Colors.redAccent.withValues(alpha: 0.5)
                                                    : Colors.green.withValues(alpha: 0.5),
                                          ),
                                        ),
                                        child: Text(
                                          item.isApproved
                                              ? 'APPROVED'
                                              : isSpam
                                                  ? 'SPAM MATCH'
                                                  : 'CLEAN',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: item.isApproved
                                                ? Colors.cyan
                                                : isSpam
                                                    ? Colors.redAccent
                                                    : Colors.green,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.fromName.isNotEmpty ? '${item.fromName} <${item.fromEmail}>' : item.fromEmail,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (item.date != null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat('MMM d HH:mm').format(item.date!),
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subject.isNotEmpty ? item.subject : '(no subject)',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (hits.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    ...hits.map(
                                      (hit) => Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('• ', style: TextStyle(color: Colors.purpleAccent, fontSize: 11)),
                                            Expanded(
                                              child: Text(
                                                hit,
                                                style: const TextStyle(color: Colors.purpleAccent, fontSize: 11),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasSpamInInbox) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.drive_file_move_outlined, size: 16),
                      label: Text('Move ${summary.spamMatches.length} to AI-Spam'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange.shade600),
                      onPressed: () {
                        state.moveMultipleEmails(
                          summary.spamMatches,
                          from: ColumnType.inbox,
                          to: ColumnType.aiSpam,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: Text('Move ${summary.spamMatches.length} to Spam'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () {
                        state.moveMultipleEmails(
                          summary.spamMatches,
                          from: ColumnType.inbox,
                          to: ColumnType.spam,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],

                  if (hasApprovedInSpam) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.inbox, size: 16),
                      label: Text('Move ${summary.approvedMatches.length} Approved to Inbox'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                      onPressed: () {
                        state.moveMultipleEmails(
                          summary.approvedMatches,
                          from: summary.column,
                          to: ColumnType.inbox,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],

                  if (hasConfirmedSpamInAi) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: Text('Move ${summary.spamMatches.length} Confirmed to Spam'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () {
                        state.moveMultipleEmails(
                          summary.spamMatches,
                          from: ColumnType.aiSpam,
                          to: ColumnType.spam,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],

                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(displayItems.isEmpty ? 'Close' : 'Dismiss (Keep As Is)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatPill({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

