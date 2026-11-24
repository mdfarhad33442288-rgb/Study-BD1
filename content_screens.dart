import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/sections.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/services/ads_service.dart';
import '../../core/services/download_service.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import 'viewers.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final contentListProvider = StreamProvider.autoDispose.family<List<ContentItem>, (String, String, String)>((ref, q) {
  return ref.watch(contentRepoProvider).watch(section: q.$1, group: q.$2, category: q.$3);
});

final customCatsProvider = StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
    (ref, section) => ref.watch(contentRepoProvider).watchCustomCategories(section));

// ---------------------------------------------------------------------------
// Opening content (premium gate + ads + analytics)
// ---------------------------------------------------------------------------
final _sessionUnlocked = <String>{};

Future<void> openContent(BuildContext context, WidgetRef ref, ContentItem c, {List<ContentItem> playlist = const []}) async {
  final premium = ref.read(isPremiumProvider);
  if (c.isPremium && !premium && !_sessionUnlocked.contains(c.id)) {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.workspace_premium),
        title: Text(ctx.tr('locked')),
        content: Text(c.displayTitle(ctx.lang)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          if (AdsService.instance.active) TextButton(onPressed: () => Navigator.pop(ctx, 'ad'), child: Text(ctx.tr('watchAd'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'premium'), style: FilledButton.styleFrom(minimumSize: const Size(100, 40)), child: Text(ctx.tr('goPremium'))),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'premium') {
      context.push('/premium');
      return;
    }
    if (choice == 'ad') {
      final ok = await AdsService.instance.showRewarded();
      if (!ok) return;
      _sessionUnlocked.add(c.id);
    } else {
      return;
    }
  }
  if (!context.mounted) return;

  AdsService.instance.maybeShowInterstitial();
  FirebaseAnalytics.instance.logEvent(name: 'open_content', parameters: {'kind': c.kind, 'section': c.section, 'category': c.category});
  ref.read(contentRepoProvider).bumpStat('opens');

  switch (c.kind) {
    case 'pdf':
      context.push('/pdf', extra: c);
    case 'video':
    case 'youtube':
      context.push('/video', extra: VideoArgs(c, playlist.where((e) => e.kind == 'video' || e.kind == 'youtube').toList()));
    case 'image':
      context.push('/image', extra: c);
    case 'text':
      context.push('/note', extra: c);
    default:
      final uri = Uri.tryParse(c.url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

IconData kindIcon(String kind) => switch (kind) {
      'pdf' => Icons.picture_as_pdf,
      'video' || 'youtube' => Icons.play_circle,
      'image' => Icons.image,
      'text' => Icons.article,
      _ => Icons.link,
    };

// ---------------------------------------------------------------------------
// Hub: groups (class / track) -> categories
// ---------------------------------------------------------------------------
class HubScreen extends ConsumerWidget {
  const HubScreen({super.key, required this.sectionId, this.groupId});
  final String sectionId;
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Sections.byId(sectionId);
    final lang = context.lang;
    final showGroups = s.hasGroups && groupId == null;
    final group = s.hasGroups && groupId != null ? s.groups.firstWhere((g) => g.id == groupId) : null;
    final custom = ref.watch(customCatsProvider(sectionId)).valueOrNull ?? [];

    final tiles = <Widget>[];
    if (showGroups) {
      for (final g in s.groups) {
        tiles.add(FeatureTile(icon: s.icon, label: g.name(lang), color: s.color, onTap: () => context.push('/hub/$sectionId/${g.id}')));
      }
    } else {
      final gid = groupId ?? 'all';
      final base = '/list/$sectionId/$gid';
      for (final c in s.cats) {
        tiles.add(FeatureTile(
            icon: c.icon, label: c.name(lang), color: s.color, onTap: () => context.push('$base/${c.id}?t=${Uri.encodeComponent(c.name(lang))}')));
      }
      for (final c in custom) {
        final name = lang == 'bn' && (c['nameBn'] ?? '').toString().isNotEmpty ? c['nameBn'] : c['nameEn'];
        tiles.add(FeatureTile(
            icon: Icons.folder, label: '$name', color: s.color, onTap: () => context.push('$base/${c['id']}?t=${Uri.encodeComponent('$name')}')));
      }
      // Special shortcuts
      if (sectionId == 'ielts') {
        tiles.add(FeatureTile(icon: Icons.calculate, label: lang == 'bn' ? 'ব্যান্ড ক্যালকুলেটর' : 'Band Calculator', color: s.color, onTap: () => context.push('/band')));
        tiles.add(FeatureTile(icon: Icons.smart_toy, label: lang == 'bn' ? 'আইইএলটিএস কোচ' : 'IELTS Coach', color: s.color, onTap: () => context.push('/ai?mode=ielts')));
      }
      if (sectionId == 'english') {
        tiles.add(FeatureTile(icon: Icons.mic, label: lang == 'bn' ? 'ভয়েস স্পিকিং' : 'Speak & Evaluate', color: s.color, onTap: () => context.push('/speaking')));
        tiles.add(FeatureTile(icon: Icons.g_translate, label: lang == 'bn' ? 'অনুবাদ' : 'Translate', color: s.color, onTap: () => context.push('/translation')));
        tiles.add(FeatureTile(icon: Icons.today, label: context.tr('dailyVocab'), color: s.color, onTap: () => context.push('/vocab')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(group?.name(lang) ?? s.name(lang)), actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
      ]),
      body: Column(children: [
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: tiles,
          ),
        ),
        const BannerAdWidget(),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Content list
// ---------------------------------------------------------------------------
class ContentListScreen extends ConsumerStatefulWidget {
  const ContentListScreen({super.key, required this.section, required this.group, required this.category, required this.title});
  final String section, group, category, title;
  @override
  ConsumerState<ContentListScreen> createState() => _ContentListScreenState();
}

class _ContentListScreenState extends ConsumerState<ContentListScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contentListProvider((widget.section, widget.group, widget.category)));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.tr('search'), isDense: true),
          ),
        ),
        Expanded(
          child: AsyncView<List<ContentItem>>(
            value: async,
            onRetry: () => ref.invalidate(contentListProvider),
            builder: (all) {
              final items = _q.isEmpty ? all : all.where((c) => '${c.title} ${c.titleBn}'.toLowerCase().contains(_q)).toList();
              if (items.isEmpty) return const EmptyState();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, i) => (i + 1) % 8 == 0 ? const NativeAdTile() : const SizedBox(height: 8),
                itemBuilder: (_, i) => ContentTile(item: items[i], playlist: items),
              );
            },
          ),
        ),
        const BannerAdWidget(),
      ]),
    );
  }
}

class ContentTile extends ConsumerStatefulWidget {
  const ContentTile({super.key, required this.item, this.playlist = const []});
  final ContentItem item;
  final List<ContentItem> playlist;
  @override
  ConsumerState<ContentTile> createState() => _ContentTileState();
}

class _ContentTileState extends ConsumerState<ContentTile> {
  double? _progress;

  Future<void> _download() async {
    final premium = ref.read(isPremiumProvider);
    final dl = ref.read(downloadServiceProvider);
    if (!dl.canDownload(premium)) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('premium')),
          content: Text('Free accounts can download ${DownloadService.freeDailyLimit} files per day. Go Premium for unlimited downloads.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(minimumSize: const Size(100, 40)), child: Text(ctx.tr('goPremium'))),
          ],
        ),
      );
      if (go == true && mounted) context.push('/premium');
      return;
    }
    if (widget.item.isPremium && !premium) {
      snack(context, context.tr('locked'));
      return;
    }
    setState(() => _progress = 0);
    try {
      await dl.download(widget.item, onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      ref.read(contentRepoProvider).bumpStat('downloads');
      if (mounted) snack(context, context.tr('offline'));
    } catch (e) {
      if (mounted) snack(context, 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final lang = context.lang;
    final bookmarked = ref.watch(bookmarksProvider).any((b) => b.id == c.id);
    final offline = ref.read(downloadServiceProvider).isDownloaded(c.id);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        onTap: () => openContent(context, ref, c, playlist: widget.playlist),
        leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(kindIcon(c.kind), color: cs.primary)),
        title: Text(c.displayTitle(lang), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: _progress != null
            ? Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: _progress))
            : Row(children: [
                if (c.isPremium) ...[Icon(Icons.lock, size: 14, color: cs.tertiary), const SizedBox(width: 4), Text(context.tr('premium'))],
                if (offline) ...[const SizedBox(width: 8), const Icon(Icons.download_done, size: 14), const SizedBox(width: 4), Text(context.tr('offline'))],
              ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (c.downloadable && !offline && _progress == null)
            IconButton(icon: const Icon(Icons.download_outlined), tooltip: context.tr('download'), onPressed: _download),
          IconButton(
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => ref.read(bookmarksProvider.notifier).toggle(c),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global search with voice input
// ---------------------------------------------------------------------------
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctl = TextEditingController();
  final _stt = SpeechToText();
  List<ContentItem> _results = [];
  bool _loading = false, _listening = false;

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(contentRepoProvider).search(q);
      if (mounted) setState(() => _results = r);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _voice() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize();
    if (!ok) {
      if (mounted) snack(context, 'Speech recognition unavailable');
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      localeId: context.lang == 'bn' ? 'bn_BD' : 'en_US',
      onResult: (r) {
        _ctl.text = r.recognizedWords;
        if (r.finalResult) {
          setState(() => _listening = false);
          _search(r.recognizedWords);
        }
      },
    );
  }

  @override
  void dispose() {
    _stt.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(hintText: context.tr('search'), border: InputBorder.none, filled: false),
        ),
        actions: [IconButton(icon: Icon(_listening ? Icons.mic : Icons.mic_none), onPressed: _voice)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const EmptyState(icon: Icons.search)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => ContentTile(item: _results[i], playlist: _results),
                ),
    );
  }
}
