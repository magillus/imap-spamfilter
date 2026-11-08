import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import '../models/account_config.dart';
import '../models/email_item.dart';
import '../services/imap_service.dart';
import '../services/spam_training_service.dart';

enum ColumnType { inbox, aiSpam, spam }

class EmailClientState extends ChangeNotifier {
  final ImapService _imapService = ImapService();
  SpamTrainingService? _trainingService;

  List<AccountConfig> _accounts = [];
  AccountConfig? _activeAccount;

  bool _isConnecting = false;
  String? _connectionError;

  // 3 Columns: 0 = Inbox, 1 = AI-Spam, 2 = Spam
  int _focusedColumnIndex = 1; // Default to AI-Spam (center)
  final Map<ColumnType, List<EmailItem>> _emails = {
    ColumnType.inbox: [],
    ColumnType.aiSpam: [],
    ColumnType.spam: [],
  };

  final Map<ColumnType, int> _totalCounts = {
    ColumnType.inbox: 0,
    ColumnType.aiSpam: 0,
    ColumnType.spam: 0,
  };

  final Map<ColumnType, bool> _isLoading = {
    ColumnType.inbox: false,
    ColumnType.aiSpam: false,
    ColumnType.spam: false,
  };

  final Map<ColumnType, bool> _isRechecking = {
    ColumnType.inbox: false,
    ColumnType.aiSpam: false,
    ColumnType.spam: false,
  };

  final Map<ColumnType, bool> _hasMore = {
    ColumnType.inbox: false,
    ColumnType.aiSpam: false,
    ColumnType.spam: false,
  };

  final Map<ColumnType, int> _selectedIndices = {
    ColumnType.inbox: -1,
    ColumnType.aiSpam: -1,
    ColumnType.spam: -1,
  };

  final Map<ColumnType, String> _searchQueries = {
    ColumnType.inbox: '',
    ColumnType.aiSpam: '',
    ColumnType.spam: '',
  };

  EmailItem? _inspectedEmail;
  bool _isLoadingBody = false;
  String _statusBannerMessage = 'Ready';

  // Getters
  List<AccountConfig> get accounts => _accounts;
  AccountConfig? get activeAccount => _activeAccount;
  bool get isConnecting => _isConnecting;
  String? get connectionError => _connectionError;
  bool get isConnected => _imapService.isConnected;
  int get focusedColumnIndex => _focusedColumnIndex;
  EmailItem? get inspectedEmail => _inspectedEmail;
  bool get isLoadingBody => _isLoadingBody;
  String get statusBannerMessage => _statusBannerMessage;
  SpamTrainingService? get trainingService => _trainingService;

  List<EmailItem> getInboxEmails() => _filterEmails(ColumnType.inbox);
  List<EmailItem> getAiSpamEmails() => _filterEmails(ColumnType.aiSpam);
  List<EmailItem> getSpamEmails() => _filterEmails(ColumnType.spam);

  int getTotalCount(ColumnType col) => _totalCounts[col] ?? 0;
  bool isLoadingColumn(ColumnType col) => _isLoading[col] ?? false;
  bool isRecheckingColumn(ColumnType col) => _isRechecking[col] ?? false;
  bool hasMoreColumn(ColumnType col) => _hasMore[col] ?? false;
  int getSelectedIndex(ColumnType col) => _selectedIndices[col] ?? -1;
  String getSearchQuery(ColumnType col) => _searchQueries[col] ?? '';

  EmailItem? get selectedEmailInFocusedColumn {
    final col = ColumnType.values[_focusedColumnIndex];
    final list = _filterEmails(col);
    final idx = _selectedIndices[col] ?? -1;
    if (idx >= 0 && idx < list.length) {
      return list[idx];
    }
    return null;
  }

  EmailClientState({bool autoConnect = true}) {
    if (autoConnect) {
      _init();
    } else {
      _accounts = AccountConfig.loadDiscoveredAccounts();
      if (_accounts.isNotEmpty) {
        _activeAccount = _accounts.first;
      }
    }
  }

  @override
  void dispose() {
    _trainingService?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _accounts = AccountConfig.loadDiscoveredAccounts();
    if (_accounts.isNotEmpty) {
      await selectAccount(_accounts.first);
    }
  }

  Future<void> selectAccount(AccountConfig account) async {
    _activeAccount = account;
    _connectionError = null;
    _isConnecting = true;
    _statusBannerMessage = 'Connecting to ${account.host}...';
    notifyListeners();

    try {
      _trainingService?.dispose();
      _trainingService = SpamTrainingService(account, onStateChanged: notifyListeners);
      await _imapService.connect(account);

      _statusBannerMessage = 'Connected as ${account.user}. Fetching folders...';
      _isConnecting = false;
      notifyListeners();

      await refreshAll();
      _statusBannerMessage = 'Ready - triaging ${account.name}';
    } catch (e, st) {
      _isConnecting = false;
      _connectionError = e.toString();
      _statusBannerMessage = 'Connection failed: $e';
      stderr.writeln('Connection error: $e\n$st');
      notifyListeners();
    }
  }

  void setFocusedColumn(int index) {
    if (index >= 0 && index < 3) {
      _focusedColumnIndex = index;
      final col = ColumnType.values[index];
      final list = _filterEmails(col);
      if (list.isNotEmpty && _selectedIndices[col]! < 0) {
        _selectedIndices[col] = 0;
      }
      notifyListeners();
    }
  }

  void selectEmailInColumn(ColumnType col, int index) {
    _focusedColumnIndex = col.index;
    _selectedIndices[col] = index;
    notifyListeners();
  }

  void setSearchQuery(ColumnType col, String query) {
    _searchQueries[col] = query;
    _selectedIndices[col] = 0;
    notifyListeners();
  }

  List<EmailItem> _filterEmails(ColumnType col) {
    final list = _emails[col] ?? [];
    final q = (_searchQueries[col] ?? '').toLowerCase().trim();
    if (q.isEmpty) return list;
    return list.where((item) {
      return item.subject.toLowerCase().contains(q) ||
          item.fromEmail.toLowerCase().contains(q) ||
          item.fromName.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> refreshAll() async {
    await refreshColumn(ColumnType.inbox);
    await refreshColumn(ColumnType.aiSpam);
    await refreshColumn(ColumnType.spam);
  }

  Future<void> refreshColumn(ColumnType col) async {
    if (!_imapService.isConnected) return;
    _isLoading[col] = true;
    notifyListeners();

    try {
      final mailbox = _getMailboxForColumn(col);
      if (mailbox == null) {
        _emails[col] = [];
        _totalCounts[col] = 0;
        _isLoading[col] = false;
        notifyListeners();
        return;
      }

      final res = await _imapService.fetchEmails(mailbox, limit: 100, offset: 0);

      // Attach local classification and approval data
      for (final item in res.items) {
        _enrichEmailWithLocalData(item);
      }

      res.items.sort(EmailItem.compareNewestFirst);
      _emails[col] = res.items;
      _totalCounts[col] = res.totalCount;
      _hasMore[col] = res.hasMore;

      if (_emails[col]!.isNotEmpty && (_selectedIndices[col] ?? -1) < 0) {
        _selectedIndices[col] = 0;
      }
    } catch (e, st) {
      _statusBannerMessage = 'Error refreshing ${col.name}: $e';
      stderr.writeln('Error refreshing ${col.name}: $e\n$st');
    } finally {
      _isLoading[col] = false;
      notifyListeners();
    }
  }

  /// Rechecks all emails currently in [col] against the retrained spam profile and approved whitelist.
  Future<ColumnRecheckSummary> recheckColumnWithProfile(ColumnType col) async {
    _isRechecking[col] = true;
    _statusBannerMessage = 'Rechecking ${col.name} with retrained spam profile...';
    notifyListeners();

    try {
      _trainingService?.reloadFiles();

      final list = _emails[col] ?? [];
      final spamMatches = <EmailItem>[];
      final approvedMatches = <EmailItem>[];
      final cleanEmails = <EmailItem>[];
      int statusChangedCount = 0;

      for (final item in list) {
        final prevSpam = item.classification?.isSpam ?? false;
        final prevApproved = item.isApproved;

        if (_trainingService != null) {
          final res = _trainingService!.evaluateEmail(item);
          if (res.isApproved) {
            approvedMatches.add(item);
          } else if (res.isSpam) {
            spamMatches.add(item);
          } else {
            cleanEmails.add(item);
          }

          if (prevSpam != res.isSpam || prevApproved != res.isApproved) {
            statusChangedCount++;
          }
        } else {
          cleanEmails.add(item);
        }
      }

      final summary = ColumnRecheckSummary(
        column: col,
        totalScanned: list.length,
        spamMatches: spamMatches,
        approvedMatches: approvedMatches,
        cleanEmails: cleanEmails,
        statusChangedCount: statusChangedCount,
      );

      _statusBannerMessage =
          'Recheck complete: ${spamMatches.length} spam match(es), ${approvedMatches.length} approved in ${col.name}';
      return summary;
    } catch (e, st) {
      _statusBannerMessage = 'Error rechecking ${col.name}: $e';
      stderr.writeln('Error rechecking ${col.name}: $e\n$st');
      return ColumnRecheckSummary(
        column: col,
        totalScanned: _emails[col]?.length ?? 0,
        spamMatches: [],
        approvedMatches: [],
        cleanEmails: _emails[col] ?? [],
        statusChangedCount: 0,
      );
    } finally {
      _isRechecking[col] = false;
      notifyListeners();
    }
  }

  Future<void> loadMore(ColumnType col) async {
    if (!_imapService.isConnected || (_isLoading[col] ?? false) || !(_hasMore[col] ?? false)) {
      return;
    }

    _isLoading[col] = true;
    notifyListeners();

    try {
      final mailbox = _getMailboxForColumn(col);
      if (mailbox == null) return;

      final currentOffset = _emails[col]?.length ?? 0;
      final res = await _imapService.fetchEmails(mailbox, limit: 100, offset: currentOffset);

      for (final item in res.items) {
        _enrichEmailWithLocalData(item);
      }

      _emails[col]!.addAll(res.items);
      _emails[col]!.sort(EmailItem.compareNewestFirst);
      _totalCounts[col] = res.totalCount;
      _hasMore[col] = res.hasMore;
    } catch (e) {
      _statusBannerMessage = 'Error loading more for ${col.name}: $e';
    } finally {
      _isLoading[col] = false;
      notifyListeners();
    }
  }

  void _enrichEmailWithLocalData(EmailItem item) {
    if (_trainingService == null) return;
    final classification = _trainingService!.getClassification(item.messageId);
    if (classification != null) {
      item.classification = classification;
    }
    item.isApproved = _trainingService!.isSenderApproved(
      item.fromEmail,
      domain: item.senderBaseDomain,
      subject: item.subject,
    );
  }

  Mailbox? _getMailboxForColumn(ColumnType col) {
    switch (col) {
      case ColumnType.inbox:
        return _imapService.inboxMailbox;
      case ColumnType.aiSpam:
        return _imapService.aiSpamMailbox;
      case ColumnType.spam:
        return _imapService.spamMailbox;
    }
  }

  // --- Keyboard navigation ---

  void moveSelectionUp() {
    final col = ColumnType.values[_focusedColumnIndex];
    final list = _filterEmails(col);
    if (list.isEmpty) return;

    final cur = _selectedIndices[col] ?? 0;
    if (cur > 0) {
      _selectedIndices[col] = cur - 1;
      notifyListeners();
    }
  }

  void moveSelectionDown() {
    final col = ColumnType.values[_focusedColumnIndex];
    final list = _filterEmails(col);
    if (list.isEmpty) return;

    final cur = _selectedIndices[col] ?? 0;
    if (cur < list.length - 1) {
      _selectedIndices[col] = cur + 1;
      notifyListeners();
    }
  }

  /// Left Arrow: Assign to Inbox (from AI-Spam or Spam)
  Future<void> handleLeftArrow() async {
    final col = ColumnType.values[_focusedColumnIndex];
    final item = selectedEmailInFocusedColumn;
    if (item == null) return;

    if (col == ColumnType.aiSpam) {
      await moveEmail(item, from: ColumnType.aiSpam, to: ColumnType.inbox);
    } else if (col == ColumnType.spam) {
      await moveEmail(item, from: ColumnType.spam, to: ColumnType.inbox);
    } else if (col == ColumnType.inbox) {
      _statusBannerMessage = 'Already in Inbox';
      notifyListeners();
    }
  }

  /// Right Arrow: Assign to Spam (from AI-Spam or Inbox)
  Future<void> handleRightArrow() async {
    final col = ColumnType.values[_focusedColumnIndex];
    final item = selectedEmailInFocusedColumn;
    if (item == null) return;

    if (col == ColumnType.aiSpam) {
      await moveEmail(item, from: ColumnType.aiSpam, to: ColumnType.spam);
    } else if (col == ColumnType.inbox) {
      await moveEmail(item, from: ColumnType.inbox, to: ColumnType.spam);
    } else if (col == ColumnType.spam) {
      _statusBannerMessage = 'Already in Spam';
      notifyListeners();
    }
  }

  /// Core Move Method: handles optimistic UI update, IMAP move, and Spam training update!
  Future<void> moveEmail(
    EmailItem item, {
    required ColumnType from,
    required ColumnType to,
  }) async {
    final targetMailbox = _getMailboxForColumn(to);
    if (targetMailbox == null) {
      _statusBannerMessage = 'Target folder for ${to.name} not found';
      notifyListeners();
      return;
    }

    // 1. Optimistic UI update
    final fromList = _emails[from]!;
    final itemIndex = fromList.indexOf(item);
    if (itemIndex >= 0) {
      fromList.removeAt(itemIndex);
      _totalCounts[from] = (_totalCounts[from] ?? 1) - 1;

      // Keep selection index valid in source column
      final filteredList = _filterEmails(from);
      if (filteredList.isEmpty) {
        _selectedIndices[from] = -1;
      } else if (_selectedIndices[from]! >= filteredList.length) {
        _selectedIndices[from] = filteredList.length - 1;
      }
    }

    // Add to target column preserving newest-first order
    _emails[to]!.add(item);
    _emails[to]!.sort(EmailItem.compareNewestFirst);
    _totalCounts[to] = (_totalCounts[to] ?? 0) + 1;

    // 2. Training logic update
    if (to == ColumnType.inbox) {
      _statusBannerMessage = 'Moved to Inbox & trained as Ham (${item.fromEmail})';
      await _trainingService?.trainAsHam(item);
    } else if (to == ColumnType.spam) {
      _statusBannerMessage = 'Moved to Spam & trained as Spam (${item.fromEmail})';
      await _trainingService?.trainAsSpam(item);
    }

    notifyListeners();

    // 3. Execute IMAP move asynchronously
    final success = await _imapService.moveEmail(item, targetMailbox);
    if (!success) {
      _statusBannerMessage = 'IMAP move failed for "${item.subject}". Refreshing...';
      // Rollback or reload
      await refreshColumn(from);
      await refreshColumn(to);
    }
  }

  /// Finds other emails in [from] column that share the same sender email address or title/subject.
  ({List<EmailItem> bySender, List<EmailItem> bySubject, List<EmailItem> combined})
      findMatchingEmails(EmailItem item, ColumnType from) {
    final list = _emails[from] ?? [];
    final targetSender = item.fromEmail.toLowerCase().trim();
    final targetSubject = item.normalizedSubject;

    final bySender = <EmailItem>[];
    final bySubject = <EmailItem>[];
    final combinedSet = <EmailItem>{};

    for (final other in list) {
      if (other.uid == item.uid && other.messageId == item.messageId) continue;

      final matchesSender = targetSender.isNotEmpty &&
          other.fromEmail.toLowerCase().trim() == targetSender;
      final matchesSubject = targetSubject.isNotEmpty &&
          other.normalizedSubject == targetSubject;

      if (matchesSender) bySender.add(other);
      if (matchesSubject) bySubject.add(other);
      if (matchesSender || matchesSubject) combinedSet.add(other);
    }

    return (
      bySender: bySender,
      bySubject: bySubject,
      combined: combinedSet.toList(),
    );
  }

  /// Moves multiple emails at once (batch triage)
  Future<void> moveMultipleEmails(
    List<EmailItem> items, {
    required ColumnType from,
    required ColumnType to,
  }) async {
    if (items.isEmpty) return;
    final targetMailbox = _getMailboxForColumn(to);
    if (targetMailbox == null) {
      _statusBannerMessage = 'Target folder for ${to.name} not found';
      notifyListeners();
      return;
    }

    // 1. Optimistic UI update
    final fromList = _emails[from]!;
    for (final item in items) {
      fromList.remove(item);
    }
    _totalCounts[from] = max(0, (_totalCounts[from] ?? items.length) - items.length);

    // Keep selection index valid in source column
    final filteredList = _filterEmails(from);
    if (filteredList.isEmpty) {
      _selectedIndices[from] = -1;
    } else if (_selectedIndices[from]! >= filteredList.length) {
      _selectedIndices[from] = filteredList.length - 1;
    }

    // Add to target column preserving newest-first order
    _emails[to]!.addAll(items);
    _emails[to]!.sort(EmailItem.compareNewestFirst);
    _totalCounts[to] = (_totalCounts[to] ?? 0) + items.length;

    // 2. Training logic update for each email
    if (to == ColumnType.spam) {
      _statusBannerMessage = 'Moved ${items.length} emails to Spam & trained AI';
      for (final item in items) {
        await _trainingService?.trainAsSpam(item);
      }
    } else if (to == ColumnType.inbox) {
      _statusBannerMessage = 'Moved ${items.length} emails to Inbox & trained Ham';
      for (final item in items) {
        await _trainingService?.trainAsHam(item);
      }
    }

    notifyListeners();

    // 3. Execute IMAP moves asynchronously via synchronized ImapService
    for (final item in items) {
      final success = await _imapService.moveEmail(item, targetMailbox);
      if (!success) {
        stderr.writeln('Failed to move item ${item.uid} to ${targetMailbox.encodedPath}');
      }
    }
  }

  /// Moves the selected email in the focused column to Trash (called by Delete/Backspace key)
  Future<void> deleteSelectedEmail() async {
    final col = ColumnType.values[_focusedColumnIndex];
    final item = selectedEmailInFocusedColumn;
    if (item == null) return;
    await deleteEmail(item, from: col);
  }

  /// Moves email from specified column to Trash
  Future<void> deleteEmail(EmailItem item, {required ColumnType from}) async {
    final trashMailbox = _imapService.trashMailbox;
    if (trashMailbox == null) {
      _statusBannerMessage = 'Trash folder not found on server';
      notifyListeners();
      return;
    }

    // 1. Optimistic UI update
    final fromList = _emails[from]!;
    final itemIndex = fromList.indexOf(item);
    if (itemIndex >= 0) {
      fromList.removeAt(itemIndex);
      _totalCounts[from] = (_totalCounts[from] ?? 1) - 1;

      // Keep selection index valid in source column
      final filteredList = _filterEmails(from);
      if (filteredList.isEmpty) {
        _selectedIndices[from] = -1;
      } else if (_selectedIndices[from]! >= filteredList.length) {
        _selectedIndices[from] = filteredList.length - 1;
      }
    }

    _statusBannerMessage = 'Moved to Trash: "${item.subject}" (${item.fromEmail})';
    notifyListeners();

    // 2. Perform IMAP move to Trash
    final success = await _imapService.moveEmail(item, trashMailbox);
    if (!success) {
      _statusBannerMessage = 'Failed to move to Trash. Refreshing...';
      await refreshColumn(from);
    }
  }

  Future<void> openEmailDetail(EmailItem item) async {
    _inspectedEmail = item;
    notifyListeners();

    if (item.fullBody == null) {
      _isLoadingBody = true;
      notifyListeners();
      final body = await _imapService.fetchBodySnippet(item);
      item.fullBody = body;
      _isLoadingBody = false;
      notifyListeners();
    }
  }

  void closeEmailDetail() {
    _inspectedEmail = null;
    notifyListeners();
  }

  Future<String> triggerManualRetrain() async {
    if (_trainingService == null) return 'No active account';
    _statusBannerMessage = 'Retraining spam filter profile...';
    notifyListeners();

    final result = await _trainingService!.triggerFullLearnNow();
    _statusBannerMessage = _trainingService!.lastStatusMessage;
    notifyListeners();
    return result;
  }
}

class ColumnRecheckSummary {
  final ColumnType column;
  final int totalScanned;
  final List<EmailItem> spamMatches;
  final List<EmailItem> approvedMatches;
  final List<EmailItem> cleanEmails;
  final int statusChangedCount;

  ColumnRecheckSummary({
    required this.column,
    required this.totalScanned,
    required this.spamMatches,
    required this.approvedMatches,
    required this.cleanEmails,
    required this.statusChangedCount,
  });
}
