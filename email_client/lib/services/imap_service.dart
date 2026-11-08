import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:enough_mail/enough_mail.dart';
import 'package:synchronized/synchronized.dart';
import '../models/account_config.dart';
import '../models/email_item.dart';

class ImapFolderInfo {
  final Mailbox mailbox;
  final String label;
  int totalMessages;

  ImapFolderInfo({
    required this.mailbox,
    required this.label,
    required this.totalMessages,
  });
}

class ImapService {
  final Lock _lock = Lock();
  ImapClient? _client;

  Mailbox? _inboxMailbox;
  Mailbox? _aiSpamMailbox;
  Mailbox? _spamMailbox;
  Mailbox? _trashMailbox;

  Mailbox? get inboxMailbox => _inboxMailbox;
  Mailbox? get aiSpamMailbox => _aiSpamMailbox;
  Mailbox? get spamMailbox => _spamMailbox;
  Mailbox? get trashMailbox => _trashMailbox;

  bool get isConnected => _client?.isConnected ?? false;

  Future<void> connect(AccountConfig account) => _lock.synchronized(() async {
    final password = account.getDecryptedPassword();
    if (password == null || password.isEmpty) {
      throw Exception('No IMAP password available for account "${account.name}". Please configure it or decrypt credentials.');
    }

    if (_client != null && _client!.isConnected) {
      try {
        await _client!.disconnect();
      } catch (_) {}
    }

    _client = ImapClient(isLogEnabled: false);
    await _client!.connectToServer(
      account.host,
      account.port,
      isSecure: true,
    );

    await _client!.login(account.user, password);

    // Resolve folders
    final allMailboxes = await _client!.listMailboxes(recursive: true);
    _resolveFolders(allMailboxes, account.spamFolder);
  });

  void _resolveFolders(List<Mailbox> mailboxes, String preferredAiSpamName) {
    // 1. Inbox
    _inboxMailbox = mailboxes.firstWhere(
      (m) => m.flags.contains(MailboxFlag.inbox) || m.name.toLowerCase() == 'inbox',
      orElse: () => mailboxes.firstWhere((m) => m.encodedPath.toUpperCase() == 'INBOX', orElse: () => mailboxes.first),
    );

    // 2. AI-Spam
    final aiSpamLower = preferredAiSpamName.toLowerCase();
    _aiSpamMailbox = mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && (m.name.toLowerCase() == aiSpamLower || m.encodedPath.toLowerCase().endsWith(aiSpamLower)),
      orElse: () => null,
    );
    _aiSpamMailbox ??= mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && m.name.toLowerCase().contains('ai-spam'),
      orElse: () => null,
    );

    // 3. Server Spam / Junk
    _spamMailbox = mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && (m.flags.contains(MailboxFlag.junk) || m.name.toLowerCase().endsWith('.spam') || m.name.toLowerCase() == 'spam'),
      orElse: () => null,
    );
    _spamMailbox ??= mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && (m.name.toLowerCase().contains('junk') || m.name.toLowerCase().contains('spam')),
      orElse: () => null,
    );

    // 4. Trash / Deleted Messages
    _trashMailbox = mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && (m.flags.contains(MailboxFlag.trash) || m.name.toLowerCase().endsWith('.trash') || m.name.toLowerCase() == 'trash'),
      orElse: () => null,
    );
    _trashMailbox ??= mailboxes.cast<Mailbox?>().firstWhere(
      (m) => m != null && (m.name.toLowerCase().contains('trash') || m.name.toLowerCase().contains('deleted')),
      orElse: () => null,
    );
  }

  Future<int> getFolderMessageCount(Mailbox mailbox) => _lock.synchronized(() async {
    _ensureConnected();
    final selected = await _client!.selectMailbox(mailbox);
    return selected.messagesExists;
  });

  /// Fetches [limit] messages starting from [offset] from the newest.
  /// Offset 0 means the newest messages.
  Future<({List<EmailItem> items, int totalCount, bool hasMore})> fetchEmails(
    Mailbox mailbox, {
    int limit = 100,
    int offset = 0,
  }) => _lock.synchronized(() async {
    _ensureConnected();
    final selected = await _client!.selectMailbox(mailbox);
    final total = selected.messagesExists;
    if (total == 0 || offset >= total) {
      return (items: <EmailItem>[], totalCount: total, hasMore: false);
    }

    // Messages sequence numbers are 1-based: 1..total
    // Newest is total.
    // At offset 0, we want messages: max(1, total - limit + 1) .. total
    // At offset K, we want: max(1, total - offset - limit + 1) .. (total - offset)
    final endSeq = total - offset;
    final startSeq = max(1, endSeq - limit + 1);

    final seq = MessageSequence.fromRange(startSeq, endSeq);
    final fetchRes = await _client!.fetchMessages(
      seq,
      '(UID RFC822.SIZE FLAGS ENVELOPE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])',
    );

    final list = <EmailItem>[];
    for (final msg in fetchRes.messages) {
      final item = EmailItem.fromMimeMessage(
        msg,
        sequenceId: msg.sequenceId ?? 0,
        mailboxPath: mailbox.encodedPath,
      );
      list.add(item);
    }

    // Sort newest first (descending date / sequence / UID)
    list.sort(EmailItem.compareNewestFirst);

    final hasMore = startSeq > 1;
    return (items: list, totalCount: total, hasMore: hasMore);
  });

  /// Moves email from current mailbox to target mailbox using IMAP UID MOVE
  Future<bool> moveEmail(EmailItem item, Mailbox targetMailbox) => _lock.synchronized(() async {
    _ensureConnected();
    try {
      // 1. Select the source mailbox
      await _client!.selectMailboxByPath(item.mailboxPath);

      // 2. Execute UID MOVE
      final seq = MessageSequence.fromId(item.uid);
      await _client!.uidMove(
        seq,
        targetMailboxPath: targetMailbox.encodedPath,
      );

      return true;
    } catch (e, st) {
      stderr.writeln('Error moving email UID ${item.uid} to ${targetMailbox.encodedPath}: $e\n$st');
      return false;
    }
  });

  /// Fetches plain text snippet or body for email preview
  Future<String> fetchBodySnippet(EmailItem item, {int maxBytes = 40000}) => _lock.synchronized(() async {
    _ensureConnected();
    try {
      await _client!.selectMailboxByPath(item.mailboxPath);
      final seq = MessageSequence.fromId(item.uid);
      final res = await _client!.uidFetchMessages(
        seq,
        'BODY.PEEK[]<0.$maxBytes>',
      );

      if (res.messages.isNotEmpty) {
        final msg = res.messages.first;
        final text = msg.decodeTextPlainPart();
        if (text != null && text.trim().isNotEmpty) {
          return text.trim();
        }
        final html = msg.decodeTextHtmlPart();
        if (html != null && html.trim().isNotEmpty) {
          return _stripHtml(html);
        }
      }
      return '(No message body content)';
    } catch (e) {
      return 'Error fetching email body: $e';
    }
  });

  String _stripHtml(String html) {
    var text = html.replaceAll(RegExp(r'<(script|style).*?</\1>', caseSensitive: false, dotAll: true), ' ');
    text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    text = text.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _ensureConnected() {
    if (_client == null || !_client!.isConnected) {
      throw Exception('IMAP client is not connected.');
    }
  }

  Future<void> disconnect() => _lock.synchronized(() async {
    if (_client != null && _client!.isConnected) {
      await _client!.disconnect();
    }
  });
}
