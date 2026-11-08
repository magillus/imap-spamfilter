import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/email_client_state.dart';
import 'batch_spam_dialog.dart';
import 'column_recheck_dialog.dart';
import 'email_card.dart';

class EmailColumn extends StatefulWidget {
  final ColumnType columnType;
  final String title;
  final IconData icon;
  final Color accentColor;
  final String shortcutKey;

  const EmailColumn({
    super.key,
    required this.columnType,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.shortcutKey,
  });

  @override
  State<EmailColumn> createState() => _EmailColumnState();
}

class _EmailColumnState extends State<EmailColumn> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index, int totalItems) {
    if (!_scrollController.hasClients || index < 0) return;
    // Each item is approx 100px height
    final targetOffset = (index * 105.0) - 100.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final isFocused = state.focusedColumnIndex == widget.columnType.index;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final emails = switch (widget.columnType) {
      ColumnType.inbox => state.getInboxEmails(),
      ColumnType.aiSpam => state.getAiSpamEmails(),
      ColumnType.spam => state.getSpamEmails(),
    };

    final totalCount = state.getTotalCount(widget.columnType);
    final isLoading = state.isLoadingColumn(widget.columnType);
    final isRechecking = state.isRecheckingColumn(widget.columnType);
    final hasMore = state.hasMoreColumn(widget.columnType);
    final selectedIndex = state.getSelectedIndex(widget.columnType);

    // Auto-scroll on keyboard selection change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isFocused && selectedIndex >= 0 && selectedIndex < emails.length) {
        _scrollToIndex(selectedIndex, emails.length);
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused
              ? widget.accentColor.withValues(alpha: 0.8)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isFocused ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          _buildHeader(context, state, emails.length, totalCount, isFocused, isLoading, isRechecking, emails.isEmpty),

          // Search Field (if toggled)
          if (_showSearch) _buildSearchField(context, state),

          // Loading Progress Bar
          if (isLoading && emails.isEmpty)
            LinearProgressIndicator(
              color: widget.accentColor,
              backgroundColor: widget.accentColor.withValues(alpha: 0.1),
            )
          else if (isLoading)
            LinearProgressIndicator(
              minHeight: 2,
              color: widget.accentColor,
              backgroundColor: Colors.transparent,
            ),

          // Emails List
          Expanded(
            child: emails.isEmpty
                ? _buildEmptyState(context, isLoading)
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: emails.length + (hasMore ? 1 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      if (index == emails.length) {
                        return _buildLoadMoreButton(context, state, isLoading, totalCount - emails.length);
                      }

                      final item = emails[index];
                      final isSelected = selectedIndex == index;

                      return EmailCard(
                        item: item,
                        isSelected: isSelected,
                        isColumnFocused: isFocused,
                        columnType: widget.columnType,
                        onTap: () {
                          state.selectEmailInColumn(widget.columnType, index);
                        },
                        onPreview: () {
                          state.openEmailDetail(item);
                        },
                        onMoveLeft: () {
                          if (widget.columnType == ColumnType.aiSpam || widget.columnType == ColumnType.spam) {
                            state.moveEmail(item, from: widget.columnType, to: ColumnType.inbox);
                          }
                        },
                        onMoveRight: () {
                          if (widget.columnType == ColumnType.aiSpam || widget.columnType == ColumnType.inbox) {
                            final matches = state.findMatchingEmails(item, widget.columnType);
                            if (matches.bySender.isNotEmpty || matches.bySubject.isNotEmpty) {
                              showDialog(
                                context: context,
                                builder: (ctx) => BatchSpamDialog(
                                  item: item,
                                  fromColumn: widget.columnType,
                                  bySender: matches.bySender,
                                  bySubject: matches.bySubject,
                                  combined: matches.combined,
                                ),
                              );
                            } else {
                              state.moveEmail(item, from: widget.columnType, to: ColumnType.spam);
                            }
                          }
                        },
                        onDelete: () {
                          state.deleteEmail(item, from: widget.columnType);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    EmailClientState state,
    int showingCount,
    int totalCount,
    bool isFocused,
    bool isLoading,
    bool isRechecking,
    bool isEmpty,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () => state.setFocusedColumn(widget.columnType.index),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isFocused
              ? widget.accentColor.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Icon(widget.icon, size: 18, color: widget.accentColor),
            const SizedBox(width: 6),

            // Title
            Flexible(
              child: Text(
                widget.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isFocused ? widget.accentColor : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 4),

            // Shortcut badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Text(
                widget.shortcutKey,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Count badge
            Text(
              showingCount < totalCount ? '$showingCount/$totalCount' : '$totalCount',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(width: 2),

            // Search toggle button
            IconButton(
              icon: Icon(
                _showSearch ? Icons.search_off : Icons.search,
                size: 16,
                color: _showSearch ? widget.accentColor : colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Filter emails',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    state.setSearchQuery(widget.columnType, '');
                  }
                });
              },
            ),

            // Refresh button
            IconButton(
              icon: isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              tooltip: 'Refresh column',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: (isLoading || isRechecking) ? null : () => state.refreshColumn(widget.columnType),
            ),

            // Recheck with retrained profile button
            IconButton(
              icon: isRechecking
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rule_folder_outlined, size: 16),
              tooltip: 'Recheck ${widget.title} with retrained profile',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: (isLoading || isRechecking || isEmpty)
                  ? null
                  : () => _handleRecheck(state),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRecheck(EmailClientState state) async {
    final summary = await state.recheckColumnWithProfile(widget.columnType);
    if (!mounted) return;

    if (summary.spamMatches.isEmpty && summary.approvedMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recheck complete: All ${summary.totalScanned} emails in ${widget.title} verified with retrained profile (all clean).',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => ColumnRecheckDialog(summary: summary),
      );
    }
  }

  Widget _buildSearchField(BuildContext context, EmailClientState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: TextField(
        controller: _searchController,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Filter by sender or subject...',
          hintStyle: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          prefixIcon: const Icon(Icons.search, size: 16),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  onPressed: () {
                    _searchController.clear();
                    state.setSearchQuery(widget.columnType, '');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: widget.accentColor),
          ),
        ),
        onChanged: (val) {
          state.setSearchQuery(widget.columnType, val);
        },
      ),
    );
  }

  Widget _buildLoadMoreButton(
    BuildContext context,
    EmailClientState state,
    bool isLoading,
    int remainingCount,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: OutlinedButton.icon(
          icon: isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_downward, size: 16),
          label: Text(
            remainingCount > 0 ? 'Load more (+100) • $remainingCount left' : 'Load more (+100)',
          ),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: isLoading ? null : () => state.loadMore(widget.columnType),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isLoading) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: widget.accentColor),
            const SizedBox(height: 12),
            Text(
              'Fetching messages...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No emails in ${widget.title}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
