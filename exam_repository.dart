import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';

class ExamRepository {
  ExamRepository(this._db);
  final FirebaseFirestore _db;

  Stream<List<Exam>> watchExams() => _db
      .collection('exams')
      .where('published', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(Exam.fromDoc).toList()..sort((a, b) => a.title.compareTo(b.title)));

  Future<Exam?> getExam(String id) async {
    final d = await _db.collection('exams').doc(id).get();
    return d.exists ? Exam.fromDoc(d) : null;
  }

  /// MCQ scoring: +1 correct, -negativeMark wrong, 0 skipped.
  ExamResult grade(Exam exam, List<int?> picked, {required String uid, required String userName, required int seconds}) {
    var correct = 0, wrong = 0, skipped = 0;
    for (var i = 0; i < exam.questions.length; i++) {
      final p = picked[i];
      if (p == null) {
        skipped++;
      } else if (p == exam.questions[i].answerIndex) {
        correct++;
      } else {
        wrong++;
      }
    }
    final score = (correct - wrong * exam.negativeMark).clamp(0, exam.questions.length).toDouble();
    return ExamResult(
      id: '',
      examId: exam.id,
      examTitle: exam.title,
      uid: uid,
      userName: userName,
      section: exam.section,
      score: score,
      total: exam.questions.length,
      correct: correct,
      wrong: wrong,
      skipped: skipped,
      seconds: seconds,
    );
  }

  Future<String> saveResult(ExamResult r, {List<String>? writtenAnswers}) async {
    final ref = await _db.collection('results').add({
      'examId': r.examId,
      'examTitle': r.examTitle,
      'uid': r.uid,
      'userName': r.userName,
      'section': r.section,
      'status': writtenAnswers != null ? 'pending' : 'graded',
      'score': r.score,
      'total': r.total,
      'correct': r.correct,
      'wrong': r.wrong,
      'skipped': r.skipped,
      'seconds': r.seconds,
      if (writtenAnswers != null) 'answers': writtenAnswers,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Rank = number of results with a higher score on the same exam + 1.
  Future<int> rankOf(String examId, double score) async {
    final c = await _db
        .collection('results')
        .where('examId', isEqualTo: examId)
        .where('status', isEqualTo: 'graded')
        .where('score', isGreaterThan: score)
        .count()
        .get();
    return (c.count ?? 0) + 1;
  }

  Stream<List<ExamResult>> leaderboard(String examId) => _db
      .collection('results')
      .where('examId', isEqualTo: examId)
      .where('status', isEqualTo: 'graded')
      .orderBy('score', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(ExamResult.fromDoc).toList());

  Stream<List<ExamResult>> myResults(String uid) => _db
      .collection('results')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(ExamResult.fromDoc).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(2000)).compareTo(b.createdAt ?? DateTime(2000))));

  // ---- Admin ----
  Future<void> createExam(Map<String, dynamic> m) => _db.collection('exams').add({...m, 'createdAt': FieldValue.serverTimestamp()});
  Future<void> deleteExam(String id) => _db.collection('exams').doc(id).delete();
}
