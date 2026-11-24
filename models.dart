import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;

/// One piece of learning content (PDF, video, image, note, link…).
/// Stored in Firestore `content/{id}`; admins add these at runtime.
class ContentItem {
  final String id, title, titleBn, section, group, category, kind;
  final String url, storagePath, thumbnailUrl, description, body;
  final bool isPremium;
  final int sortOrder, sizeBytes;
  final DateTime? createdAt;

  const ContentItem({
    required this.id,
    required this.title,
    this.titleBn = '',
    required this.section,
    this.group = 'all',
    required this.category,
    required this.kind,
    this.url = '',
    this.storagePath = '',
    this.thumbnailUrl = '',
    this.description = '',
    this.body = '',
    this.isPremium = false,
    this.sortOrder = 0,
    this.sizeBytes = 0,
    this.createdAt,
  });

  factory ContentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ContentItem(
      id: d.id,
      title: m['title'] ?? '',
      titleBn: m['titleBn'] ?? '',
      section: m['section'] ?? '',
      group: m['group'] ?? 'all',
      category: m['category'] ?? '',
      kind: m['kind'] ?? 'pdf',
      url: m['url'] ?? '',
      storagePath: m['storagePath'] ?? '',
      thumbnailUrl: m['thumbnailUrl'] ?? '',
      description: m['description'] ?? '',
      body: m['body'] ?? '',
      isPremium: m['isPremium'] ?? false,
      sortOrder: (m['sortOrder'] ?? 0) as int,
      sizeBytes: (m['sizeBytes'] ?? 0) as int,
      createdAt: _ts(m['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'titleBn': titleBn,
        'section': section,
        'group': group,
        'category': category,
        'kind': kind,
        'url': url,
        'storagePath': storagePath,
        'thumbnailUrl': thumbnailUrl,
        'description': description,
        'body': body,
        'isPremium': isPremium,
        'sortOrder': sortOrder,
        'sizeBytes': sizeBytes,
        'searchKeywords': keywords(title, titleBn),
      };

  /// Lower-case tokens used for Firestore `array-contains` search.
  static List<String> keywords(String a, String b) {
    final out = <String>{};
    for (final w in '$a $b'.toLowerCase().split(RegExp(r'[\s\-_,.()]+'))) {
      if (w.length < 2) continue;
      for (var i = 2; i <= w.length && i <= 12; i++) {
        out.add(w.substring(0, i));
      }
    }
    return out.toList();
  }

  String displayTitle(String lang) => (lang == 'bn' && titleBn.isNotEmpty) ? titleBn : title;

  bool get isYoutube => kind == 'youtube' || url.contains('youtube.com') || url.contains('youtu.be');

  String get fileExt {
    switch (kind) {
      case 'pdf':
        return 'pdf';
      case 'image':
        return 'jpg';
      case 'video':
        return 'mp4';
      default:
        return 'bin';
    }
  }

  bool get downloadable => (kind == 'pdf' || kind == 'image' || kind == 'video') && url.isNotEmpty;

  Map<String, dynamic> toJson() => {...toMap()..remove('searchKeywords'), 'id': id};

  factory ContentItem.fromJson(Map<String, dynamic> m) => ContentItem(
        id: m['id'],
        title: m['title'] ?? '',
        titleBn: m['titleBn'] ?? '',
        section: m['section'] ?? '',
        group: m['group'] ?? 'all',
        category: m['category'] ?? '',
        kind: m['kind'] ?? 'pdf',
        url: m['url'] ?? '',
        thumbnailUrl: m['thumbnailUrl'] ?? '',
        isPremium: m['isPremium'] ?? false,
      );
}

class AppUser {
  final String uid, name, email, photoUrl, role;
  final bool isPremiumFlag, isGuest, banned;
  final DateTime? premiumUntil;

  const AppUser({
    required this.uid,
    this.name = '',
    this.email = '',
    this.photoUrl = '',
    this.role = 'student',
    this.isPremiumFlag = false,
    this.isGuest = false,
    this.banned = false,
    this.premiumUntil,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      uid: d.id,
      name: m['name'] ?? '',
      email: m['email'] ?? '',
      photoUrl: m['photoUrl'] ?? '',
      role: m['role'] ?? 'student',
      isPremiumFlag: m['isPremium'] ?? false,
      isGuest: m['isGuest'] ?? false,
      banned: m['banned'] ?? false,
      premiumUntil: _ts(m['premiumUntil']),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isPremium => isPremiumFlag && (premiumUntil == null || premiumUntil!.isAfter(DateTime.now()));
}

class Question {
  final String text;
  final List<String> options;
  final int answerIndex; // -1 for written questions
  final String explanation;
  const Question({required this.text, this.options = const [], this.answerIndex = -1, this.explanation = ''});

  factory Question.fromMap(Map<String, dynamic> m) => Question(
        text: m['q'] ?? '',
        options: List<String>.from(m['options'] ?? const []),
        answerIndex: (m['answer'] ?? -1) as int,
        explanation: m['explanation'] ?? '',
      );

  Map<String, dynamic> toMap() => {'q': text, 'options': options, 'answer': answerIndex, 'explanation': explanation};
}

class Exam {
  final String id, title, section, group, type; // type: mcq | written
  final int durationMin;
  final double negativeMark;
  final bool isPremium;
  final String courseId;
  final List<Question> questions;

  const Exam({
    required this.id,
    required this.title,
    this.section = 'academic',
    this.group = 'all',
    this.type = 'mcq',
    this.durationMin = 20,
    this.negativeMark = 0,
    this.isPremium = false,
    this.courseId = '',
    this.questions = const [],
  });

  factory Exam.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Exam(
      id: d.id,
      title: m['title'] ?? '',
      section: m['section'] ?? 'academic',
      group: m['group'] ?? 'all',
      type: m['type'] ?? 'mcq',
      durationMin: (m['durationMin'] ?? 20) as int,
      negativeMark: ((m['negativeMark'] ?? 0) as num).toDouble(),
      isPremium: m['isPremium'] ?? false,
      courseId: m['courseId'] ?? '',
      questions: ((m['questions'] ?? []) as List).map((e) => Question.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }
}

class ExamResult {
  final String id, examId, examTitle, uid, userName, section, status;
  final double score;
  final int total, correct, wrong, skipped, seconds;
  final DateTime? createdAt;

  const ExamResult({
    required this.id,
    required this.examId,
    this.examTitle = '',
    required this.uid,
    this.userName = '',
    this.section = '',
    this.status = 'graded',
    this.score = 0,
    this.total = 0,
    this.correct = 0,
    this.wrong = 0,
    this.skipped = 0,
    this.seconds = 0,
    this.createdAt,
  });

  factory ExamResult.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return ExamResult(
      id: d.id,
      examId: m['examId'] ?? '',
      examTitle: m['examTitle'] ?? '',
      uid: m['uid'] ?? '',
      userName: m['userName'] ?? '',
      section: m['section'] ?? '',
      status: m['status'] ?? 'graded',
      score: ((m['score'] ?? 0) as num).toDouble(),
      total: (m['total'] ?? 0) as int,
      correct: (m['correct'] ?? 0) as int,
      wrong: (m['wrong'] ?? 0) as int,
      skipped: (m['skipped'] ?? 0) as int,
      seconds: (m['seconds'] ?? 0) as int,
      createdAt: _ts(m['createdAt']),
    );
  }

  double get percent => total == 0 ? 0 : (score / total * 100).clamp(0, 100).toDouble();
}
