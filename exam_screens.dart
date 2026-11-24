import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/services/ads_service.dart';
import '../../core/services/certificate_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';

final examsProvider = StreamProvider.autoDispose<List<Exam>>((ref) => ref.watch(examRepoProvider).watchExams());
final leaderboardProvider = StreamProvider.autoDispose.family<List<ExamResult>, String>((ref, id) => ref.watch(examRepoProvider).leaderboard(id));
final myResultsProvider = StreamProvider.autoDispose<List<ExamResult>>((ref) {
  final u = ref.watch(authStateProvider).valueOrNull;
  if (u == null) return const Stream.empty();
  return ref.watch(examRepoProvider).myResults(u.uid);
});

// ---------------------------------------------------------------------------
// Exam list (bottom-nav tab)
// ---------------------------------------------------------------------------
class ExamListTab extends ConsumerWidget {
  const ExamListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(isPremiumProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('exams')), actions: [
        IconButton(icon: const Icon(Icons.insights), onPressed: () => context.push('/analysis')),
      ]),
      body: AsyncView<List<Exam>>(
        value: ref.watch(examsProvider),
        builder: (exams) {
          if (exams.isEmpty) return const EmptyState(icon: Icons.quiz);
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = exams[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(e.type == 'written' ? Icons.edit_note : Icons.checklist)),
                  title: Text(e.title),
                  subtitle: Text('${e.questions.length} Q · ${e.durationMin} min${e.negativeMark > 0 ? ' · −${e.negativeMark}' : ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (e.isPremium && !premium) const Icon(Icons.lock, size: 18),
                    IconButton(icon: const Icon(Icons.leaderboard), onPressed: () => context.push('/leaderboard/${e.id}')),
                  ]),
                  onTap: () {
                    if (e.isPremium && !premium) {
                      context.push('/premium');
                    } else {
                      context.push('/exam/${e.id}');
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Taking an exam: timer, auto-submit, MCQ + written
// ---------------------------------------------------------------------------
class ResultArgs {
  final Exam exam;
  final ExamResult result;
  final List<int?> picked;
  final int rank;
  const ResultArgs(this.exam, this.result, this.picked, this.rank);
}

class ExamScreen extends ConsumerStatefulWidget {
  const ExamScreen({super.key, required this.examId});
  final String examId;
  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  Exam? _exam;
  List<int?> _picked = [];
  List<TextEditingController> _written = [];
  int _left = 0, _index = 0;
  Timer? _timer;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await ref.read(examRepoProvider).getExam(widget.examId);
      if (e == null) throw 'Exam not found';
      if (!mounted) return;
      setState(() {
        _exam = e;
        _picked = List.filled(e.questions.length, null);
        _written = List.generate(e.questions.length, (_) => TextEditingController());
        _left = e.durationMin * 60;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_left <= 1) {
          t.cancel();
          _submit(auto: true);
        } else {
          setState(() => _left--);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _written) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting || _exam == null) return;
    if (!auto) {
      final answered = _exam!.type == 'written' ? _written.where((c) => c.text.trim().isNotEmpty).length : _picked.where((p) => p != null).length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('submit')),
          content: Text('Answered $answered of ${_exam!.questions.length}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(100, 40)), child: Text(ctx.tr('submit'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _submitting = true;
    _timer?.cancel();
    final user = ref.read(appUserProvider).valueOrNull;
    final uid = ref.read(authStateProvider).valueOrNull!.uid;
    final repo = ref.read(examRepoProvider);
    final exam = _exam!;
    final seconds = exam.durationMin * 60 - _left;
    try {
      final isWritten = exam.type == 'written';
      var r = repo.grade(exam, _picked, uid: uid, userName: user?.name ?? '', seconds: seconds);
      if (isWritten) {
        r = ExamResult(id: '', examId: exam.id, examTitle: exam.title, uid: uid, userName: user?.name ?? '', section: exam.section, status: 'pending', total: exam.questions.length, seconds: seconds);
      }
      final id = await repo.saveResult(r, writtenAnswers: isWritten ? _written.map((c) => c.text.trim()).toList() : null);
      final rank = isWritten ? 0 : await repo.rankOf(exam.id, r.score);
      ref.read(contentRepoProvider).bumpStat('exams');
      if (!mounted) return;
      AdsService.instance.maybeShowInterstitial();
      context.pushReplacement('/result', extra: ResultArgs(exam, ExamResult(id: id, examId: r.examId, examTitle: r.examTitle, uid: uid, userName: r.userName, status: r.status, score: r.score, total: r.total, correct: r.correct, wrong: r.wrong, skipped: r.skipped, seconds: r.seconds), _picked, rank));
    } catch (e) {
      _submitting = false;
      if (mounted) snack(context, 'Submit failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    final e = _exam;
    if (e == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final q = e.questions[_index];
    final low = _left < 60;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave exam?'),
            content: const Text('Your progress will be lost.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave'))],
          ),
        );
        if (leave == true && context.mounted) {
          _timer?.cancel();
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_index + 1} / ${e.questions.length}'),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: low ? Colors.red.withValues(alpha: 0.15) : Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [Icon(Icons.timer, size: 16, color: low ? Colors.red : null), const SizedBox(width: 4), Text(Formatters.mmss(_left), style: TextStyle(fontWeight: FontWeight.bold, color: low ? Colors.red : null))]),
            ),
          ],
        ),
        body: Column(children: [
          LinearProgressIndicator(value: (_index + 1) / e.questions.length),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(q.text, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.4)),
              const SizedBox(height: 16),
              if (e.type == 'written')
                TextField(controller: _written[_index], minLines: 6, maxLines: 14, decoration: const InputDecoration(hintText: 'Write your answer…'))
              else
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: _picked[_index] == i ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: ListTile(
                        leading: CircleAvatar(radius: 14, child: Text(String.fromCharCode(65 + i))),
                        title: Text(q.options[i]),
                        onTap: () => setState(() => _picked[_index] = _picked[_index] == i ? null : i),
                      ),
                    ),
                  ),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                IconButton.filledTonal(onPressed: _index > 0 ? () => setState(() => _index--) : null, icon: const Icon(Icons.chevron_left)),
                const SizedBox(width: 12),
                Expanded(
                  child: _index == e.questions.length - 1
                      ? FilledButton(onPressed: _submitting ? null : () => _submit(), child: Text(context.tr('submit')))
                      : OutlinedButton(onPressed: () => _submit(), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(context.tr('submit'))),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(onPressed: _index < e.questions.length - 1 ? () => setState(() => _index++) : null, icon: const Icon(Icons.chevron_right)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result + answer review + certificate
// ---------------------------------------------------------------------------
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.args});
  final ResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = args.result;
    final pending = r.status == 'pending';
    final cs = Theme.of(context).colorScheme;
    final passed = !pending && r.percent >= 60;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('result')), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(args.exam.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (pending)
                const Text('Submitted. A teacher will grade your written answers.', textAlign: TextAlign.center)
              else ...[
                Text('${Formatters.score(r.score)} / ${r.total}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('${r.percent.toStringAsFixed(1)}%'),
                const SizedBox(height: 8),
                Text('Rank #${args.rank}'),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (!pending)
          Row(children: [
            _Stat('Correct', '${r.correct}', Colors.green),
            _Stat('Wrong', '${r.wrong}', Colors.red),
            _Stat('Skipped', '${r.skipped}', Colors.orange),
            _Stat('Time', '${r.seconds ~/ 60}m ${r.seconds % 60}s', cs.primary),
          ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/leaderboard/${r.examId}'), icon: const Icon(Icons.leaderboard), label: Text(context.tr('leaderboard')))),
          if (passed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final user = ref.read(appUserProvider).valueOrNull;
                  final bytes = await CertificateService.build(name: user?.name.isNotEmpty == true ? user!.name : 'Student', exam: args.exam.title, percent: r.percent);
                  await Printing.sharePdf(bytes: bytes, filename: 'StudyBD_Certificate.pdf');
                },
                icon: const Icon(Icons.workspace_premium),
                label: Text(context.tr('certificate')),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        if (!pending && args.exam.type == 'mcq') ...[
          Text('Review', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < args.exam.questions.length; i++) _ReviewTile(i: i, q: args.exam.questions[i], picked: args.picked[i]),
        ],
        const BannerAdWidget(),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(children: [Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)), Text(label, style: Theme.of(context).textTheme.labelSmall)]))),
      );
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.i, required this.q, required this.picked});
  final int i;
  final Question q;
  final int? picked;
  @override
  Widget build(BuildContext context) {
    final ok = picked == q.answerIndex;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(picked == null ? Icons.remove_circle_outline : (ok ? Icons.check_circle : Icons.cancel), color: picked == null ? Colors.orange : (ok ? Colors.green : Colors.red)),
        title: Text('${i + 1}. ${q.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (picked != null && !ok) Text('Your answer: ${q.options[picked!]}', style: const TextStyle(color: Colors.red)),
          Text('Correct: ${q.options[q.answerIndex]}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
          if (q.explanation.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(q.explanation)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leaderboard
// ---------------------------------------------------------------------------
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key, required this.examId});
  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authStateProvider).valueOrNull?.uid;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('leaderboard'))),
      body: AsyncView<List<ExamResult>>(
        value: ref.watch(leaderboardProvider(examId)),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.leaderboard)
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: r.uid == me ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: i < 3 ? [Colors.amber, Colors.blueGrey.shade300, Colors.brown.shade300][i] : null, child: Text('${i + 1}')),
                      title: Text(r.userName.isEmpty ? 'Student' : r.userName),
                      subtitle: Text('${r.seconds ~/ 60}m ${r.seconds % 60}s'),
                      trailing: Text('${Formatters.score(r.score)}/${r.total}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score history + performance analysis
// ---------------------------------------------------------------------------
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.lang == 'bn' ? 'পারফরম্যান্স বিশ্লেষণ' : 'Performance Analysis')),
      body: AsyncView<List<ExamResult>>(
        value: ref.watch(myResultsProvider),
        builder: (all) {
          final list = all.where((r) => r.status == 'graded' && r.total > 0).toList();
          if (list.isEmpty) return const EmptyState(icon: Icons.insights);
          final avg = list.map((r) => r.percent).reduce((a, b) => a + b) / list.length;
          final best = list.map((r) => r.percent).reduce((a, b) => a > b ? a : b);
          final bySection = <String, List<double>>{};
          for (final r in list) {
            bySection.putIfAbsent(r.section.isEmpty ? 'other' : r.section, () => []).add(r.percent);
          }
          final spots = [for (var i = 0; i < list.length; i++) FlSpot(i.toDouble(), list[i].percent)];

          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              _Stat('Exams', '${list.length}', Theme.of(context).colorScheme.primary),
              _Stat('Average', '${avg.toStringAsFixed(1)}%', Colors.blue),
              _Stat('Best', '${best.toStringAsFixed(0)}%', Colors.green),
            ]),
            const SizedBox(height: 16),
            Text('Score trend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: 100,
                gridData: const FlGridData(drawVerticalLine: false),
                titlesData: const FlTitlesData(topTitles: AxisTitles(), rightTitles: AxisTitles(), bottomTitles: AxisTitles()),
                borderData: FlBorderData(show: false),
                lineBarData: [LineChartBarData(spots: spots, isCurved: true, barWidth: 3, color: Theme.of(context).colorScheme.primary, belowBarData: BarAreaData(show: true, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)))],
              )),
            ),
            const SizedBox(height: 16),
            Text('By section', style: Theme.of(context).textTheme.titleMedium),
            for (final e in bySection.entries)
              ListTile(
                title: Text(e.key),
                subtitle: LinearProgressIndicator(value: (e.value.reduce((a, b) => a + b) / e.value.length) / 100, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                trailing: Text('${(e.value.reduce((a, b) => a + b) / e.value.length).toStringAsFixed(0)}%'),
              ),
            const SizedBox(height: 8),
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            for (final r in list.reversed)
              ListTile(dense: true, title: Text(r.examTitle), subtitle: Text(r.createdAt?.toString().substring(0, 16) ?? ''), trailing: Text('${r.percent.toStringAsFixed(0)}%')),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily quiz: 5 random questions from Firestore `quizBank`
// ---------------------------------------------------------------------------
final dailyQuizProvider = FutureProvider.autoDispose<List<Question>>((ref) async {
  final snap = await ref.watch(contentRepoProvider).quizBank();
  final now = DateTime.now();
  final seed = now.year * 10000 + now.month * 100 + now.day;
  // Same 5 questions for everyone on a given day.
  snap.shuffle(Random(seed));
  return snap.take(5).toList();
});

class DailyQuizScreen extends ConsumerStatefulWidget {
  const DailyQuizScreen({super.key});
  @override
  ConsumerState<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends ConsumerState<DailyQuizScreen> {
  final Map<int, int> _picked = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('dailyQuiz'))),
      body: AsyncView<List<Question>>(
        value: ref.watch(dailyQuizProvider),
        builder: (qs) {
          if (qs.isEmpty) return const EmptyState(icon: Icons.bolt);
          final done = _picked.length == qs.length;
          final score = _picked.entries.where((e) => qs[e.key].answerIndex == e.value).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (done) Card(color: Theme.of(context).colorScheme.primaryContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text('Score: $score / ${qs.length}', style: Theme.of(context).textTheme.titleLarge))),
            for (var i = 0; i < qs.length; i++) ...[
              const SizedBox(height: 12),
              Text('${i + 1}. ${qs[i].text}', style: Theme.of(context).textTheme.titleSmall),
              for (var o = 0; o < qs[i].options.length; o++)
                ListTile(
                  dense: true,
                  title: Text(qs[i].options[o]),
                  tileColor: _picked.containsKey(i) ? (o == qs[i].answerIndex ? Colors.green.withValues(alpha: 0.2) : (_picked[i] == o ? Colors.red.withValues(alpha: 0.2) : null)) : null,
                  onTap: _picked.containsKey(i) ? null : () => setState(() => _picked[i] = o),
                ),
              if (_picked.containsKey(i) && qs[i].explanation.isNotEmpty) Text(qs[i].explanation, style: Theme.of(context).textTheme.bodySmall),
            ],
          ]);
        },
      ),
    );
  }
}
