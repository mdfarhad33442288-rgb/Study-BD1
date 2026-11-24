import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/services/ads_service.dart';
import '../../data/models/models.dart';

// ---------------------------------------------------------------------------
// PDF reader (works offline for downloaded files)
// ---------------------------------------------------------------------------
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key, required this.item});
  final ContentItem item;
  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  PdfControllerPinch? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final dl = ref.read(downloadServiceProvider);
      final path = dl.localPath(widget.item.id) ?? await dl.cacheTemp(widget.item);
      if (!mounted) return;
      setState(() => _c = PdfControllerPinch(document: PdfDocument.openFile(path)));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open PDF. Check your connection.\n$e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarked = ref.watch(bookmarksProvider).any((b) => b.id == widget.item.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.displayTitle(context.lang), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_c != null) Center(child: PdfPageNumber(controller: _c!, builder: (_, state, page, total) => Text('$page / ${total ?? '-'}  '))),
          IconButton(
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => ref.read(bookmarksProvider.notifier).toggle(widget.item),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _c == null
              ? const Center(child: CircularProgressIndicator())
              : PdfViewPinch(controller: _c!),
    );
  }
}

// ---------------------------------------------------------------------------
// Video (YouTube + uploaded files + playlist)
// ---------------------------------------------------------------------------
class VideoArgs {
  final ContentItem item;
  final List<ContentItem> playlist;
  const VideoArgs(this.item, this.playlist);
}

class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key, required this.args});
  final VideoArgs args;
  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  YoutubePlayerController? _yt;
  VideoPlayerController? _vp;
  ChewieController? _chewie;
  String? _error;

  ContentItem get item => widget.args.item;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (item.isYoutube) {
        final id = YoutubePlayer.convertUrlToId(item.url);
        if (id == null) throw 'Invalid YouTube link';
        _yt = YoutubePlayerController(initialVideoId: id, flags: const YoutubePlayerFlags(autoPlay: true));
        setState(() {});
      } else {
        final local = ref.read(downloadServiceProvider).localPath(item.id);
        _vp = local != null ? VideoPlayerController.file(File(local)) : VideoPlayerController.networkUrl(Uri.parse(item.url));
        await _vp!.initialize();
        _chewie = ChewieController(videoPlayerController: _vp!, autoPlay: true, allowFullScreen: true, aspectRatio: _vp!.value.aspectRatio);
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _yt?.dispose();
    _chewie?.dispose();
    _vp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    Widget player;
    if (_error != null) {
      player = AspectRatio(aspectRatio: 16 / 9, child: Center(child: Text(_error!)));
    } else if (_yt != null) {
      player = YoutubePlayer(controller: _yt!, showVideoProgressIndicator: true);
    } else if (_chewie != null) {
      player = AspectRatio(aspectRatio: _vp!.value.aspectRatio, child: Chewie(controller: _chewie!));
    } else {
      player = const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()));
    }

    final list = widget.args.playlist;
    return Scaffold(
      appBar: AppBar(title: Text(item.displayTitle(lang), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        player,
        Expanded(
          child: ListView(children: [
            ListTile(title: Text(item.displayTitle(lang), style: Theme.of(context).textTheme.titleMedium), subtitle: item.description.isEmpty ? null : Text(item.description)),
            if (list.length > 1) const Divider(),
            for (final v in list)
              ListTile(
                selected: v.id == item.id,
                leading: Icon(v.id == item.id ? Icons.play_arrow : Icons.play_circle_outline),
                title: Text(v.displayTitle(lang), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => v.id == item.id ? null : context.pushReplacement('/video', extra: VideoArgs(v, list)),
              ),
          ]),
        ),
        const BannerAdWidget(),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Image + text note viewers
// ---------------------------------------------------------------------------
class ImageViewerScreen extends ConsumerWidget {
  const ImageViewerScreen({super.key, required this.item});
  final ContentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.read(downloadServiceProvider).localPath(item.id);
    return Scaffold(
      appBar: AppBar(title: Text(item.displayTitle(context.lang))),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: local != null ? Image.file(File(local)) : CachedNetworkImage(imageUrl: item.url, placeholder: (_, __) => const CircularProgressIndicator())),
      ),
    );
  }
}

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.item});
  final ContentItem item;
  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _tts = FlutterTts();
  bool _speaking = false;

  Future<void> _toggle() async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    await _tts.setLanguage(context.lang == 'bn' ? 'bn-BD' : 'en-US');
    _tts.setCompletionHandler(() => mounted ? setState(() => _speaking = false) : null);
    setState(() => _speaking = true);
    await _tts.speak(widget.item.body);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.displayTitle(context.lang)), actions: [
        IconButton(icon: Icon(_speaking ? Icons.stop_circle : Icons.volume_up), tooltip: 'Text to speech', onPressed: _toggle),
      ]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(widget.item.body, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6))),
    );
  }
}
