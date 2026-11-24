import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';

/// Thin client for the `aiTutor` Cloud Function (API key stays on the server).
class AiClient {
  AiClient(this._fn);
  final FirebaseFunctions _fn;

  Future<String> ask({required String mode, required List<Map<String, String>> messages, required String lang}) async {
    try {
      final res = await _fn.httpsCallable('aiTutor', options: HttpsCallableOptions(timeout: const Duration(seconds: 60))).call({
        'mode': mode,
        'messages': messages,
        'lang': lang,
      });
      return (res.data['text'] ?? '') as String;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') throw 'quota';
      throw e.message ?? e.code;
    }
  }
}

final aiClientProvider = Provider((ref) => AiClient(ref.watch(functionsProvider)));

const aiModes = <String, (String, String, IconData)>{
  'general': ('Ask', 'প্রশ্ন করুন', Icons.chat),
  'homework': ('Homework', 'হোমওয়ার্ক', Icons.menu_book),
  'explain': ('Explain', 'ব্যাখ্যা', Icons.lightbulb),
  'mcq': ('Solve MCQ', 'MCQ সমাধান', Icons.checklist),
  'grammar': ('Grammar', 'গ্রামার', Icons.spellcheck),
  'speaking': ('Speaking', 'স্পিকিং', Icons.record_voice_over),
  'ielts': ('IELTS Coach', 'আইইএলটিএস কোচ', Icons.language),
  'math': ('Math', 'গণিত', Icons.calculate),
  'science': ('Science', 'বিজ্ঞান', Icons.science),
};

class _Msg {
  final bool user;
  final String text;
  const _Msg(this.user, this.text);
}

class AiTutorScreen extends ConsumerStatefulWidget {
  const AiTutorScreen({super.key, this.initialMode});
  final String? initialMode;
  @override
  ConsumerState<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends ConsumerState<AiTutorScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _msgs = <_Msg>[];
  late String _mode = aiModes.containsKey(widget.initialMode) ? widget.initialMode! : 'general';
  bool _busy = false, _listening = false;

  @override
  void dispose() {
    _stt.cancel();
    _tts.stop();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _ctl.text).trim();
    if (text.isEmpty || _busy) return;
    _ctl.clear();
    setState(() {
      _msgs.add(_Msg(true, text));
      _busy = true;
    });
    _toBottom();
    try {
      final history = _msgs.length > 12 ? _msgs.sublist(_msgs.length - 12) : _msgs;
      final reply = await ref.read(aiClientProvider).ask(
            mode: _mode,
            lang: context.lang,
            messages: [for (final m in history) {'role': m.user ? 'user' : 'assistant', 'content': m.text}],
          );
      if (mounted) setState(() => _msgs.add(_Msg(false, reply)));
    } catch (e) {
      if (!mounted) return;
      if (e == 'quota') {
        setState(() => _msgs.add(_Msg(false, context.lang == 'bn' ? 'আজকের ফ্রি সীমা শেষ। আনলিমিটেড ব্যবহারের জন্য প্রিমিয়াম নিন।' : 'Daily free limit reached. Go Premium for more questions.')));
      } else {
        setState(() => _msgs.add(_Msg(false, 'Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  /// Doubt solver: photo of a question -> on-device OCR -> AI.
  Future<void> _scan() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera);
    if (img == null) return;
    final rec = TextRecognizer();
    try {
      final r = await rec.processImage(InputImage.fromFilePath(img.path));
      if (r.text.trim().isEmpty) {
        if (mounted) snack(context, 'No text found');
      } else {
        _ctl.text = r.text.trim();
      }
    } finally {
      rec.close();
    }
  }

  Future<void> _voice() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!await _stt.initialize()) return;
    setState(() => _listening = true);
    await _stt.listen(
      localeId: context.lang == 'bn' ? 'bn_BD' : 'en_US',
      onResult: (r) {
        _ctl.text = r.recognizedWords;
        if (r.finalResult) setState(() => _listening = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('aiTutor')), actions: [
        IconButton(icon: const Icon(Icons.delete_sweep), onPressed: () => setState(_msgs.clear)),
      ]),
      body: Column(children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in aiModes.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(e.value.$3, size: 16),
                    label: Text(lang == 'bn' ? e.value.$2 : e.value.$1),
                    selected: _mode == e.key,
                    onSelected: (_) => setState(() => _mode = e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _msgs.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(lang == 'bn' ? 'যেকোনো প্রশ্ন করুন — আমি ধাপে ধাপে বুঝিয়ে দেব।' : 'Ask anything — I will explain step by step.', textAlign: TextAlign.center)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) return const Padding(padding: EdgeInsets.all(8), child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))));
                    final m = _msgs[i];
                    return Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(color: m.user ? cs.primaryContainer : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(m.text),
                          if (!m.user)
                            InkWell(
                              onTap: () async {
                                await _tts.setLanguage(lang == 'bn' ? 'bn-BD' : 'en-US');
                                await _tts.speak(m.text);
                              },
                              child: const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.volume_up, size: 18)),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.document_scanner), tooltip: 'Scan question', onPressed: _scan),
              IconButton(icon: Icon(_listening ? Icons.mic : Icons.mic_none), onPressed: _voice),
              Expanded(child: TextField(controller: _ctl, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Type your question…', isDense: true))),
              IconButton.filled(onPressed: _busy ? null : () => _send(), icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
