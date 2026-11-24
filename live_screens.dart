import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../courses/course_screens.dart';

final _db = FirebaseFirestore.instance;

final liveListProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) => _db
    .collection('liveClasses')
    .snapshots()
    .map((s) => s.docs.toList()..sort((a, b) => ((b['startsAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a['startsAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0))));

/// Live classes are streamed through YouTube Live (or any meeting link) that
/// the admin pastes in; Study BD handles scheduling, chat, attendance and
/// assignments around it.
class LiveListScreen extends ConsumerWidget {
  const LiveListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('live')), bottom: TabBar(tabs: [Tab(text: context.lang == 'bn' ? 'লাইভ / আসন্ন' : 'Live & Upcoming'), Tab(text: context.lang == 'bn' ? 'রেকর্ডেড' : 'Recorded')])),
        body: AsyncView<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          value: ref.watch(liveListProvider),
          builder: (docs) {
            final upcoming = docs.where((d) => d['status'] != 'ended').toList().reversed.toList();
            final recorded = docs.where((d) => d['status'] == 'ended').toList();
            Widget list(List<QueryDocumentSnapshot<Map<String, dynamic>>> l) => l.isEmpty
                ? const EmptyState(icon: Icons.live_tv)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: l.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = l[i];
                      final at = (d['startsAt'] as Timestamp?)?.toDate();
                      final live = d['status'] == 'live';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: live ? Colors.red : null, child: Icon(live ? Icons.sensors : Icons.live_tv, color: live ? Colors.white : null)),
                          title: Text(d['title'] ?? ''),
                          subtitle: Text('${d['teacher'] ?? ''}${at != null ? '\n${at.toString().substring(0, 16)}' : ''}'),
                          isThreeLine: at != null,
                          trailing: live ? const Chip(label: Text('LIVE')) : null,
                          onTap: () => context.push('/live/${d.id}'),
                        ),
                      );
                    },
                  );
            return TabBarView(children: [list(upcoming), list(recorded)]);
          },
        ),
      ),
    );
  }
}

class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key, required this.liveId});
  final String liveId;
  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  final _msg = TextEditingController();
  YoutubePlayerController? _yt;
  String? _loadedUrl;

  DocumentReference<Map<String, dynamic>> get _ref => _db.collection('liveClasses').doc(widget.liveId);

  @override
  void initState() {
    super.initState();
    _markAttendance();
  }

  Future<void> _markAttendance() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final name = ref.read(appUserProvider).valueOrNull?.name ?? '';
    await _ref.collection('attendance').doc(uid).set({'uid': uid, 'name': name, 'at': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((_) {});
  }

  void _setupPlayer(String url) {
    if (url == _loadedUrl) return;
    _loadedUrl = url;
    final id = YoutubePlayer.convertUrlToId(url);
    _yt?.dispose();
    _yt = id == null ? null : YoutubePlayerController(initialVideoId: id, flags: const YoutubePlayerFlags(autoPlay: true, isLive: false));
  }

  Future<void> _send() async {
    final t = _msg.text.trim();
    if (t.isEmpty) return;
    _msg.clear();
    final u = ref.read(appUserProvider).valueOrNull;
    await _ref.collection('chat').add({'uid': ref.read(authStateProvider).valueOrNull!.uid, 'name': u?.name.isNotEmpty == true ? u!.name : 'Student', 'text': t, 'at': FieldValue.serverTimestamp()});
  }

  @override
  void dispose() {
    _yt?.dispose();
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final m = snap.data!.data() ?? {};
        final ended = m['status'] == 'ended';
        final url = ((ended ? m['recordingUrl'] : m['url']) ?? m['url'] ?? '') as String;
        _setupPlayer(url);

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(title: Text(m['title'] ?? '')),
            body: Column(children: [
              if (_yt != null)
                YoutubePlayer(controller: _yt!)
              else
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: url.isEmpty
                        ? const Text('Stream link not added yet')
                        : FilledButton.icon(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Join class')),
                  ),
                ),
              TabBar(tabs: [Tab(text: context.lang == 'bn' ? 'লাইভ চ্যাট' : 'Live chat'), Tab(text: context.lang == 'bn' ? 'অ্যাসাইনমেন্ট' : 'Assignments')]),
              Expanded(
                child: TabBarView(children: [
                  Column(children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _ref.collection('chat').orderBy('at', descending: true).limit(100).snapshots(),
                        builder: (context, s) {
                          final docs = s.data?.docs ?? [];
                          return ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: docs.length,
                            itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text.rich(TextSpan(children: [TextSpan(text: '${docs[i]['name']}: ', style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: docs[i]['text'])]))),
                          );
                        },
                      ),
                    ),
                    if (!ended)
                      SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: TextField(controller: _msg, decoration: const InputDecoration(hintText: 'Say something…', isDense: true), onSubmitted: (_) => _send())), IconButton.filled(onPressed: _send, icon: const Icon(Icons.send))]))),
                  ]),
                  AssignmentsView(path: 'liveClasses/${widget.liveId}'),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
