import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/models.dart';
import '../../features/admin/admin_screens.dart';
import '../../features/ai_tutor/ai_tutor_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/content/content_screens.dart';
import '../../features/content/viewers.dart';
import '../../features/courses/course_screens.dart';
import '../../features/english/english_screens.dart';
import '../../features/exam/exam_screens.dart';
import '../../features/home/home_screen.dart';
import '../../features/live/live_screens.dart';
import '../../features/premium/premium_screens.dart';
import '../../features/profile/profile_screens.dart';
import '../../features/tools/tools_screens.dart';
import '../providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, __) => refresh.value++);
  ref.listen(appUserProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Study BD')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            Text('Page not found: ${state.uri}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Go home')),
          ]),
        ),
      ),
    ),
    observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      if (auth.isLoading) return null;
      final loggedIn = auth.valueOrNull != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn) return onLogin ? null : '/login';
      if (onLogin) return '/';
      if (state.matchedLocation.startsWith('/admin') && !ref.read(isAdminProvider)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),

      // Content hubs: /hub/academic -> /hub/academic/7 -> /list/academic/7/mcq
      GoRoute(path: '/hub/:section', builder: (_, s) => HubScreen(sectionId: s.pathParameters['section']!)),
      GoRoute(path: '/hub/:section/:group', builder: (_, s) => HubScreen(sectionId: s.pathParameters['section']!, groupId: s.pathParameters['group'])),
      GoRoute(
        path: '/list/:section/:group/:category',
        builder: (_, s) => ContentListScreen(
          section: s.pathParameters['section']!,
          group: s.pathParameters['group']!,
          category: s.pathParameters['category']!,
          title: s.uri.queryParameters['t'] ?? '',
        ),
      ),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),

      // Viewers
      GoRoute(path: '/pdf', builder: (_, s) => PdfViewerScreen(item: s.extra as ContentItem)),
      GoRoute(path: '/video', builder: (_, s) => VideoScreen(args: s.extra as VideoArgs)),
      GoRoute(path: '/image', builder: (_, s) => ImageViewerScreen(item: s.extra as ContentItem)),
      GoRoute(path: '/note', builder: (_, s) => NoteScreen(item: s.extra as ContentItem)),

      // English / IELTS
      GoRoute(path: '/speaking', builder: (_, __) => const SpeakingPracticeScreen()),
      GoRoute(path: '/translation', builder: (_, __) => const TranslationPracticeScreen()),
      GoRoute(path: '/vocab', builder: (_, __) => const DailyVocabScreen()),
      GoRoute(path: '/band', builder: (_, __) => const BandCalculatorScreen()),

      // AI
      GoRoute(path: '/ai', builder: (_, s) => AiTutorScreen(initialMode: s.uri.queryParameters['mode'])),

      // Exams
      GoRoute(path: '/exam/:id', builder: (_, s) => ExamScreen(examId: s.pathParameters['id']!)),
      GoRoute(path: '/result', builder: (_, s) => ResultScreen(args: s.extra as ResultArgs)),
      GoRoute(path: '/leaderboard/:id', builder: (_, s) => LeaderboardScreen(examId: s.pathParameters['id']!)),
      GoRoute(path: '/analysis', builder: (_, __) => const PerformanceScreen()),
      GoRoute(path: '/dailyquiz', builder: (_, __) => const DailyQuizScreen()),

      // Courses
      GoRoute(path: '/course/:id', builder: (_, s) => CourseDetailScreen(courseId: s.pathParameters['id']!)),

      // Live
      GoRoute(path: '/live', builder: (_, __) => const LiveListScreen()),
      GoRoute(path: '/live/:id', builder: (_, s) => LiveRoomScreen(liveId: s.pathParameters['id']!)),

      // Premium & payments
      GoRoute(path: '/premium', builder: (_, __) => const PremiumScreen()),
      GoRoute(path: '/pay', builder: (_, s) => PaymentScreen(args: s.extra as PaymentArgs)),

      // Profile
      GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksScreen()),
      GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
      GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),

      // Tools
      GoRoute(path: '/tools/:tool', builder: (_, s) => ToolHost(tool: s.pathParameters['tool']!)),

      // Admin
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
      GoRoute(path: '/admin/:page', builder: (_, s) => AdminPageHost(page: s.pathParameters['page']!)),
    ],
  );
});
