import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:video_player/video_player.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../ai_tutor/ai_tutor_screen.dart';

// ---------------------------------------------------------------------------
// Speaking practice: record yourself + speech recognition + AI evaluation
// ---------------------------------------------------------------------------
const _speakingPrompts = [
  'Introduce yourself and talk about your family.',
  'Describe your hometown. What do you like about it?',
  'Talk about your favourite subject and why you enjoy it.',
  'Describe a memorable day in your life.',
  'What are your goals for the next five years?',
  'Do you prefer studying alone or in a group? Why?',
];

class SpeakingPracticeScreen extends ConsumerStatefulWidget {
  const SpeakingPracticeScreen({super.key});
  @override
  ConsumerState<SpeakingPracticeScreen> createState() => _SpeakingPracticeScreenState();
}

class _SpeakingPracticeScreenState extends ConsumerState<SpeakingPracticeScreen> {
  final _stt = SpeechToText();
  final _rec = AudioRecorder();
  VideoPlayerController? _player; // video_player also plays local audio on Android
  int _prompt = 0;
  String _transcript = '', _feedback = '';
  bool _listening = false, _recording = false, _evaluating = false;
  String? _audioPath;

  @override
  void dispose() {
    _stt.cancel();
    _rec.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!await _stt.initialize()) {
      if (mounted) snack(context, 'Speech recognition unavailable on this device');
      return;
    }
    setState(() {
      _listening = true;
      _transcript = '';
      _feedback = '';
    });
    await _stt.listen(
      localeId: 'en_US',
      listenFor: const Duration(minutes: 2),
      onResult: (r) {
        setState(() => _transcript = r.recognizedWords);
        if (r.finalResult) setState(() => _listening = false);
      },
    );
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final p = await _rec.stop();
      setState(() => _recording = false);
      if (p != null) {
        _audioPath = p;
        _player?.dispose();
        _player = VideoPlayerController.file(File(p));
        await _player!.initialize();
        setState(() {});
      }
      return;
    }
    if (!await _rec.hasPermission()) {
      if (mounted) snack(context, 'Microphone permission needed');
      return;
    }
    final dir = await getTemporaryDirectory();
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '${dir.path}/practice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    setState(() => _recording = true);
  }

  Future<void> _evaluate() async {
    if (_transcript.trim().isEmpty) return;
    setState(() => _evaluating = true);
    try {
      final reply = await ref.read(aiClientProvider).ask(
        mode: 'speaking_eval',
        lang: context.lang,
        messages: [
          {'role': 'user', 'content': 'Question: ${_speakingPrompts[_prompt]}\nStudent answer (speech-to-text transcript): $_transcript'}
        ],
      );
      if (mounted) setState(() => _feedback = reply);
    } catch (e) {
      if (mounted) snack(context, e == 'quota' ? 'Daily AI limit reached' : '$e');
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Speaking Practice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(_speakingPrompts[_prompt], style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              TextButton.icon(onPressed: () => setState(() => _prompt = (_prompt + 1) % _speakingPrompts.length), icon: const Icon(Icons.shuffle), label: const Text('Next topic')),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _listen, icon: Icon(_listening ? Icons.stop : Icons.mic), label: Text(_listening ? 'Stop' : 'Speak your answer')),
        if (_transcript.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_transcript))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _evaluating || _listening ? null : _evaluate,
            icon: _evaluating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: const Text('AI speaking evaluation'),
          ),
        ],
        if (_feedback.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Card(color: cs.secondaryContainer, child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(_feedback)))),
        const Divider(height: 32),
        Text('Voice recorder', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _toggleRecord, icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record, color: Colors.red), label: Text(_recording ? 'Stop recording' : 'Record yourself'))),
          const SizedBox(width: 12),
          if (_player != null)
            IconButton.filledTonal(
              onPressed: () async {
                await _player!.seekTo(Duration.zero);
                await _player!.play();
              },
              icon: const Icon(Icons.play_arrow),
            ),
        ]),
        if (_audioPath != null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Listen back and compare with the model answer.', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Translation practice (AI checks the student's translation)
// ---------------------------------------------------------------------------
const _translationSentences = [
  ('আমি প্রতিদিন সকালে স্কুলে যাই।', 'bn→en'),
  ('বৃষ্টির কারণে খেলা বন্ধ হয়ে গেছে।', 'bn→en'),
  ('She has been studying English for two years.', 'en→bn'),
  ('If I had more time, I would learn programming.', 'en→bn'),
];

class TranslationPracticeScreen extends ConsumerStatefulWidget {
  const TranslationPracticeScreen({super.key});
  @override
  ConsumerState<TranslationPracticeScreen> createState() => _TranslationPracticeScreenState();
}

class _TranslationPracticeScreenState extends ConsumerState<TranslationPracticeScreen> {
  int _i = 0;
  final _ctl = TextEditingController();
  String _feedback = '';
  bool _busy = false;

  Future<void> _check() async {
    if (_ctl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final s = _translationSentences[_i];
    try {
      final r = await ref.read(aiClientProvider).ask(
        mode: 'translation',
        lang: context.lang,
        messages: [
          {'role': 'user', 'content': 'Direction: ${s.$2}\nSource: ${s.$1}\nStudent translation: ${_ctl.text.trim()}'}
        ],
      );
      if (mounted) setState(() => _feedback = r);
    } catch (e) {
      if (mounted) snack(context, e == 'quota' ? 'Daily AI limit reached' : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _translationSentences[_i];
    return Scaffold(
      appBar: AppBar(title: const Text('Translation Practice')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Chip(label: Text(s.$2)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.$1, style: Theme.of(context).textTheme.titleLarge))),
        const SizedBox(height: 12),
        TextField(controller: _ctl, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Type your translation…')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _check, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Check')),
        if (_feedback.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(_feedback)))),
        TextButton.icon(
          onPressed: () => setState(() {
            _i = (_i + 1) % _translationSentences.length;
            _ctl.clear();
            _feedback = '';
          }),
          icon: const Icon(Icons.skip_next),
          label: const Text('Next sentence'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily vocabulary + flashcards (data from Firestore `vocabulary`)
// ---------------------------------------------------------------------------
final vocabProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(contentRepoProvider).vocabulary());

class DailyVocabScreen extends ConsumerStatefulWidget {
  const DailyVocabScreen({super.key});
  @override
  ConsumerState<DailyVocabScreen> createState() => _DailyVocabScreenState();
}

class _DailyVocabScreenState extends ConsumerState<DailyVocabScreen> {
  final _tts = FlutterTts();
  int _card = 0;
  bool _flipped = false;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('dailyVocab'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        value: ref.watch(vocabProvider),
        builder: (words) {
          if (words.isEmpty) return const EmptyState(icon: Icons.translate);
          final today = words[DateTime.now().difference(DateTime(DateTime.now().year)).inDays % words.length];
          final w = words[_card % words.length];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(context.tr('dailyVocab'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _WordCard(word: today, onSpeak: (t) => _tts.speak(t)),
            const SizedBox(height: 24),
            Text('Flashcards ${(_card % words.length) + 1}/${words.length}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _flipped = !_flipped),
              child: Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: SizedBox(
                  height: 180,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_flipped ? '${w['meaningBn'] ?? ''}\n${w['meaningEn'] ?? ''}' : '${w['word'] ?? ''}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              OutlinedButton(onPressed: () => setState(() {_card = (_card - 1) % words.length; _flipped = false;}), child: const Icon(Icons.chevron_left)),
              const Text('Tap card to flip'),
              OutlinedButton(onPressed: () => setState(() {_card = (_card + 1) % words.length; _flipped = false;}), child: const Icon(Icons.chevron_right)),
            ]),
          ]);
        },
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.onSpeak});
  final Map<String, dynamic> word;
  final void Function(String) onSpeak;
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${word['word'] ?? ''}', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.volume_up), onPressed: () => onSpeak('${word['word'] ?? ''}')),
            ]),
            Text('${word['meaningBn'] ?? ''}  ${word['meaningEn'] ?? ''}'),
            if ((word['example'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('“${word['example']}”', style: const TextStyle(fontStyle: FontStyle.italic))),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// IELTS band calculator (Academic conversion tables)
// ---------------------------------------------------------------------------
double listeningBand(int raw) {
  const t = [(39, 9.0), (37, 8.5), (35, 8.0), (32, 7.5), (30, 7.0), (26, 6.5), (23, 6.0), (18, 5.5), (16, 5.0), (13, 4.5), (10, 4.0), (8, 3.5), (6, 3.0), (4, 2.5)];
  for (final e in t) {
    if (raw >= e.$1) return e.$2;
  }
  return raw >= 2 ? 2.0 : (raw >= 1 ? 1.0 : 0.0);
}

double readingBand(int raw) {
  const t = [(39, 9.0), (37, 8.5), (35, 8.0), (33, 7.5), (30, 7.0), (27, 6.5), (23, 6.0), (19, 5.5), (15, 5.0), (13, 4.5), (10, 4.0), (8, 3.5), (6, 3.0), (4, 2.5)];
  for (final e in t) {
    if (raw >= e.$1) return e.$2;
  }
  return raw >= 2 ? 2.0 : (raw >= 1 ? 1.0 : 0.0);
}

/// IELTS rounding: average to nearest half band; .25 rounds up to .5, .75 up to next whole.
double overallBand(double avg) => ((avg * 2) + 0.5).floor() / 2;

class BandCalculatorScreen extends StatefulWidget {
  const BandCalculatorScreen({super.key});
  @override
  State<BandCalculatorScreen> createState() => _BandCalculatorScreenState();
}

class _BandCalculatorScreenState extends State<BandCalculatorScreen> {
  double _l = 6, _r = 6, _w = 6, _s = 6;
  bool _useRaw = false;
  int _lRaw = 25, _rRaw = 25;

  @override
  Widget build(BuildContext context) {
    final l = _useRaw ? listeningBand(_lRaw) : _l;
    final r = _useRaw ? readingBand(_rRaw) : _r;
    final overall = overallBand((l + r + _w + _s) / 4);

    Widget bandSlider(String label, double v, ValueChanged<double> on) => Row(children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(child: Slider(value: v, min: 0, max: 9, divisions: 18, label: v.toString(), onChanged: on)),
          SizedBox(width: 32, child: Text(v.toString())),
        ]);

    Widget rawSlider(String label, int v, double band, ValueChanged<double> on) => Row(children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(child: Slider(value: v.toDouble(), min: 0, max: 40, divisions: 40, label: '$v', onChanged: on)),
          SizedBox(width: 64, child: Text('$v → $band')),
        ]);

    return Scaffold(
      appBar: AppBar(title: const Text('IELTS Band Calculator')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SwitchListTile(title: const Text('Enter raw scores (out of 40) for Listening & Reading'), value: _useRaw, onChanged: (v) => setState(() => _useRaw = v)),
        if (_useRaw) ...[
          rawSlider('Listening', _lRaw, listeningBand(_lRaw), (v) => setState(() => _lRaw = v.round())),
          rawSlider('Reading', _rRaw, readingBand(_rRaw), (v) => setState(() => _rRaw = v.round())),
        ] else ...[
          bandSlider('Listening', _l, (v) => setState(() => _l = v)),
          bandSlider('Reading', _r, (v) => setState(() => _r = v)),
        ],
        bandSlider('Writing', _w, (v) => setState(() => _w = v)),
        bandSlider('Speaking', _s, (v) => setState(() => _s = v)),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Text('Overall band'),
              Text(overall.toStringAsFixed(1), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Raw-score conversion uses the Academic tables and is an estimate; real tests may vary slightly.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
