import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/sections.dart';
import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../content/content_screens.dart';

final _db = FirebaseFirestore.instance;

/// Parses "Question|A|B|C|D|B|Explanation" lines (answer is A–D).
List<Question> parseMcqBulk(String s) {
  final out = <Question>[];
  for (final line in s.split('\n')) {
    final p = line.split('|').map((e) => e.trim()).toList();
    if (p.length < 6) continue;
    final idx = 'ABCD'.indexOf(p[5].toUpperCase());
    if (idx < 0) continue;
    out.add(Question(text: p[0], options: p.sublist(1, 5), answerIndex: idx, explanation: p.length > 6 ? p[6] : ''));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Admin home: dashboard + tools
// ---------------------------------------------------------------------------
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = <(IconData, String, String)>[
      (Icons.upload_file, 'Upload content', 'upload'),
      (Icons.folder_open, 'Manage content', 'content'),
      (Icons.quiz, 'Create exam', 'exam'),
      (Icons.school, 'Courses', 'course'),
      (Icons.live_tv, 'Live classes', 'live'),
      (Icons.notifications_active, 'Notifications', 'notify'),
      (Icons.people, 'Users', 'users'),
      (Icons.payments, 'Payments', 'payments'),
      (Icons.category, 'Categories', 'categories'),
      (Icons.dataset, 'Quiz & vocab import', 'bulk'),
      (Icons.ads_click, 'Ads & settings', 'config'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Admin panel')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const _Dashboard(),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: [for (final t in tools) FeatureTile(icon: t.$1, label: t.$2, color: Theme.of(context).colorScheme.primary, onTap: () => context.push('/admin/${t.$3}'))],
        ),
      ]),
    );
  }
}

class _DashData {
  int users = 0, active = 0, results = 0, payments = 0;
  double revenue = 0;
  List<int> visits = [], opens = [], downloads = [];
  List<String> labels = [];
}

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<_DashData> _f = _load();

  Future<_DashData> _load() async {
    final d = _DashData();
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    d.users = (await _db.collection('users').count().get()).count ?? 0;
    d.active = (await _db.collection('users').where('lastActiveAt', isGreaterThan: since).count().get()).count ?? 0;
    d.results = (await _db.collection('results').count().get()).count ?? 0;
    final rev = await _db.collection('payments').where('status', isEqualTo: 'approved').aggregate(sum('amount'), count()).get();
    d.revenue = rev.getSum('amount') ?? 0;
    d.payments = rev.count ?? 0;
    final days = List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
    final docs = await Future.wait(days.map((x) => _db.collection('stats').doc('daily_${DateFormat('yyyyMMdd').format(x)}').get()));
    int v(DocumentSnapshot<Map<String, dynamic>> s, String k) => ((s.data()?[k]) ?? 0) as int;
    d.visits = docs.map((s) => v(s, 'visits')).toList();
    d.opens = docs.map((s) => v(s, 'opens')).toList();
    d.downloads = docs.map((s) => v(s, 'downloads')).toList();
    d.labels = days.map((x) => DateFormat('E').format(x)).toList();
    return d;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashData>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Text('Dashboard error: ${snap.error}');
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final d = snap.data!;
        Widget stat(String l, String v, IconData i) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(i, size: 20), const SizedBox(height: 4), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text(l, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center)]))));
        return Column(children: [
          Row(children: [stat('Total users', '${d.users}', Icons.people), const SizedBox(width: 8), stat('Active (7d)', '${d.active}', Icons.bolt), const SizedBox(width: 8), stat('Today visits', '${d.visits.last}', Icons.today)]),
          const SizedBox(height: 8),
          Row(children: [stat('Exams taken', '${d.results}', Icons.quiz), const SizedBox(width: 8), stat('Revenue ৳', d.revenue.toStringAsFixed(0), Icons.payments), const SizedBox(width: 8), stat('Downloads (7d)', '${d.downloads.fold<int>(0, (a, b) => a + b)}', Icons.download)]),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: Text('Daily visitors (last 7 days)', style: Theme.of(context).textTheme.titleSmall)),
          SizedBox(
            height: 140,
            child: BarChart(BarChartData(
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(drawVerticalLine: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(d.labels[v.toInt()], style: const TextStyle(fontSize: 10)))),
              ),
              barGroups: [for (var i = 0; i < d.visits.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: d.visits[i].toDouble(), width: 16, color: Theme.of(context).colorScheme.primary)])],
            )),
          ),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => setState(() => _f = _load()), icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Router host
// ---------------------------------------------------------------------------
class AdminPageHost extends StatelessWidget {
  const AdminPageHost({super.key, required this.page});
  final String page;
  @override
  Widget build(BuildContext context) => switch (page) {
        'upload' => const UploadContentScreen(),
        'content' => const ManageContentScreen(),
        'exam' => const CreateExamScreen(),
        'course' => const CourseAdminScreen(),
        'live' => const LiveAdminScreen(),
        'notify' => const SendNotificationScreen(),
        'users' => const ManageUsersScreen(),
        'payments' => const PaymentsAdminScreen(),
        'categories' => const CategoriesAdminScreen(),
        'bulk' => const BulkImportScreen(),
        'config' => const ConfigScreen(),
        _ => const Scaffold(body: EmptyState()),
      };
}

Map<String, String> _sectionItems() => {for (final s in Sections.all) s.id: s.en};

Map<String, String> _groupItems(String section) {
  final s = Sections.byId(section);
  return s.hasGroups ? {for (final g in s.groups) g.id: g.en} : {'all': 'All'};
}

// ---------------------------------------------------------------------------
// Upload content (supports multi-file; new content appears instantly in the app)
// ---------------------------------------------------------------------------
class UploadContentScreen extends ConsumerStatefulWidget {
  const UploadContentScreen({super.key});
  @override
  ConsumerState<UploadContentScreen> createState() => _UploadContentScreenState();
}

class _UploadContentScreenState extends ConsumerState<UploadContentScreen> {
  String _section = 'academic', _group = '1', _category = 'nctb', _kind = 'pdf';
  bool _premium = false, _busy = false;
  final _title = TextEditingController(), _titleBn = TextEditingController(), _desc = TextEditingController(), _url = TextEditingController(), _body = TextEditingController();
  List<PlatformFile> _files = [];
  double _progress = 0;
  String _status = '';

  Map<String, String> _catItems() {
    final custom = ref.read(customCatsProvider(_section)).valueOrNull ?? [];
    return {for (final c in Sections.byId(_section).cats) c.id: c.en, for (final c in custom) c['id'] as String: '${c['nameEn']} (custom)'};
  }

  Future<void> _pick() async {
    final type = _kind == 'pdf' ? FileType.custom : (_kind == 'image' ? FileType.image : FileType.video);
    final r = await FilePicker.platform.pickFiles(type: type, allowedExtensions: _kind == 'pdf' ? ['pdf'] : null, allowMultiple: true);
    if (r != null) setState(() => _files = r.files.where((f) => f.path != null).toList());
  }

  Future<void> _save() async {
    final needsFile = ['pdf', 'image'].contains(_kind) || (_kind == 'video' && _url.text.trim().isEmpty);
    if (needsFile && _files.isEmpty && _url.text.trim().isEmpty) return snack(context, 'Pick a file or paste a URL');
    if (_files.isEmpty && _title.text.trim().isEmpty) return snack(context, 'Title required');
    if (_url.text.trim().isNotEmpty && !Validators.isHttpUrl(_url.text)) return snack(context, 'Enter a valid http(s) URL');
    setState(() => _busy = true);
    final repo = ref.read(contentRepoProvider);
    try {
      final jobs = _files.isEmpty ? [null] : _files;
      for (var i = 0; i < jobs.length; i++) {
        final f = jobs[i];
        var url = _url.text.trim(), path = '';
        var size = 0;
        if (f != null) {
          setState(() => _status = 'Uploading ${i + 1}/${jobs.length}: ${f.name}');
          final res = await repo.upload(File(f.path!), 'content/$_section/$_group/$_category', f.name, onProgress: (p) => setState(() => _progress = p));
          url = res.$1;
          path = res.$2;
          size = res.$3;
        }
        final title = (jobs.length == 1 && _title.text.trim().isNotEmpty) ? _title.text.trim() : (f?.name.replaceAll(RegExp(r'\.[^.]+$'), '') ?? _title.text.trim());
        await repo.add(ContentItem(id: '', title: title, titleBn: jobs.length == 1 ? _titleBn.text.trim() : '', section: _section, group: _group, category: _category, kind: _kind, url: url, storagePath: path, description: _desc.text.trim(), body: _body.text, isPremium: _premium, sizeBytes: size));
      }
      if (!mounted) return;
      snack(context, 'Published. Users see it immediately.');
      setState(() {
        _files = [];
        _title.clear();
        _titleBn.clear();
        _url.clear();
        _body.clear();
        _desc.clear();
        _progress = 0;
        _status = '';
      });
    } catch (e) {
      if (mounted) snack(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(customCatsProvider(_section));
    final cats = _catItems();
    if (!cats.containsKey(_category)) _category = cats.keys.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload content')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Dropdown<String>(label: 'Section', value: _section, items: _sectionItems(), onChanged: (v) => setState(() {_section = v!; _group = _groupItems(v).keys.first; _category = Sections.byId(v).cats.first.id;})),
        Dropdown<String>(label: 'Class / Track', value: _group, items: _groupItems(_section), onChanged: (v) => setState(() => _group = v!)),
        Dropdown<String>(label: 'Category', value: _category, items: cats, onChanged: (v) => setState(() => _category = v!)),
        Dropdown<String>(label: 'Type', value: _kind, items: {for (final k in contentKinds) k: k}, onChanged: (v) => setState(() {_kind = v!; _files = [];})),
        Field('Title (English)', _title),
        Field('Title (বাংলা, optional)', _titleBn),
        Field('Description (optional)', _desc, lines: 2),
        if (_kind == 'text') Field('Note text', _body, lines: 8),
        if (['link', 'youtube', 'video'].contains(_kind)) Field(_kind == 'youtube' ? 'YouTube URL' : 'URL (or pick a video file below)', _url, keyboard: TextInputType.url),
        if (['pdf', 'image', 'video'].contains(_kind))
          OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.attach_file), label: Text(_files.isEmpty ? 'Pick file(s) – multiple allowed' : '${_files.length} file(s) selected')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Premium only'), value: _premium, onChanged: (v) => setState(() => _premium = v)),
        if (_busy) ...[LinearProgressIndicator(value: _progress), Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_status))],
        const SizedBox(height: 8),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Publish')),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage (list / toggle premium / delete) content
// ---------------------------------------------------------------------------
class ManageContentScreen extends ConsumerStatefulWidget {
  const ManageContentScreen({super.key});
  @override
  ConsumerState<ManageContentScreen> createState() => _ManageContentScreenState();
}

class _ManageContentScreenState extends ConsumerState<ManageContentScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage content')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => _q = v.toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter latest 150', isDense: true))),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('content').orderBy('createdAt', descending: true).limit(150).snapshots(),
            builder: (context, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final items = s.data!.docs.map(ContentItem.fromDoc).where((c) => _q.isEmpty || c.title.toLowerCase().contains(_q)).toList();
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final c = items[i];
                  return ListTile(
                    leading: Icon(kindIcon(c.kind)),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${c.section} · ${c.group} · ${c.category}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: Icon(c.isPremium ? Icons.lock : Icons.lock_open), onPressed: () => _db.collection('content').doc(c.id).update({'isPremium': !c.isPremium})),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete?'), content: Text(c.title), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
                          if (ok == true) await ref.read(contentRepoProvider).delete(c);
                        },
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Create exam
// ---------------------------------------------------------------------------
class CreateExamScreen extends ConsumerStatefulWidget {
  const CreateExamScreen({super.key});
  @override
  ConsumerState<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends ConsumerState<CreateExamScreen> {
  final _title = TextEditingController(), _duration = TextEditingController(text: '20'), _neg = TextEditingController(text: '0'), _course = TextEditingController(), _bulk = TextEditingController();
  String _section = 'academic', _group = 'all', _type = 'mcq';
  bool _premium = false, _published = true, _busy = false;

  Future<void> _save() async {
    final qs = _type == 'mcq' ? parseMcqBulk(_bulk.text) : _bulk.text.split('\n').where((l) => l.trim().isNotEmpty).map((l) => Question(text: l.trim())).toList();
    if (_title.text.trim().isEmpty || qs.isEmpty) return snack(context, 'Title and at least one valid question required');
    setState(() => _busy = true);
    try {
      await ref.read(examRepoProvider).createExam({
        'title': _title.text.trim(),
        'section': _section,
        'group': _group,
        'type': _type,
        'durationMin': int.tryParse(_duration.text) ?? 20,
        'negativeMark': double.tryParse(_neg.text) ?? 0,
        'isPremium': _premium,
        'published': _published,
        'courseId': _course.text.trim(),
        'questions': qs.map((q) => q.toMap()).toList(),
      });
      if (!mounted) return;
      snack(context, 'Exam created with ${qs.length} questions');
      _bulk.clear();
      _title.clear();
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _type == 'mcq' ? parseMcqBulk(_bulk.text).length : _bulk.text.split('\n').where((l) => l.trim().isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Create exam')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Field('Exam title', _title),
        Dropdown<String>(label: 'Type', value: _type, items: const {'mcq': 'MCQ', 'written': 'Written'}, onChanged: (v) => setState(() => _type = v!)),
        Dropdown<String>(label: 'Section', value: _section, items: _sectionItems(), onChanged: (v) => setState(() {_section = v!; _group = 'all';})),
        Dropdown<String>(label: 'Class / Track', value: _groupItems(_section).containsKey(_group) ? _group : _groupItems(_section).keys.first, items: _groupItems(_section), onChanged: (v) => setState(() => _group = v!)),
        Row(children: [Expanded(child: Field('Duration (min)', _duration, keyboard: TextInputType.number)), const SizedBox(width: 12), Expanded(child: Field('Negative mark', _neg, keyboard: const TextInputType.numberWithOptions(decimal: true)))]),
        Field('Course ID (optional – makes it a course quiz/final)', _course),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Premium only'), value: _premium, onChanged: (v) => setState(() => _premium = v)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), value: _published, onChanged: (v) => setState(() => _published = v)),
        Text(_type == 'mcq' ? 'One question per line:\nQuestion | A | B | C | D | CorrectLetter | Explanation' : 'One question per line', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(controller: _bulk, minLines: 8, maxLines: 20, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Paste questions here')),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('$parsed valid question(s) detected')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Create exam')),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Courses (create, add lessons / assignments)
// ---------------------------------------------------------------------------
class CourseAdminScreen extends ConsumerStatefulWidget {
  const CourseAdminScreen({super.key});
  @override
  ConsumerState<CourseAdminScreen> createState() => _CourseAdminScreenState();
}

class _CourseAdminScreenState extends ConsumerState<CourseAdminScreen> {
  Future<void> _newCourse() async {
    final t = TextEditingController(), d = TextEditingController(), teacher = TextEditingController(), price = TextEditingController(text: '0');
    bool premium = false;
    File? thumb;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New course'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field('Title', t),
              Field('Description', d, lines: 3),
              Field('Teacher', teacher),
              Field('Price ৳ (0 = free)', price, keyboard: TextInputType.number),
              SwitchListTile(title: const Text('Premium members only'), value: premium, onChanged: (v) => set(() => premium = v)),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(type: FileType.image);
                  if (r?.files.single.path != null) set(() => thumb = File(r!.files.single.path!));
                },
                icon: const Icon(Icons.image),
                label: Text(thumb == null ? 'Thumbnail' : thumb!.path.split('/').last),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(90, 40)), child: const Text('Create'))],
        ),
      ),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    String thumbUrl = '';
    if (thumb != null) thumbUrl = (await ref.read(contentRepoProvider).upload(thumb!, 'courses/thumbs', thumb!.path.split('/').last)).$1;
    await _db.collection('courses').add({'title': t.text.trim(), 'description': d.text.trim(), 'teacher': teacher.text.trim(), 'price': num.tryParse(price.text) ?? 0, 'isPremium': premium, 'published': true, 'thumbnailUrl': thumbUrl, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> _addLesson(String courseId, int next) async {
    final t = TextEditingController(), url = TextEditingController();
    String kind = 'youtube';
    bool preview = false;
    PlatformFile? file;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add lesson'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field('Title', t),
              Dropdown<String>(label: 'Type', value: kind, items: const {'youtube': 'YouTube', 'video': 'Video (URL/file)', 'pdf': 'PDF', 'image': 'Image', 'text': 'Text'}, onChanged: (v) => set(() => kind = v!)),
              Field(kind == 'text' ? 'Text' : 'URL (or pick a file)', url, lines: kind == 'text' ? 4 : 1),
              if (['video', 'pdf', 'image'].contains(kind)) OutlinedButton.icon(onPressed: () async {final r = await FilePicker.platform.pickFiles(); if (r != null) set(() => file = r.files.single);}, icon: const Icon(Icons.attach_file), label: Text(file?.name ?? 'Pick file')),
              SwitchListTile(title: const Text('Free preview'), value: preview, onChanged: (v) => set(() => preview = v)),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(90, 40)), child: const Text('Add'))],
        ),
      ),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    var u = kind == 'text' ? '' : url.text.trim();
    if (file?.path != null) u = (await ref.read(contentRepoProvider).upload(File(file!.path!), 'courses/$courseId', file!.name)).$1;
    await _db.collection('courses').doc(courseId).collection('lessons').add({'title': t.text.trim(), 'kind': kind, 'url': u, if (kind == 'text') 'body': url.text, 'order': next, 'isPreview': preview});
  }

  Future<void> _addAssignment(String path) async {
    final t = TextEditingController(), d = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add assignment'), content: Column(mainAxisSize: MainAxisSize.min, children: [Field('Title', t), Field('Instructions', d, lines: 3)]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(90, 40)), child: const Text('Add'))]));
    if (ok == true && t.text.trim().isNotEmpty) await _db.doc(path).collection('assignments').add({'title': t.text.trim(), 'description': d.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newCourse, icon: const Icon(Icons.add), label: const Text('New course')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('courses').snapshots(),
        builder: (context, s) {
          final docs = s.data?.docs ?? [];
          if (docs.isEmpty) return const EmptyState(icon: Icons.school);
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            for (final c in docs)
              ExpansionTile(
                title: Text(c['title'] ?? ''),
                subtitle: Text('ID: ${c.id}  ·  ৳${c['price'] ?? 0}  ·  ${c['published'] == true ? 'published' : 'hidden'}'),
                children: [
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: c.reference.collection('lessons').snapshots(),
                    builder: (context, ls) {
                      final lessons = ls.data?.docs ?? [];
                      return Column(children: [
                        for (final l in lessons) ListTile(dense: true, title: Text(l['title'] ?? ''), subtitle: Text(l['kind'] ?? ''), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => l.reference.delete())),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton.icon(onPressed: () => _addLesson(c.id, lessons.length + 1), icon: const Icon(Icons.add), label: const Text('Lesson')),
                          TextButton.icon(onPressed: () => _addAssignment('courses/${c.id}'), icon: const Icon(Icons.assignment), label: const Text('Assignment')),
                          TextButton.icon(onPressed: () => c.reference.update({'published': !(c['published'] == true)}), icon: const Icon(Icons.visibility), label: const Text('Toggle')),
                          TextButton.icon(onPressed: () => c.reference.delete(), icon: const Icon(Icons.delete, color: Colors.red), label: const Text('Delete')),
                        ]),
                      ]);
                    },
                  ),
                ],
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live classes
// ---------------------------------------------------------------------------
class LiveAdminScreen extends StatefulWidget {
  const LiveAdminScreen({super.key});
  @override
  State<LiveAdminScreen> createState() => _LiveAdminScreenState();
}

class _LiveAdminScreenState extends State<LiveAdminScreen> {
  Future<void> _create() async {
    final t = TextEditingController(), teacher = TextEditingController(), url = TextEditingController();
    DateTime when = DateTime.now().add(const Duration(hours: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Schedule live class'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field('Title', t),
              Field('Teacher', teacher),
              Field('YouTube Live / meeting URL', url, keyboard: TextInputType.url),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(DateFormat('d MMM, hh:mm a').format(when)),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d == null || !ctx.mounted) return;
                  final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                  if (tm != null) set(() => when = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
                },
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(90, 40)), child: const Text('Schedule'))],
        ),
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) {
      await _db.collection('liveClasses').add({'title': t.text.trim(), 'teacher': teacher.text.trim(), 'url': url.text.trim(), 'startsAt': Timestamp.fromDate(when), 'status': 'upcoming', 'reminded': false, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live classes')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Schedule')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('liveClasses').snapshots(),
        builder: (context, s) {
          final docs = s.data?.docs ?? [];
          return ListView(children: [
            for (final d in docs)
              ListTile(
                title: Text(d['title'] ?? ''),
                subtitle: Text('${d['status']} · ${(d['startsAt'] as Timestamp?)?.toDate().toString().substring(0, 16) ?? ''}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'delete') return d.reference.delete();
                    if (v == 'recording') {
                      final c = TextEditingController();
                      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Recording URL'), content: TextField(controller: c), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
                      if (ok == true) await d.reference.update({'recordingUrl': c.text.trim(), 'status': 'ended'});
                      return;
                    }
                    await d.reference.update({'status': v});
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'live', child: Text('Go live')), PopupMenuItem(value: 'ended', child: Text('End')), PopupMenuItem(value: 'recording', child: Text('Add recording')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications (calls Cloud Function; FCM server key never in the app)
// ---------------------------------------------------------------------------
class SendNotificationScreen extends ConsumerStatefulWidget {
  const SendNotificationScreen({super.key});
  @override
  ConsumerState<SendNotificationScreen> createState() => _SendNotificationScreenState();
}

class _SendNotificationScreenState extends ConsumerState<SendNotificationScreen> {
  final _title = TextEditingController(), _body = TextEditingController(), _course = TextEditingController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send notification')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Field('Title', _title),
        Field('Message', _body, lines: 3),
        Field('Course ID (leave empty to send to everyone)', _course),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  if (_title.text.trim().isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    await ref.read(functionsProvider).httpsCallable('sendNotification').call({'title': _title.text.trim(), 'body': _body.text.trim(), 'topic': _course.text.trim().isEmpty ? 'all' : 'course_${_course.text.trim()}'});
                    if (context.mounted) snack(context, 'Sent');
                    _title.clear();
                    _body.clear();
                  } on FirebaseFunctionsException catch (e) {
                    if (context.mounted) snack(context, e.message ?? e.code);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.send),
          label: const Text('Send'),
        ),
        const SizedBox(height: 12),
        const Text('New book alerts, live-class reminders and exam reminders are sent automatically by Cloud Functions.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});
  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => _q = v.toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter by name/email', isDense: true))),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _db.collection('users').orderBy('createdAt', descending: true).limit(200).snapshots(),
            builder: (context, s) {
              final users = (s.data?.docs ?? []).map(AppUser.fromDoc).where((u) => _q.isEmpty || '${u.name} ${u.email}'.toLowerCase().contains(_q)).toList();
              return ListView(children: [
                for (final u in users)
                  ListTile(
                    leading: Icon(u.isAdmin ? Icons.admin_panel_settings : (u.isGuest ? Icons.person_outline : Icons.person)),
                    title: Text(u.name.isEmpty ? '(no name)' : u.name),
                    subtitle: Text('${u.email}${u.isPremium ? ' · PREMIUM' : ''}${u.banned ? ' · BANNED' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        final r = _db.collection('users').doc(u.uid);
                        switch (v) {
                          case 'premium30':
                            r.update({'isPremium': true, 'premiumUntil': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))});
                          case 'unpremium':
                            r.update({'isPremium': false, 'premiumUntil': null});
                          case 'admin':
                            r.update({'role': u.isAdmin ? 'student' : 'admin'});
                          case 'ban':
                            r.update({'banned': !u.banned});
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'premium30', child: Text('Grant Premium 30 days')),
                        const PopupMenuItem(value: 'unpremium', child: Text('Remove Premium')),
                        PopupMenuItem(value: 'admin', child: Text(u.isAdmin ? 'Remove admin' : 'Make admin')),
                        PopupMenuItem(value: 'ban', child: Text(u.banned ? 'Unban' : 'Ban')),
                      ],
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Payments: approve → unlock premium / course
// ---------------------------------------------------------------------------
class PaymentsAdminScreen extends StatelessWidget {
  const PaymentsAdminScreen({super.key});

  Future<void> _approve(QueryDocumentSnapshot<Map<String, dynamic>> p) async {
    final m = p.data();
    final uid = m['uid'] as String;
    final batch = _db.batch();
    batch.update(p.reference, {'status': 'approved', 'approvedAt': FieldValue.serverTimestamp()});
    if (m['type'] == 'premium') {
      final u = await _db.collection('users').doc(uid).get();
      final current = (u.data()?['premiumUntil'] as Timestamp?)?.toDate();
      final base = (current != null && current.isAfter(DateTime.now())) ? current : DateTime.now();
      batch.update(u.reference, {'isPremium': true, 'premiumUntil': Timestamp.fromDate(base.add(Duration(days: (m['days'] ?? 30) as int)))});
    } else if (m['type'] == 'course') {
      batch.set(_db.collection('users').doc(uid).collection('enrollments').doc(m['refId']), {'courseId': m['refId'], 'at': FieldValue.serverTimestamp(), 'via': 'payment'});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Payments'), bottom: const TabBar(tabs: [Tab(text: 'Pending'), Tab(text: 'History')])),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('payments').orderBy('createdAt', descending: true).limit(200).snapshots(),
          builder: (context, s) {
            final docs = s.data?.docs ?? [];
            final pending = docs.where((d) => d['status'] == 'pending').toList();
            final rest = docs.where((d) => d['status'] != 'pending').toList();
            return TabBarView(children: [
              ListView(children: [
                for (final p in pending)
                  Card(
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p['title']} — ৳${p['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('${p['userName']} · ${p['method']} · ${p['senderNumber']}'),
                        SelectableText('TrxID: ${p['trxId']}'),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton(onPressed: () => p.reference.update({'status': 'rejected'}), child: const Text('Reject')),
                          FilledButton(onPressed: () => _approve(p), style: FilledButton.styleFrom(minimumSize: const Size(100, 40)), child: const Text('Approve')),
                        ]),
                      ]),
                    ),
                  ),
                if (pending.isEmpty) const EmptyState(icon: Icons.payments, message: 'No pending payments'),
              ]),
              ListView(children: [for (final p in rest) ListTile(title: Text('${p['title']} — ৳${p['amount']}'), subtitle: Text('${p['userName']} · ${p['trxId']}'), trailing: Chip(label: Text('${p['status']}')))]),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------
class CategoriesAdminScreen extends ConsumerStatefulWidget {
  const CategoriesAdminScreen({super.key});
  @override
  ConsumerState<CategoriesAdminScreen> createState() => _CategoriesAdminScreenState();
}

class _CategoriesAdminScreenState extends ConsumerState<CategoriesAdminScreen> {
  String _section = 'academic';
  final _en = TextEditingController(), _bn = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(customCatsProvider(_section)).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Dropdown<String>(label: 'Section', value: _section, items: _sectionItems(), onChanged: (v) => setState(() => _section = v!)),
        Field('Name (English)', _en),
        Field('Name (বাংলা)', _bn),
        FilledButton(
          onPressed: () async {
            if (_en.text.trim().isEmpty) return;
            await ref.read(contentRepoProvider).addCategory(_section, _en.text.trim(), _bn.text.trim());
            _en.clear();
            _bn.clear();
          },
          child: const Text('Add category'),
        ),
        const Divider(height: 32),
        for (final c in cats) ListTile(title: Text('${c['nameEn']}'), subtitle: Text('${c['nameBn']}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(contentRepoProvider).deleteCategory(c['id']))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Bulk import for Daily Quiz bank and Vocabulary
// ---------------------------------------------------------------------------
class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});
  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  final _ctl = TextEditingController();
  String _target = 'quizBank';
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final batch = _db.batch();
      var n = 0;
      if (_target == 'quizBank') {
        for (final q in parseMcqBulk(_ctl.text)) {
          batch.set(_db.collection('quizBank').doc(), q.toMap());
          n++;
        }
      } else {
        for (final line in _ctl.text.split('\n')) {
          final p = line.split('|').map((e) => e.trim()).toList();
          if (p.length < 2 || p[0].isEmpty) continue;
          batch.set(_db.collection('vocabulary').doc(), {'word': p[0], 'meaningBn': p[1], 'meaningEn': p.length > 2 ? p[2] : '', 'example': p.length > 3 ? p[3] : ''});
          n++;
        }
      }
      await batch.commit();
      if (mounted) {
        snack(context, 'Imported $n item(s)');
        _ctl.clear();
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quiz & vocabulary import')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Dropdown<String>(label: 'Import into', value: _target, items: const {'quizBank': 'Daily quiz bank', 'vocabulary': 'Vocabulary / flashcards'}, onChanged: (v) => setState(() => _target = v!)),
          Text(_target == 'quizBank' ? 'Question | A | B | C | D | CorrectLetter | Explanation' : 'word | Bangla meaning | English meaning | example sentence', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(controller: _ctl, minLines: 10, maxLines: 25),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _import, child: const Text('Import')),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Remote settings: ads, payment numbers, announcement banner
// ---------------------------------------------------------------------------
class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});
  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  final _c = <String, TextEditingController>{for (final k in ['banner', 'interstitial', 'rewarded', 'appOpen', 'native', 'bkash', 'nagad', 'rocket', 'note', 'homeBanner']) k: TextEditingController()};
  bool _adsEnabled = true, _loaded = false;

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(remoteConfigProvider).valueOrNull;
    if (cfg != null && !_loaded) {
      _loaded = true;
      final ads = Map<String, dynamic>.from(cfg['ads'] ?? {}), pay = Map<String, dynamic>.from(cfg['payment'] ?? {});
      _adsEnabled = ads['enabled'] ?? true;
      for (final k in ['banner', 'interstitial', 'rewarded', 'appOpen', 'native']) {
        _c[k]!.text = '${ads[k] ?? ''}';
      }
      for (final k in ['bkash', 'nagad', 'rocket', 'note']) {
        _c[k]!.text = '${pay[k] ?? ''}';
      }
      _c['homeBanner']!.text = '${cfg['homeBanner'] ?? ''}';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Ads & settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('AdMob', style: Theme.of(context).textTheme.titleMedium),
        const Text('Leave unit IDs empty to use Google test ads. Paste your real ad unit IDs for production.', style: TextStyle(fontSize: 12)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ads enabled'), value: _adsEnabled, onChanged: (v) => setState(() => _adsEnabled = v)),
        Field('Banner unit ID', _c['banner']!),
        Field('Interstitial unit ID', _c['interstitial']!),
        Field('Rewarded unit ID', _c['rewarded']!),
        Field('App Open unit ID', _c['appOpen']!),
        Field('Native unit ID', _c['native']!),
        const Divider(height: 32),
        Text('Payment numbers', style: Theme.of(context).textTheme.titleMedium),
        Field('bKash number', _c['bkash']!, keyboard: TextInputType.phone),
        Field('Nagad number', _c['nagad']!, keyboard: TextInputType.phone),
        Field('Rocket number', _c['rocket']!, keyboard: TextInputType.phone),
        Field('Instruction note', _c['note']!, lines: 2),
        const Divider(height: 32),
        Field('Home announcement banner (empty = hidden)', _c['homeBanner']!, lines: 2),
        FilledButton(
          onPressed: () async {
            await ref.read(contentRepoProvider).saveConfig({
              'ads': {'enabled': _adsEnabled, for (final k in ['banner', 'interstitial', 'rewarded', 'appOpen', 'native']) k: _c[k]!.text.trim()},
              'payment': {for (final k in ['bkash', 'nagad', 'rocket', 'note']) k: _c[k]!.text.trim()},
              'homeBanner': _c['homeBanner']!.text.trim(),
            });
            if (context.mounted) snack(context, 'Saved');
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
