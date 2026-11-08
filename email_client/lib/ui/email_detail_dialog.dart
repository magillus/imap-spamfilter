import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/email_item.dart';
import '../state/email_client_state.dart';
import 'batch_spam_dialog.dart';

class EmailDetailDialog extends StatefulWidget {
  final EmailItem item;

  const EmailDetailDialog({super.key, required this.item});

  @override
  State<EmailDetailDialog> createState() => _EmailDetailDialogState();
}

class _EmailDetailDialogState extends State<EmailDetailDialog> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cls = widget.item.classification;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final key = event.logicalKey;
        final currentCol = _findColumnForMailbox(state, widget.item.mailboxPath);

        if (key == LogicalKeyboardKey.arrowLeft) {
          state.moveEmail(widget.item, from: currentCol, to: ColumnType.inbox);
          Navigator.of(context).pop();
        } else if (key == LogicalKeyboardKey.arrowRight) {
          _moveToSpamOrPrompt(context, state);
        } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
          state.deleteEmail(widget.item, from: currentCol);
          Navigator.of(context).pop();
        } else if (key == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        }
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: colorScheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Row: Subject & Close
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.subject.isNotEmpty ? widget.item.subject : '(no subject)',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Metadata card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetaRow(label: 'From', value: widget.item.senderDisplay),
                      if (widget.item.date != null)
                        _MetaRow(
                          label: 'Date',
                          value: DateFormat('yyyy-MM-dd HH:mm:ss (EEEE)').format(widget.item.date!),
                        ),
                      _MetaRow(label: 'Folder', value: widget.item.mailboxPath),
                      _MetaRow(label: 'Ref', value: widget.item.ref),
                      if (widget.item.messageId.isNotEmpty)
                        _MetaRow(label: 'Message-ID', value: widget.item.messageId),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // AI Spam Breakdown Section
                if (cls != null || widget.item.isApproved) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.item.isApproved
                          ? Colors.cyan.withValues(alpha: 0.08)
                          : (cls?.isSpam ?? false)
                              ? Colors.red.withValues(alpha: 0.08)
                              : Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.item.isApproved
                            ? Colors.cyan.withValues(alpha: 0.4)
                            : (cls?.isSpam ?? false)
                                ? Colors.red.withValues(alpha: 0.4)
                                : Colors.green.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.item.isApproved
                                  ? Icons.verified
                                  : (cls?.isSpam ?? false)
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline,
                              size: 18,
                              color: widget.item.isApproved
                                  ? Colors.cyan
                                  : (cls?.isSpam ?? false)
                                      ? Colors.redAccent
                                      : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.item.isApproved
                                  ? 'Approved Sender / Subject (Whitelisted)'
                                  : 'AI Classification: ${cls?.verdict.toUpperCase()} (${((cls?.confidence ?? 0.5) * 100).toInt()}%) • Category: ${cls?.category}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: widget.item.isApproved
                                    ? Colors.cyan
                                    : (cls?.isSpam ?? false)
                                        ? Colors.redAccent
                                        : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        if (cls?.reason.isNotEmpty ?? false) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Reason: ${cls!.reason}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (cls?.profileHits.isNotEmpty ?? false) ...[
                          const SizedBox(height: 6),
                          ...cls!.profileHits.map(
                            (hit) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: Colors.purpleAccent)),
                                  Expanded(
                                    child: Text(
                                      hit,
                                      style: const TextStyle(fontSize: 12, color: Colors.purpleAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Body Title
                Text(
                  'Message Body Preview',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),

                // Body Content Box
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: state.isLoadingBody
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Downloading email body...'),
                              ],
                            ),
                          )
                        : SelectableText(
                            widget.item.fullBody ?? widget.item.bodySnippet ?? '(No body content available)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Move to Inbox & Train Ham'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: () {
                        final currentCol = _findColumnForMailbox(state, widget.item.mailboxPath);
                        state.moveEmail(widget.item, from: currentCol, to: ColumnType.inbox);
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Move to Spam & Train Spam'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      ),
                      onPressed: () => _moveToSpamOrPrompt(context, state),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Move to Trash'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        final currentCol = _findColumnForMailbox(state, widget.item.mailboxPath);
                        state.deleteEmail(widget.item, from: currentCol);
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close (Esc)'),
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

  ColumnType _findColumnForMailbox(EmailClientState state, String path) {
    if (path.toLowerCase().contains('ai-spam')) return ColumnType.aiSpam;
    if (path.toLowerCase().contains('spam') || path.toLowerCase().contains('junk')) return ColumnType.spam;
    return ColumnType.inbox;
  }

  void _moveToSpamOrPrompt(BuildContext context, EmailClientState state) {
    final currentCol = _findColumnForMailbox(state, widget.item.mailboxPath);
    final matches = state.findMatchingEmails(widget.item, currentCol);
    Navigator.of(context).pop();
    if (matches.bySender.isNotEmpty || matches.bySubject.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => BatchSpamDialog(
          item: widget.item,
          fromColumn: currentCol,
          bySender: matches.bySender,
          bySubject: matches.bySubject,
          combined: matches.combined,
        ),
      );
    } else {
      state.moveEmail(widget.item, from: currentCol, to: ColumnType.spam);
    }
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

