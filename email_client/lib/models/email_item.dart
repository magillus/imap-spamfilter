import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:enough_mail/enough_mail.dart';
import 'spam_classification.dart';

class EmailItem {
  final int uid;
  final int sequenceId;
  final String mailboxPath;
  final String fromName;
  final String fromEmail;
  final String subject;
  final DateTime? date;
  final String messageId;
  final bool isSeen;
  final bool isFlagged;
  final int? size;
  SpamClassification? classification;
  bool isApproved;
  String? bodySnippet;
  String? fullBody;

  EmailItem({
    required this.uid,
    required this.sequenceId,
    required this.mailboxPath,
    required this.fromName,
    required this.fromEmail,
    required this.subject,
    this.date,
    required this.messageId,
    this.isSeen = false,
    this.isFlagged = false,
    this.size,
    this.classification,
    this.isApproved = false,
    this.bodySnippet,
    this.fullBody,
  });

  String get ref => sha1.convert(utf8.encode(messageId)).toString().substring(0, 6);

  String get senderDisplay {
    if (fromName.isNotEmpty && fromName != fromEmail) {
      return '$fromName <$fromEmail>';
    }
    return fromEmail.isNotEmpty ? fromEmail : fromName;
  }

  String get senderBaseDomain {
    if (!fromEmail.contains('@')) return '';
    final domain = fromEmail.split('@').last.toLowerCase().trim();
    final parts = domain.split('.');
    if (parts.length > 2 &&
        parts.last.length == 2 &&
        ['co', 'com', 'org', 'net', 'gov', 'ac'].contains(parts[parts.length - 2])) {
      return parts.sublist(parts.length - 3).join('.');
    }
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('.');
    }
    return domain;
  }

  /// Normalized subject without leading Re:, Fwd:, etc.
  String get normalizedSubject => cleanSubject(subject).toLowerCase();

  /// Removes leading Re:, Fwd:, etc. from subject
  static String cleanSubject(String text) {
    return text.replaceAll(RegExp(r'^\s*((re|fwd?|aw|sv)\s*:\s*)+', caseSensitive: false), '').trim();
  }

  factory EmailItem.fromMimeMessage(
    MimeMessage msg, {
    required int sequenceId,
    required String mailboxPath,
  }) {
    String fromName = '';
    String fromEmail = '';

    final fromList = msg.from;
    if (fromList != null && fromList.isNotEmpty) {
      final first = fromList.first;
      fromName = first.personalName ?? '';
      fromEmail = first.email;
    } else {
      final rawFrom = msg.decodeHeaderValue('from') ?? '';
      fromEmail = rawFrom;
    }

    final subject = msg.decodeSubject() ?? '(no subject)';
    final messageId = msg.decodeHeaderValue('message-id') ?? 'uid:$sequenceId';
    final date = msg.decodeDate() ?? msg.envelope?.date;
    final isSeen = msg.hasFlag(MessageFlags.seen);
    final isFlagged = msg.hasFlag(MessageFlags.flagged);

    return EmailItem(
      uid: msg.uid ?? sequenceId,
      sequenceId: sequenceId,
      mailboxPath: mailboxPath,
      fromName: fromName,
      fromEmail: fromEmail,
      subject: subject,
      date: date,
      messageId: messageId,
      isSeen: isSeen,
      isFlagged: isFlagged,
      size: msg.size,
    );
  }

  /// Sorts emails with the newest date / sequence on top (descending).
  static int compareNewestFirst(EmailItem a, EmailItem b) {
    if (a.date != null && b.date != null) {
      final dateComp = b.date!.compareTo(a.date!);
      if (dateComp != 0) return dateComp;
    } else if (a.date != null) {
      return -1;
    } else if (b.date != null) {
      return 1;
    }
    if (a.sequenceId != b.sequenceId) {
      return b.sequenceId.compareTo(a.sequenceId);
    }
    return b.uid.compareTo(a.uid);
  }
}
