import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:email_client/models/account_config.dart';
import 'package:email_client/models/email_item.dart';
import 'package:email_client/services/spam_training_service.dart';

void main() {
  late Directory tempDir;
  late AccountConfig testAccount;
  late SpamTrainingService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spam_training_test_');
    testAccount = AccountConfig(
      name: 'test_account',
      host: 'mail.example.com',
      port: 993,
      user: 'test@example.com',
      dataDir: tempDir.path,
    );
    service = SpamTrainingService(
      testAccount,
      debounceDuration: const Duration(seconds: 45),
      maxBatchBeforeForceLearn: 10,
    );
  });

  tearDown(() {
    service.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('trainAsHam updates classified.json and adds sender to approved.json', () async {
    final item = EmailItem(
      uid: 101,
      sequenceId: 1,
      mailboxPath: 'INBOX.AI-Spam',
      fromName: 'Good Friend',
      fromEmail: 'friend@example.org',
      subject: 'Hello there!',
      messageId: '<msg101@example.org>',
    );

    expect(service.isSenderApproved('friend@example.org'), isFalse);

    await service.trainAsHam(item);

    expect(service.isSenderApproved('friend@example.org'), isTrue);
    final cls = service.getClassification('<msg101@example.org>');
    expect(cls, isNotNull);
    expect(cls!.verdict, equals('ham'));
    expect(cls.category, equals('approved'));
  });

  test('trainAsSpam updates classified.json and removes sender from approved.json', () async {
    final item = EmailItem(
      uid: 102,
      sequenceId: 2,
      mailboxPath: 'INBOX.AI-Spam',
      fromName: 'Spammer',
      fromEmail: 'scam@phish.xyz',
      subject: 'Claim your prize',
      messageId: '<msg102@phish.xyz>',
    );

    // Pre-approve to test removal
    await service.trainAsHam(item);
    expect(service.isSenderApproved('scam@phish.xyz'), isTrue);

    // Now train as spam
    await service.trainAsSpam(item);
    expect(service.isSenderApproved('scam@phish.xyz'), isFalse);

    final cls = service.getClassification('<msg102@phish.xyz>');
    expect(cls, isNotNull);
    expect(cls!.verdict, equals('spam'));
    expect(cls.category, equals('user_spam'));
  });

  test('batches triage changes and delays learn execution', () async {
    expect(service.pendingChangesCount, equals(0));

    for (int i = 1; i <= 5; i++) {
      final item = EmailItem(
        uid: 200 + i,
        sequenceId: i,
        mailboxPath: 'INBOX.AI-Spam',
        fromName: 'Sender $i',
        fromEmail: 'sender$i@example.com',
        subject: 'Subject $i',
        messageId: '<msg20$i@example.com>',
      );
      await service.trainAsHam(item);
    }

    // 5 emails moved -> 5 pending changes batched
    expect(service.pendingChangesCount, equals(5));
    expect(service.isTraining, isFalse);
    expect(service.scheduledLearnTime, isNotNull);

    final stats = service.getStats();
    expect(stats.pendingChangesCount, equals(5));
  });

  test('sorts emails with newest date on top', () {
    final older = EmailItem(
      uid: 1,
      sequenceId: 1,
      mailboxPath: 'INBOX',
      fromName: 'Older',
      fromEmail: 'older@example.com',
      subject: 'Older email',
      date: DateTime(2026, 11, 1, 10, 0),
      messageId: '<1@example.com>',
    );

    final newer = EmailItem(
      uid: 2,
      sequenceId: 2,
      mailboxPath: 'INBOX',
      fromName: 'Newer',
      fromEmail: 'newer@example.com',
      subject: 'Newer email',
      date: DateTime(2026, 11, 6, 17, 0),
      messageId: '<2@example.com>',
    );

    final newest = EmailItem(
      uid: 3,
      sequenceId: 3,
      mailboxPath: 'INBOX',
      fromName: 'Newest',
      fromEmail: 'newest@example.com',
      subject: 'Newest email',
      date: DateTime(2026, 11, 6, 17, 30),
      messageId: '<3@example.com>',
    );

    final list = [older, newest, newer];
    list.sort(EmailItem.compareNewestFirst);

    expect(list.first.subject, equals('Newest email'));
    expect(list[1].subject, equals('Newer email'));
    expect(list.last.subject, equals('Older email'));
  });

  test('normalizes subject by removing Re/Fwd prefixes', () {
    expect(EmailItem.cleanSubject('Re: Special Offer'), equals('Special Offer'));
    expect(EmailItem.cleanSubject('Fwd: Re: Special Offer'), equals('Special Offer'));
    expect(EmailItem.cleanSubject('aw: sv: Meeting Notes'), equals('Meeting Notes'));
    expect(EmailItem.cleanSubject('  Normal Subject  '), equals('Normal Subject'));

    final item1 = EmailItem(
      uid: 10,
      sequenceId: 10,
      mailboxPath: 'INBOX',
      fromName: 'Alice',
      fromEmail: 'alice@example.com',
      subject: 'Re: Project Update',
      messageId: '<item1@example.com>',
    );
    final item2 = EmailItem(
      uid: 11,
      sequenceId: 11,
      mailboxPath: 'INBOX',
      fromName: 'Bob',
      fromEmail: 'bob@example.com',
      subject: 'Fwd: project update',
      messageId: '<item2@example.com>',
    );

    expect(item1.normalizedSubject, equals('project update'));
    expect(item2.normalizedSubject, equals('project update'));
    expect(item1.normalizedSubject, equals(item2.normalizedSubject));
  });

  test('finds matching emails by sender and subject', () {
    final target = EmailItem(
      uid: 1,
      sequenceId: 1,
      mailboxPath: 'INBOX',
      fromName: 'Newsletter',
      fromEmail: 'news@daily.com',
      subject: 'Weekly Digest #42',
      messageId: '<target@daily.com>',
    );

    final matchSender = EmailItem(
      uid: 2,
      sequenceId: 2,
      mailboxPath: 'INBOX',
      fromName: 'Newsletter Team',
      fromEmail: 'news@daily.com',
      subject: 'Special Announcement',
      messageId: '<other1@daily.com>',
    );

    final matchSubject = EmailItem(
      uid: 3,
      sequenceId: 3,
      mailboxPath: 'INBOX',
      fromName: 'Forwarder',
      fromEmail: 'someone@other.com',
      subject: 'Re: Weekly Digest #42',
      messageId: '<other2@other.com>',
    );

    final matchBoth = EmailItem(
      uid: 4,
      sequenceId: 4,
      mailboxPath: 'INBOX',
      fromName: 'Newsletter',
      fromEmail: 'news@daily.com',
      subject: 'Weekly Digest #42',
      messageId: '<other3@daily.com>',
    );

    final unrelated = EmailItem(
      uid: 5,
      sequenceId: 5,
      mailboxPath: 'INBOX',
      fromName: 'Boss',
      fromEmail: 'boss@company.com',
      subject: 'Urgent task',
      messageId: '<unrelated@company.com>',
    );

    final emails = [target, matchSender, matchSubject, matchBoth, unrelated];

    final targetSender = target.fromEmail.toLowerCase().trim();
    final targetSubject = target.normalizedSubject;

    final bySender = <EmailItem>[];
    final bySubject = <EmailItem>[];
    final combinedSet = <EmailItem>{};

    for (final other in emails) {
      if (other.uid == target.uid && other.messageId == target.messageId) continue;
      final mSender = targetSender.isNotEmpty && other.fromEmail.toLowerCase().trim() == targetSender;
      final mSubject = targetSubject.isNotEmpty && other.normalizedSubject == targetSubject;

      if (mSender) bySender.add(other);
      if (mSubject) bySubject.add(other);
      if (mSender || mSubject) combinedSet.add(other);
    }

    expect(bySender.length, equals(2));
    expect(bySender.map((e) => e.uid), containsAll([2, 4]));

    expect(bySubject.length, equals(2));
    expect(bySubject.map((e) => e.uid), containsAll([3, 4]));

    expect(combinedSet.length, equals(3));
    expect(combinedSet.map((e) => e.uid), containsAll([2, 3, 4]));
    expect(combinedSet.map((e) => e.uid), isNot(contains(5)));
  });

  test('extractSubjectTokens strips stopwords and punctuation', () {
    final tokens = SpamTrainingService.extractSubjectTokens('Fwd: Re: The Great 100% Free Gift Offer for You!');
    expect(tokens, contains('great'));
    expect(tokens, contains('free'));
    expect(tokens, contains('gift'));
    expect(tokens, contains('offer'));
    // Stopwords removed:
    expect(tokens, isNot(contains('the')));
    expect(tokens, isNot(contains('for')));
    expect(tokens, isNot(contains('you')));
  });

  test('evaluateEmail evaluates against retrained profile and approved list', () async {
    // 1. Write mock spam_profile.json
    final profileFile = File('${tempDir.path}/spam_profile.json');
    profileFile.writeAsStringSync('''
{
  "generated": "2026-11-07 12:00:00",
  "senders": [
    {"value": "spammer@badsource.com", "spam_count": 8, "score": 3.1}
  ],
  "domains": [
    {"value": "scamdomain.org", "spam_count": 15, "score": 2.8}
  ],
  "display_names": [
    {"value": "lottery prize team", "spam_count": 5, "score": 2.0}
  ],
  "subject_words": [
    {"value": "jackpot", "spam_count": 22, "score": 4.5},
    {"value": "refinance", "spam_count": 14, "score": 3.0}
  ]
}
''');

    // 2. Write approved.json
    final approvedFile = File('${tempDir.path}/approved.json');
    approvedFile.writeAsStringSync('''
{
  "senders": ["boss@company.com"],
  "domains": ["goodcorp.com"],
  "subjects": ["payroll notification"]
}
''');

    service.reloadFiles();

    // Case A: Whitelisted sender
    final approvedItem = EmailItem(
      uid: 50,
      sequenceId: 50,
      mailboxPath: 'INBOX',
      fromName: 'The Boss',
      fromEmail: 'boss@company.com',
      subject: 'Refinance jackpot win', // Even if words match, approved wins
      messageId: '<appr1@company.com>',
    );
    final resApproved = service.evaluateEmail(approvedItem);
    expect(resApproved.isApproved, isTrue);
    expect(resApproved.isSpam, isFalse);
    expect(approvedItem.isApproved, isTrue);
    expect(approvedItem.classification?.verdict, equals('ham'));

    // Case B: Repeat spam sender
    final spamSenderItem = EmailItem(
      uid: 51,
      sequenceId: 51,
      mailboxPath: 'INBOX',
      fromName: 'Fake Deals',
      fromEmail: 'spammer@badsource.com',
      subject: 'Just saying hi',
      messageId: '<spam1@badsource.com>',
    );
    final resSenderSpam = service.evaluateEmail(spamSenderItem);
    expect(resSenderSpam.isSpam, isTrue);
    expect(resSenderSpam.isApproved, isFalse);
    expect(resSenderSpam.category, equals('profile_match'));
    expect(resSenderSpam.profileHits.any((h) => h.contains('spammer@badsource.com')), isTrue);
    expect(spamSenderItem.classification?.isSpam, isTrue);

    // Case C: Repeat spam domain
    final spamDomainItem = EmailItem(
      uid: 52,
      sequenceId: 52,
      mailboxPath: 'INBOX',
      fromName: 'Random Name',
      fromEmail: 'nobody@marketing.scamdomain.org',
      subject: 'Hello customer',
      messageId: '<spam2@marketing.scamdomain.org>',
    );
    final resDomainSpam = service.evaluateEmail(spamDomainItem);
    expect(resDomainSpam.isSpam, isTrue);
    expect(resDomainSpam.profileHits.any((h) => h.contains('scamdomain.org')), isTrue);

    // Case D: Subject words in profile
    final spamWordsItem = EmailItem(
      uid: 53,
      sequenceId: 53,
      mailboxPath: 'INBOX',
      fromName: 'Unrecognized Person',
      fromEmail: 'someone@somehost.io',
      subject: 'Claim your refinance jackpot now',
      messageId: '<spam3@somehost.io>',
    );
    final resWordsSpam = service.evaluateEmail(spamWordsItem);
    expect(resWordsSpam.isSpam, isTrue);
    expect(resWordsSpam.profileHits.any((h) => h.contains('jackpot')), isTrue);

    // Case E: Clean message
    final cleanItem = EmailItem(
      uid: 54,
      sequenceId: 54,
      mailboxPath: 'INBOX',
      fromName: 'Friend',
      fromEmail: 'friend@otherdomain.com',
      subject: 'Weekend hiking trip plan',
      messageId: '<clean1@otherdomain.com>',
    );
    final resClean = service.evaluateEmail(cleanItem);
    expect(resClean.isSpam, isFalse);
    expect(resClean.isApproved, isFalse);
    expect(resClean.category, equals('clean'));
    expect(cleanItem.classification?.verdict, equals('ham'));
  });
}
