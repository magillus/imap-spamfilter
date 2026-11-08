import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/email_client_state.dart';
import 'account_dialog.dart';
import 'batch_spam_dialog.dart';
import 'email_column.dart';
import 'email_detail_dialog.dart';
import 'training_stats_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
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

  void _handleKeyEvent(KeyEvent event, EmailClientState state) {
    if (event is! KeyDownEvent) return;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final isEditingText = primaryFocus?.context?.widget is EditableText;
    if (isEditingText) return;

    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      state.deleteSelectedEmail();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      state.moveSelectionUp();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      state.moveSelectionDown();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      state.handleLeftArrow();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _promptOrMoveToSpam(state);
    } else if (key == LogicalKeyboardKey.digit1) {
      state.setFocusedColumn(0); // Inbox
    } else if (key == LogicalKeyboardKey.digit2) {
      state.setFocusedColumn(1); // AI-Spam
    } else if (key == LogicalKeyboardKey.digit3) {
      state.setFocusedColumn(2); // Spam
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      final selected = state.selectedEmailInFocusedColumn;
      if (selected != null) {
        state.openEmailDetail(selected);
      }
    } else if (key == LogicalKeyboardKey.keyR) {
      if (isShift) {
        state.refreshAll();
      } else {
        state.refreshColumn(ColumnType.values[state.focusedColumnIndex]);
      }
    }
  }

  void _promptOrMoveToSpam(EmailClientState state) {
    final col = ColumnType.values[state.focusedColumnIndex];
    if (col == ColumnType.spam) {
      state.handleRightArrow();
      return;
    }
    final item = state.selectedEmailInFocusedColumn;
    if (item == null) return;

    final matches = state.findMatchingEmails(item, col);
    if (matches.bySender.isNotEmpty || matches.bySubject.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => BatchSpamDialog(
          item: item,
          fromColumn: col,
          bySender: matches.bySender,
          bySubject: matches.bySubject,
          combined: matches.combined,
        ),
      ).then((_) => _focusNode.requestFocus());
    } else {
      state.handleRightArrow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show inspected email dialog when requested
    if (state.inspectedEmail != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (ctx) => EmailDetailDialog(item: state.inspectedEmail!),
        ).then((_) {
          state.closeEmailDetail();
          _focusNode.requestFocus();
        });
      });
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, state),
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          titleSpacing: 16,
          backgroundColor: colorScheme.surface,
          elevation: 1,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.mark_email_unread, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Spam Filter Triage & AI Training',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      state.activeAccount != null
                          ? '${state.activeAccount!.user} (${state.activeAccount!.host})'
                          : 'No account connected',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            // Connection Status Indicator
            _buildConnectionBadge(context, state),

            const SizedBox(width: 8),

            // Account Switcher Button
            OutlinedButton.icon(
              icon: const Icon(Icons.account_circle_outlined, size: 16),
              label: Text(state.activeAccount?.name ?? 'Accounts'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const AccountDialog(),
                ).then((_) => _focusNode.requestFocus());
              },
            ),

            const SizedBox(width: 8),

            // Global Refresh All
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Refresh All Folders (Shift + R)',
              visualDensity: VisualDensity.compact,
              onPressed: () => state.refreshAll(),
            ),

            const SizedBox(width: 12),
          ],
        ),

        // Main 3-Column Body
        body: Column(
          children: [
            // Error banner if any
            if (state.connectionError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.red.shade900.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connection error: ${state.connectionError}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      child: const Text('Configure Accounts'),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => const AccountDialog(),
                        ).then((_) => _focusNode.requestFocus());
                      },
                    ),
                  ],
                ),
              ),

            // Three Columns
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // LEFT COLUMN: Inbox emails
                    const Expanded(
                      child: EmailColumn(
                        columnType: ColumnType.inbox,
                        title: 'Inbox',
                        icon: Icons.inbox,
                        accentColor: Colors.blueAccent,
                        shortcutKey: '1',
                      ),
                    ),

                    const SizedBox(width: 12),

                    // CENTER COLUMN: AI-Spam emails
                    const Expanded(
                      child: EmailColumn(
                        columnType: ColumnType.aiSpam,
                        title: 'AI-Spam',
                        icon: Icons.psychology,
                        accentColor: Colors.amber,
                        shortcutKey: '2 (Triage)',
                      ),
                    ),

                    const SizedBox(width: 12),

                    // RIGHT COLUMN: Spam emails
                    const Expanded(
                      child: EmailColumn(
                        columnType: ColumnType.spam,
                        title: 'Spam',
                        icon: Icons.report_outlined,
                        accentColor: Colors.redAccent,
                        shortcutKey: '3',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Training & Status Bar
            const TrainingStatsBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(BuildContext context, EmailClientState state) {
    if (state.isConnecting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber),
            ),
            SizedBox(width: 6),
            Text(
              'Connecting...',
              style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (state.isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Connected',
              style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 12, color: Colors.redAccent),
          SizedBox(width: 4),
          Text(
            'Disconnected',
            style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
