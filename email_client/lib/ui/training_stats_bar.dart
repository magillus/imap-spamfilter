import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/email_client_state.dart';

class TrainingStatsBar extends StatelessWidget {
  const TrainingStatsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final training = state.trainingService;
    final stats = training?.getStats();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Left: Real-time Status / Notification
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (training?.isTraining ?? false) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    state.statusBannerMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Center: Quick Stats Pills
          if (stats != null)
            Flexible(
              flex: 3,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatPill(
                      icon: Icons.verified_user_outlined,
                      label: '${stats.approvedSendersCount} Approved',
                      color: Colors.cyan,
                      tooltip: '${stats.approvedSendersCount} senders & ${stats.approvedDomainsCount} domains in approved.json',
                    ),
                    const SizedBox(width: 6),
                    _StatPill(
                      icon: Icons.shield_outlined,
                      label: '${stats.spamProfileDomainsCount} Spam Domains',
                      color: Colors.redAccent,
                      tooltip: 'Spam repeat offenders learned in spam_profile.json',
                    ),
                    const SizedBox(width: 6),
                    _StatPill(
                      icon: Icons.storage_outlined,
                      label: '${stats.classifiedCount} Classified',
                      color: Colors.amber,
                      tooltip: 'Cached message classifications in classified.json',
                    ),
                    if (stats.pendingChangesCount > 0) ...[
                      const SizedBox(width: 6),
                      _StatPill(
                        icon: Icons.hourglass_top,
                        label: '${stats.pendingChangesCount} Batched',
                        color: Colors.orangeAccent,
                        tooltip: '${stats.pendingChangesCount} changes batched. Retrains after 45s idle or click Retrain Now.',
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(width: 8),

          // Right: Manual Retrain Button & Shortcuts hint
          Tooltip(
            message: stats != null && stats.pendingChangesCount > 0
                ? 'Immediately flush and run imap-spam-filter learn for ${stats.pendingChangesCount} batched changes'
                : 'Run imap-spam-filter learn now to recompute spam profile from folders',
            child: stats != null && stats.pendingChangesCount > 0
                ? FilledButton.tonalIcon(
                    icon: (training?.isTraining ?? false)
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.psychology, size: 16),
                    label: Text(
                      (training?.isTraining ?? false)
                          ? 'Learning...'
                          : 'Retrain (${stats.pendingChangesCount})',
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: (training?.isTraining ?? false)
                        ? null
                        : () async {
                            final msg = await state.triggerManualRetrain();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                  )
                : OutlinedButton.icon(
                    icon: (training?.isTraining ?? false)
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.psychology, size: 16),
                    label: const Text('Retrain Profile'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: (training?.isTraining ?? false)
                        ? null
                        : () async {
                            final msg = await state.triggerManualRetrain();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                  ),
          ),

          const SizedBox(width: 12),

          // Keyboard Legend Popover / Info
          IconButton(
            icon: const Icon(Icons.keyboard_outlined, size: 18),
            tooltip: 'Keyboard Shortcuts:\n'
                '• ↑ / ↓ : Navigate emails in column\n'
                '• ← : Move to Inbox (train Ham)\n'
                '• → : Move to Spam (train Spam)\n'
                '• Del / Backspace : Move to Trash\n'
                '• 1 / 2 / 3 : Switch column focus\n'
                '• Enter / Space : Open details & body\n'
                '• R : Refresh current column\n'
                '• Shift + R : Refresh all columns',
            visualDensity: VisualDensity.compact,
            onPressed: () => _showShortcutsDialog(context),
          ),
        ],
      ),
    );
  }

  void _showShortcutsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.keyboard),
            SizedBox(width: 8),
            Text('Keyboard Shortcuts'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShortcutRow(keys: '↑ / ↓', desc: 'Navigate up and down between emails in active column'),
            _ShortcutRow(keys: '← (Left)', desc: 'From AI-Spam: Move to Inbox (assigns Ham, adds to approved.json)'),
            _ShortcutRow(keys: '→ (Right)', desc: 'From AI-Spam: Move to Spam (assigns Spam, trains spam profile)'),
            _ShortcutRow(keys: 'Del / Backspace', desc: 'Move email to Trash folder (INBOX.Trash)'),
            _ShortcutRow(keys: '1 / 2 / 3', desc: 'Focus Inbox (1), AI-Spam (2), or Spam (3) column'),
            _ShortcutRow(keys: 'Enter / Space', desc: 'Open full email details, body preview & AI breakdown'),
            _ShortcutRow(keys: 'R', desc: 'Refresh emails in active column'),
            _ShortcutRow(keys: 'Shift + R', desc: 'Refresh all three columns'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String desc;

  const _ShortcutRow({required this.keys, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4)),
            ),
            child: Text(
              keys,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
