import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/email_item.dart';
import '../state/email_client_state.dart';

class SpamBatchOption {
  final String title;
  final String subtitle;
  final List<EmailItem> emails;
  final IconData icon;

  SpamBatchOption({
    required this.title,
    required this.subtitle,
    required this.emails,
    required this.icon,
  });
}

class BatchSpamDialog extends StatefulWidget {
  final EmailItem item;
  final ColumnType fromColumn;
  final List<EmailItem> bySender;
  final List<EmailItem> bySubject;
  final List<EmailItem> combined;

  const BatchSpamDialog({
    super.key,
    required this.item,
    required this.fromColumn,
    required this.bySender,
    required this.bySubject,
    required this.combined,
  });

  @override
  State<BatchSpamDialog> createState() => _BatchSpamDialogState();
}

class _BatchSpamDialogState extends State<BatchSpamDialog> {
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  late final List<SpamBatchOption> _options;

  @override
  void initState() {
    super.initState();

    final opts = <SpamBatchOption>[];

    // Option 1: By Sender Email
    if (widget.bySender.isNotEmpty) {
      final senderEmails = [widget.item, ...widget.bySender];
      opts.add(
        SpamBatchOption(
          title: 'All from sender (${senderEmails.length} emails)',
          subtitle: widget.item.fromEmail,
          emails: senderEmails,
          icon: Icons.alternate_email,
        ),
      );
    }

    // Option 2: By Subject Line / Title
    if (widget.bySubject.isNotEmpty) {
      final subjectEmails = [widget.item, ...widget.bySubject];
      opts.add(
        SpamBatchOption(
          title: 'All with same subject (${subjectEmails.length} emails)',
          subtitle: '"${EmailItem.cleanSubject(widget.item.subject)}"',
          emails: subjectEmails,
          icon: Icons.subject,
        ),
      );
    }

    // Option 3: Combined (if both sender & subject options exist and sets differ)
    if (widget.bySender.isNotEmpty &&
        widget.bySubject.isNotEmpty &&
        widget.combined.isNotEmpty) {
      final allMatching = [widget.item, ...widget.combined];
      if (allMatching.length > (widget.bySender.length + 1) &&
          allMatching.length > (widget.bySubject.length + 1)) {
        opts.add(
          SpamBatchOption(
            title: 'All matching sender or subject (${allMatching.length} emails)',
            subtitle: 'Combined sender & subject matches',
            emails: allMatching,
            icon: Icons.dynamic_feed,
          ),
        );
      }
    }

    _options = opts;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event, EmailClientState state) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_selectedIndex > 0) {
        setState(() => _selectedIndex--);
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_selectedIndex < _options.length - 1) {
        setState(() => _selectedIndex++);
      }
    } else if (key == LogicalKeyboardKey.enter) {
      // Preselected: Move All in chosen subset
      _executeMoveAll(state);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // Right arrow: Move single
      _executeMoveSingle(state);
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.arrowLeft) {
      Navigator.of(context).pop();
    }
  }

  void _executeMoveAll(EmailClientState state) {
    if (_options.isEmpty) {
      _executeMoveSingle(state);
      return;
    }
    final selectedOption = _options[_selectedIndex];
    state.moveMultipleEmails(
      selectedOption.emails,
      from: widget.fromColumn,
      to: ColumnType.spam,
    );
    Navigator.of(context).pop();
  }

  void _executeMoveSingle(EmailClientState state) {
    state.moveEmail(
      widget.item,
      from: widget.fromColumn,
      to: ColumnType.spam,
    );
    Navigator.of(context).pop();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('MMM d, HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentOption = _options.isNotEmpty ? _options[_selectedIndex] : null;

    final sourceFolderLabel = switch (widget.fromColumn) {
      ColumnType.inbox => 'Inbox',
      ColumnType.aiSpam => 'AI-Spam',
      ColumnType.spam => 'Spam',
    };

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, state),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.report_outlined, color: Colors.redAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Multiple Matching Emails Found in $sourceFolderLabel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Would you like to move all matching emails to Spam or only this one?',
                            style: TextStyle(
                              fontSize: 12,
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

                // Current Email Preview Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mail_outline, size: 18, color: Colors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.subject,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.item.senderDisplay,
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Subsets Selector
                Text(
                  'Select Batch Subset (Use ↑ / ↓ to change):',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                ...List.generate(_options.length, (index) {
                  final opt = _options[index];
                  final isSelected = _selectedIndex == index;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.12)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? colorScheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      onTap: () => setState(() => _selectedIndex = index),
                      leading: Icon(
                        opt.icon,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        opt.title,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        opt.subtitle,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Selected (Enter)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              '${opt.emails.length} emails',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // Preview of emails in selected subset
                if (currentOption != null) ...[
                  Text(
                    'Emails included in this batch (${currentOption.emails.length}):',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: ListView.separated(
                        itemCount: currentOption.emails.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        itemBuilder: (context, idx) {
                          final e = currentOption.emails[idx];
                          final isCurrent = e.uid == widget.item.uid;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  isCurrent ? Icons.arrow_right_alt : Icons.email_outlined,
                                  size: 14,
                                  color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.subject,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(e.date),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  children: [
                    // Shortcuts Hint
                    Expanded(
                      child: Text(
                        '[Enter] Move All • [→] Move Single • [↑/↓] Change Subset • [Esc] Cancel',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),

                    // Cancel
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),

                    const SizedBox(width: 8),

                    // Move Single (Right Arrow)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: const Text('Move Single (→)'),
                      onPressed: () => _executeMoveSingle(state),
                    ),

                    const SizedBox(width: 8),

                    // Move All (Enter) - Preselected
                    FilledButton.icon(
                      icon: const Icon(Icons.done_all, size: 16),
                      label: Text(
                        currentOption != null
                            ? 'Move All (${currentOption.emails.length}) [Enter]'
                            : 'Move All [Enter]',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      ),
                      onPressed: () => _executeMoveAll(state),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
