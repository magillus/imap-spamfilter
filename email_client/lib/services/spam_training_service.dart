import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/account_config.dart';
import '../models/email_item.dart';
import '../models/spam_classification.dart';

class SpamTrainingStats {
  final int approvedSendersCount;
  final int approvedDomainsCount;
  final int classifiedCount;
  final int spamProfileSendersCount;
  final int spamProfileDomainsCount;
  final int pendingChangesCount;
  final String? lastGenerated;

  SpamTrainingStats({
    required this.approvedSendersCount,
    required this.approvedDomainsCount,
    required this.classifiedCount,
    required this.spamProfileSendersCount,
    required this.spamProfileDomainsCount,
    this.pendingChangesCount = 0,
    this.lastGenerated,
  });
}

class SpamTrainingService {
  final AccountConfig account;
  final void Function()? onStateChanged;

  late final Directory dataDir;
  late final File classifiedFile;
  late final File approvedFile;
  late final File profileFile;

  Map<String, dynamic> _classified = {};
  Map<String, List<String>> _approved = {'senders': [], 'domains': [], 'subjects': []};
  Map<String, dynamic> _profile = {};

  bool _isTraining = false;
  int _pendingChangesCount = 0;
  String _lastStatusMessage = 'Ready';

  Timer? _debounceTimer;
  DateTime? _scheduledLearnTime;

  /// Inactivity period before triggering batched learn (e.g. 45 seconds).
  final Duration debounceDuration;

  /// Maximum triaged emails before automatically forcing a learn run.
  final int maxBatchBeforeForceLearn;

  bool get isTraining => _isTraining;
  int get pendingChangesCount => _pendingChangesCount;
  String get lastStatusMessage => _lastStatusMessage;
  DateTime? get scheduledLearnTime => _scheduledLearnTime;

  SpamTrainingService(
    this.account, {
    this.onStateChanged,
    this.debounceDuration = const Duration(seconds: 45),
    this.maxBatchBeforeForceLearn = 25,
  }) {
    dataDir = Directory(account.dataDir);
    if (!dataDir.existsSync()) {
      try {
        dataDir.createSync(recursive: true);
      } catch (_) {}
    }

    classifiedFile = File('${dataDir.path}/classified.json');
    approvedFile = File('${dataDir.path}/approved.json');
    profileFile = File('${dataDir.path}/spam_profile.json');

    reloadFiles();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void reloadFiles() {
    try {
      if (classifiedFile.existsSync()) {
        _classified = jsonDecode(classifiedFile.readAsStringSync()) as Map<String, dynamic>;
      } else {
        _classified = {};
      }
    } catch (e) {
      stderr.writeln('Error loading classified.json: $e');
      _classified = {};
    }

    try {
      if (approvedFile.existsSync()) {
        final decoded = jsonDecode(approvedFile.readAsStringSync()) as Map<String, dynamic>;
        _approved = {
          'senders': (decoded['senders'] as List? ?? []).map((e) => e.toString().toLowerCase()).toList(),
          'domains': (decoded['domains'] as List? ?? []).map((e) => e.toString().toLowerCase()).toList(),
          'subjects': (decoded['subjects'] as List? ?? []).map((e) => e.toString()).toList(),
        };
      } else {
        _approved = {'senders': [], 'domains': [], 'subjects': []};
      }
    } catch (e) {
      stderr.writeln('Error loading approved.json: $e');
      _approved = {'senders': [], 'domains': [], 'subjects': []};
    }

    try {
      if (profileFile.existsSync()) {
        _profile = jsonDecode(profileFile.readAsStringSync()) as Map<String, dynamic>;
      } else {
        _profile = {};
      }
    } catch (e) {
      stderr.writeln('Error loading spam_profile.json: $e');
      _profile = {};
    }
  }

  SpamClassification? getClassification(String messageId) {
    if (_classified.containsKey(messageId)) {
      final data = _classified[messageId];
      if (data is Map<String, dynamic>) {
        return SpamClassification.fromJson(data, messageId: messageId);
      }
    }
    return null;
  }

  bool isSenderApproved(String emailAddress, {String? domain, String? subject}) {
    final addr = emailAddress.toLowerCase().trim();
    if (_approved['senders']?.contains(addr) ?? false) return true;

    final dom = domain ?? (addr.contains('@') ? addr.split('@').last : '');
    if (dom.isNotEmpty) {
      for (final d in _approved['domains'] ?? <String>[]) {
        if (dom == d || dom.endsWith('.$d')) return true;
      }
    }

    if (subject != null && subject.isNotEmpty) {
      final subLower = subject.toLowerCase();
      for (final s in _approved['subjects'] ?? <String>[]) {
        if (subLower.contains(s.toLowerCase())) return true;
      }
    }

    return false;
  }

  SpamTrainingStats getStats() {
    return SpamTrainingStats(
      approvedSendersCount: _approved['senders']?.length ?? 0,
      approvedDomainsCount: _approved['domains']?.length ?? 0,
      classifiedCount: _classified.length,
      spamProfileSendersCount: (_profile['senders'] as List?)?.length ?? 0,
      spamProfileDomainsCount: (_profile['domains'] as List?)?.length ?? 0,
      pendingChangesCount: _pendingChangesCount,
      lastGenerated: _profile['generated'] as String?,
    );
  }

  /// Called when an email is assigned/moved to Inbox (trained as Ham / Legit)
  Future<void> trainAsHam(EmailItem item, {bool addToApproved = true}) async {
    final fromAddr = item.fromEmail.toLowerCase().trim();
    final messageId = item.messageId;

    // 1. Update classified.json immediately (fast local effect)
    final classification = SpamClassification(
      verdict: 'ham',
      confidence: 1.0,
      category: 'approved',
      reason: 'Trained as Ham / Approved by user',
      profileHits: [],
    );
    item.classification = classification;
    item.isApproved = true;

    _classified[messageId] = classification.toJson(
      from: fromAddr,
      subject: item.subject,
    );
    _saveClassified();

    // 2. Add to approved.json immediately
    if (addToApproved && fromAddr.isNotEmpty) {
      final senders = _approved['senders'] ?? [];
      if (!senders.contains(fromAddr)) {
        senders.add(fromAddr);
        _approved['senders'] = senders;
        _saveApproved();
      }
    }

    // 3. Update spam_profile.json in memory and disk
    _decrementSpamProfile(fromAddr, item.senderBaseDomain);

    _lastStatusMessage = 'Trained as Ham: ${fromAddr.isNotEmpty ? fromAddr : item.subject} (Approved)';

    // 4. Batch & debounce the heavy background learn command
    _scheduleBatchedLearn();
  }

  /// Called when an email is assigned/moved to Spam (trained as Spam)
  Future<void> trainAsSpam(EmailItem item) async {
    final fromAddr = item.fromEmail.toLowerCase().trim();
    final domain = item.senderBaseDomain;
    final messageId = item.messageId;

    // 1. Update classified.json immediately
    final classification = SpamClassification(
      verdict: 'spam',
      confidence: 1.0,
      category: 'user_spam',
      reason: 'Trained as Spam by user in email client',
      profileHits: ['User-flagged spam'],
    );
    item.classification = classification;
    item.isApproved = false;

    _classified[messageId] = classification.toJson(
      from: fromAddr,
      subject: item.subject,
    );
    _saveClassified();

    // 2. Remove from approved.json immediately if previously approved
    var approvedChanged = false;
    final senders = _approved['senders'] ?? [];
    if (senders.remove(fromAddr)) approvedChanged = true;
    final domains = _approved['domains'] ?? [];
    if (domains.remove(domain)) approvedChanged = true;
    if (approvedChanged) {
      _saveApproved();
    }

    // 3. Immediately increment repeat offenders in spam_profile.json
    _incrementSpamProfile(fromAddr, domain, item.subject);

    _lastStatusMessage = 'Trained as Spam: ${fromAddr.isNotEmpty ? fromAddr : item.subject}';

    // 4. Batch & debounce the heavy background learn command
    _scheduleBatchedLearn();
  }

  /// Batches changes and schedules retraining after inactivity or batch limit.
  void _scheduleBatchedLearn() {
    _pendingChangesCount++;

    if (_pendingChangesCount >= maxBatchBeforeForceLearn) {
      // Reached batch threshold: trigger immediately
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _scheduledLearnTime = null;
      _triggerBackgroundLearn();
    } else {
      // Reset debounce timer to wait for user to finish triaging
      _debounceTimer?.cancel();
      _scheduledLearnTime = DateTime.now().add(debounceDuration);
      _debounceTimer = Timer(debounceDuration, () {
        _triggerBackgroundLearn();
      });
    }

    onStateChanged?.call();
  }

  void _saveClassified() {
    try {
      classifiedFile.writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(_classified),
      );
    } catch (e) {
      stderr.writeln('Error saving classified.json: $e');
    }
  }

  void _saveApproved() {
    try {
      approvedFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_approved),
      );
    } catch (e) {
      stderr.writeln('Error saving approved.json: $e');
    }
  }

  void _saveProfile() {
    try {
      profileFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_profile),
      );
    } catch (e) {
      stderr.writeln('Error saving spam_profile.json: $e');
    }
  }

  void _decrementSpamProfile(String addr, String domain) {
    if (_profile.isEmpty) return;
    try {
      final senders = _profile['senders'];
      if (senders is List) {
        for (final entry in senders) {
          if (entry is Map && entry['value'] == addr) {
            final count = (entry['spam_count'] as num? ?? 1).toInt() - 1;
            entry['spam_count'] = count > 0 ? count : 0;
          }
        }
      }
      final inboxSamples = (_profile['inbox_samples'] as num? ?? 0).toInt() + 1;
      _profile['inbox_samples'] = inboxSamples;
      _saveProfile();
    } catch (_) {}
  }

  void _incrementSpamProfile(String addr, String domain, String subject) {
    if (_profile.isEmpty) return;
    try {
      final senders = _profile['senders'];
      if (senders is List && addr.isNotEmpty) {
        bool found = false;
        for (final entry in senders) {
          if (entry is Map && entry['value'] == addr) {
            entry['spam_count'] = ((entry['spam_count'] as num? ?? 0).toInt() + 1);
            entry['score'] = ((entry['score'] as num? ?? 1.0).toDouble() + 0.5);
            found = true;
            break;
          }
        }
        if (!found) {
          senders.insert(0, {'value': addr, 'spam_count': 1, 'score': 2.5});
        }
      }

      final domains = _profile['domains'];
      if (domains is List && domain.isNotEmpty) {
        bool found = false;
        for (final entry in domains) {
          if (entry is Map && entry['value'] == domain) {
            entry['spam_count'] = ((entry['spam_count'] as num? ?? 0).toInt() + 1);
            found = true;
            break;
          }
        }
        if (!found) {
          domains.insert(0, {'value': domain, 'spam_count': 1, 'score': 2.0});
        }
      }

      final spamSamples = (_profile['spam_samples'] as num? ?? 0).toInt() + 1;
      _profile['spam_samples'] = spamSamples;
      _saveProfile();
    } catch (_) {}
  }

  Future<void> _triggerBackgroundLearn() async {
    if (_isTraining) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _scheduledLearnTime = null;

    final batchSize = _pendingChangesCount;
    _isTraining = true;
    _lastStatusMessage = 'Retraining spam profile ($batchSize pending changes)...';
    onStateChanged?.call();

    try {
      final home = Platform.environment['HOME'] ?? '';
      final repoRoot = '$home/Work/imap-spam-filter';
      final cliPath = File('$repoRoot/imap-spam-filter');

      if (cliPath.existsSync() && account.name != 'Manual / Default') {
        Process.run(cliPath.path, ['learn', account.name]).then((res) {
          _isTraining = false;
          _pendingChangesCount = max(0, _pendingChangesCount - batchSize);
          _lastStatusMessage = 'Retrain completed for $batchSize changes';
          reloadFiles();
          onStateChanged?.call();
        }).catchError((err) {
          _isTraining = false;
          _lastStatusMessage = 'Retrain error: $err';
          onStateChanged?.call();
        });
      } else {
        _isTraining = false;
        _pendingChangesCount = max(0, _pendingChangesCount - batchSize);
        onStateChanged?.call();
      }
    } catch (e) {
      _isTraining = false;
      _lastStatusMessage = 'Retrain error: $e';
      onStateChanged?.call();
    }
  }

  /// Manually force a full profile learn right now
  Future<String> triggerFullLearnNow() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _scheduledLearnTime = null;

    _isTraining = true;
    _lastStatusMessage = 'Running manual profile learn...';
    onStateChanged?.call();

    try {
      final home = Platform.environment['HOME'] ?? '';
      final repoRoot = '$home/Work/imap-spam-filter';
      final cliPath = File('$repoRoot/imap-spam-filter');

      ProcessResult res;
      if (cliPath.existsSync() && account.name != 'Manual / Default') {
        res = await Process.run(cliPath.path, ['learn', account.name]);
      } else {
        final script = File('$repoRoot/spam_filter.py');
        final pw = account.getDecryptedPassword();
        res = await Process.run(
          'python3',
          [
            script.path,
            '--host', account.host,
            '--port', account.port.toString(),
            '--user', account.user,
            if (pw != null) ...['--password', pw],
            '--spam-folder', account.spamFolder,
            'learn',
          ],
          environment: {'SPAM_FILTER_DATA_DIR': account.dataDir},
        );
      }

      reloadFiles();
      _isTraining = false;
      _pendingChangesCount = 0;

      if (res.exitCode == 0) {
        _lastStatusMessage = 'Spam profile retrained successfully';
        onStateChanged?.call();
        return 'Success: ${res.stdout}';
      } else {
        _lastStatusMessage = 'Learn exited with code ${res.exitCode}';
        onStateChanged?.call();
        return 'Notice: ${res.stderr}\n${res.stdout}';
      }
    } catch (e) {
      _isTraining = false;
      _lastStatusMessage = 'Error running learn: $e';
      onStateChanged?.call();
      return 'Error: $e';
    }
  }

  /// Evaluates an email item against the retrained spam profile and approved whitelist.
  ProfileEvaluationResult evaluateEmail(EmailItem item) {
    final addr = item.fromEmail.toLowerCase().trim();
    final domain = item.senderBaseDomain.toLowerCase().trim();
    final name = item.fromName.trim().toLowerCase();
    final subject = item.subject;

    // 1. Check approved whitelist
    if (isSenderApproved(addr, domain: domain, subject: subject)) {
      final res = ProfileEvaluationResult(
        isApproved: true,
        isSpam: false,
        confidence: 1.0,
        category: 'approved',
        reason: 'Approved by whitelist rule',
        profileHits: [],
        score: 0.0,
      );
      item.isApproved = true;
      item.classification = SpamClassification(
        verdict: 'ham',
        confidence: 1.0,
        category: 'approved',
        reason: res.reason,
        profileHits: [],
      );
      return res;
    }

    // 2. Check profile hits
    final hits = <String>[];
    double totalScore = 0.0;

    final senders = _profile['senders'];
    if (senders is List && addr.isNotEmpty) {
      for (final s in senders) {
        if (s is Map && s['value']?.toString().toLowerCase() == addr) {
          final count = s['spam_count'] ?? 1;
          final score = (s['score'] as num? ?? 2.0).toDouble();
          hits.add('sender $addr appears ${count}x in Spam profile');
          totalScore += score;
          break;
        }
      }
    }

    final domains = _profile['domains'];
    if (domains is List && domain.isNotEmpty && !kFreemail.contains(domain)) {
      for (final d in domains) {
        if (d is Map && d['value']?.toString().toLowerCase() == domain) {
          final count = d['spam_count'] ?? 1;
          final score = (d['score'] as num? ?? 2.0).toDouble();
          hits.add('domain $domain appears ${count}x in Spam profile');
          totalScore += score;
          break;
        }
      }
    }

    final displayNames = _profile['display_names'];
    if (displayNames is List && name.isNotEmpty) {
      for (final n in displayNames) {
        if (n is Map && n['value']?.toString().toLowerCase() == name) {
          hits.add('display name "$name" is a repeat Spam sender name');
          totalScore += 1.5;
          break;
        }
      }
    }

    final subjectWords = _profile['subject_words'];
    if (subjectWords is List && subject.isNotEmpty) {
      final tokens = extractSubjectTokens(subject);
      final wordMap = <String, Map<String, dynamic>>{};
      for (final w in subjectWords) {
        if (w is Map && w['value'] != null) {
          wordMap[w['value'].toString().toLowerCase()] = Map<String, dynamic>.from(w);
        }
      }

      final matchedTokens = tokens.where((t) => wordMap.containsKey(t)).toList();
      if (matchedTokens.isNotEmpty) {
        matchedTokens.sort((a, b) {
          final scoreA = (wordMap[a]?['score'] as num? ?? 0.0).toDouble();
          final scoreB = (wordMap[b]?['score'] as num? ?? 0.0).toDouble();
          return scoreB.compareTo(scoreA);
        });

        hits.add('subject words common in Spam: ${matchedTokens.take(6).join(', ')}');
        final topWordScore = (wordMap[matchedTokens.first]?['score'] as num? ?? 1.5).toDouble();
        totalScore += topWordScore * 0.8;
      }
    }

    if (hits.isNotEmpty) {
      final confidence = (0.55 + (totalScore * 0.12)).clamp(0.65, 0.99);
      final res = ProfileEvaluationResult(
        isApproved: false,
        isSpam: true,
        confidence: confidence,
        category: 'profile_match',
        reason: hits.first,
        profileHits: hits,
        score: totalScore,
      );
      item.isApproved = false;
      item.classification = SpamClassification(
        verdict: 'spam',
        confidence: confidence,
        category: 'profile_match',
        reason: hits.first,
        profileHits: hits,
      );
      return res;
    }

    // 3. Clean / No spam signals found
    // If it had a prior classification from classified.json without profile hits, keep it or mark clean
    final prior = getClassification(item.messageId);
    if (prior != null && prior.category != 'profile_match') {
      item.isApproved = false;
      item.classification = prior;
      return ProfileEvaluationResult(
        isApproved: false,
        isSpam: prior.isSpam,
        confidence: prior.confidence,
        category: prior.category,
        reason: prior.reason,
        profileHits: prior.profileHits,
        score: 0.0,
      );
    }

    final res = ProfileEvaluationResult(
      isApproved: false,
      isSpam: false,
      confidence: 0.90,
      category: 'clean',
      reason: 'No spam profile signals matched',
      profileHits: [],
      score: 0.0,
    );
    item.isApproved = false;
    item.classification = SpamClassification(
      verdict: 'ham',
      confidence: 0.90,
      category: 'clean',
      reason: 'No spam profile signals matched',
      profileHits: [],
    );
    return res;
  }

  /// Extracts meaningful subject tokens excluding stopwords and punctuation.
  static Set<String> extractSubjectTokens(String subject) {
    final regExp = RegExp(r"[^\W\d_][\w'$€%!-]{2,}");
    final matches = regExp.allMatches(subject.toLowerCase());
    final tokens = <String>{};
    for (final m in matches) {
      final raw = m.group(0)!;
      final cleaned = raw.replaceAll(RegExp(r"^['-]+|['-]+$"), '');
      if (cleaned.length >= 2 && !kStopwords.contains(cleaned)) {
        tokens.add(cleaned);
      }
    }
    return tokens;
  }

  static const Set<String> kStopwords = {
    'the', 'and', 'for', 'you', 'your', 'are', 'with', 'this', 'that', 'from',
    'have', 'has', 'was', 'were', 'will', 'our', 'not', 'but', 'can', 'all',
    'any', 'out', 'get', 'new', 'now', 'just', 'more', 'one', 'its', "it's",
    'off', 'per', 'via', 'who', 'how', 'what', 'when', 'why', 'here', 'there',
    'their', 'they', 'them', 'his', 'her', 'him', 'she', 'been', 'than', 'then',
    'into', 'about', 'over', 'only', 'also', 're', 'fw', 'fwd',
  };

  static const Set<String> kFreemail = {
    'gmail.com', 'googlemail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
    'live.com', 'icloud.com', 'me.com', 'aol.com', 'proton.me',
    'protonmail.com', 'gmx.com', 'mail.com', 'yandex.com',
  };
}

class ProfileEvaluationResult {
  final bool isApproved;
  final bool isSpam;
  final double confidence;
  final String category;
  final String reason;
  final List<String> profileHits;
  final double score;

  ProfileEvaluationResult({
    required this.isApproved,
    required this.isSpam,
    required this.confidence,
    required this.category,
    required this.reason,
    required this.profileHits,
    required this.score,
  });
}
