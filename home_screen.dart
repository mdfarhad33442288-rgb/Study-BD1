import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/sections.dart';
import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/services/ads_service.dart';
import '../../core/widgets/common.dart';
import '../content/content_screens.dart';
import '../courses/course_screens.dart';
import '../exam/exam_screens.dart';
import '../profile/profile_screens.dart';
import '../tools/tools_screens.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [HomeTab(), CourseListTab(), ExamListTab(), ToolsTab(), ProfileTab()];
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: context.tr('home')),
          NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library), label: context.tr('courses')),
          NavigationDestination(icon: const Icon(Icons.quiz_outlined), selectedIcon: const Icon(Icons.quiz), label: context.tr('exams')),
          NavigationDestination(icon: const Icon(Icons.apps_outlined), selectedIcon: const Icon(Icons.apps), label: context.tr('tools')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.tr('profile')),
        ],
      ),
    );
  }
}

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = context.lang;
    final user = ref.watch(appUserProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final cfg = ref.watch(remoteConfigProvider).valueOrNull ?? {};
    final banner = (cfg['homeBanner'] ?? '') as String; // admin-editable announcement

    FeatureTile sec(SectionDef s) => FeatureTile(icon: s.icon, label: s.name(lang), color: s.color, onTap: () => context.push('/hub/${s.id}'));

    final tiles = <Widget>[
      sec(Sections.academic),
      sec(Sections.admission),
      sec(Sections.english),
      sec(Sections.ielts),
      FeatureTile(icon: Icons.smart_toy, label: context.tr('aiTutor'), color: const Color(0xFF00897B), onTap: () => context.push('/ai')),
      FeatureTile(icon: Icons.live_tv, label: context.tr('live'), color: const Color(0xFFD81B60), onTap: () => context.push('/live')),
      sec(Sections.library),
      sec(Sections.video),
      sec(Sections.career),
      sec(Sections.news),
      FeatureTile(icon: Icons.insights, label: lang == 'bn' ? 'পারফরম্যান্স' : 'Analysis', color: const Color(0xFF5D4037), onTap: () => context.push('/analysis')),
      FeatureTile(icon: Icons.workspace_premium, label: context.tr('premium'), color: const Color(0xFFF9A825), onTap: () => context.push('/premium')),
    ];

    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'bn' ? 'স্বাগতম' : 'Welcome', style: Theme.of(context).textTheme.bodyMedium),
              Text(user == null || user.isGuest || user.name.isEmpty ? context.tr('appName') : user.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ),
          if (user?.isPremium ?? false) Icon(Icons.workspace_premium, color: cs.tertiary),
        ]),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/search'),
          child: InputDecorator(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), suffixIcon: const Icon(Icons.mic_none), hintText: context.tr('search')),
            child: Text(context.tr('search'), style: TextStyle(color: cs.outline)),
          ),
        ),
        if (banner.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(color: cs.primaryContainer, child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Icon(Icons.campaign, color: cs.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(banner, style: TextStyle(color: cs.onPrimaryContainer))),
          ]))),
        ],
        if (user?.isGuest ?? false) ...[
          const SizedBox(height: 12),
          Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(context.tr('guestNotice')), trailing: TextButton(onPressed: () => ref.read(authRepoProvider).signOut(), child: Text(context.tr('login'))))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _QuickCard(icon: Icons.bolt, label: context.tr('dailyQuiz'), color: cs.secondaryContainer, onTap: () => context.push('/dailyquiz'))),
          const SizedBox(width: 12),
          Expanded(child: _QuickCard(icon: Icons.translate, label: context.tr('dailyVocab'), color: cs.tertiaryContainer, onTap: () => context.push('/vocab'))),
        ]),
        const SizedBox(height: 12),
        const Center(child: BannerAdWidget()),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: tiles,
        ),
        const SizedBox(height: 20),
        Text(Sections.news.name(lang), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _LatestNotices(),
      ]),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)))])),
        ),
      );
}

class _LatestNotices extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contentListProvider(('news', 'all', 'notice')));
    return async.when(
      data: (l) => l.isEmpty
          ? const SizedBox.shrink()
          : Column(children: [for (final c in l.take(5)) Padding(padding: const EdgeInsets.only(bottom: 8), child: ContentTile(item: c, playlist: l))]),
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
