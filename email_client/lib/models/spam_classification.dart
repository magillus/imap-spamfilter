import 'package:crypto/crypto.dart';
import 'dart:convert';

class SpamClassification {
  final String verdict; // 'spam' or 'ham'
  final double confidence;
  final String category;
  final String reason;
  final List<String> profileHits;
  final String? ref;

  SpamClassification({
    required this.verdict,
    required this.confidence,
    required this.category,
    required this.reason,
    this.profileHits = const [],
    this.ref,
  });

  bool get isSpam => verdict == 'spam';
  bool get isHam => verdict == 'ham';
  bool get isApproved => category == 'approved';

  factory SpamClassification.fromJson(Map<String, dynamic> json, {String? messageId}) {
    String? ref = json['ref'] as String?;
    if (ref == null && messageId != null && messageId.isNotEmpty) {
      ref = sha1.convert(utf8.encode(messageId)).toString().substring(0, 6);
    }

    final hitsRaw = json['profile_hits'];
    List<String> hits = [];
    if (hitsRaw is List) {
      hits = hitsRaw.map((e) => e.toString()).toList();
    }

    return SpamClassification(
      verdict: (json['verdict'] as String?) ?? 'ham',
      confidence: (json['confidence'] is num) ? (json['confidence'] as num).toDouble() : 0.5,
      category: (json['category'] as String?) ?? 'unknown',
      reason: (json['reason'] as String?) ?? '',
      profileHits: hits,
      ref: ref,
    );
  }

  Map<String, dynamic> toJson({String? from, String? subject}) {
    final map = <String, dynamic>{
      'verdict': verdict,
      'confidence': confidence,
      'category': category,
      'reason': reason,
    };
    if (profileHits.isNotEmpty) map['profile_hits'] = profileHits;
    if (from != null) map['from'] = from;
    if (subject != null) map['subject'] = subject;
    return map;
  }
}
