import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/services/ads_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';

class StudyBdApp extends ConsumerStatefulWidget {
  const StudyBdApp({super.key});
  @override
  ConsumerState<StudyBdApp> createState() => _StudyBdAppState();
}

class _StudyBdAppState extends ConsumerState<StudyBdApp> {
  final _observer = AppOpenObserver();
  String? _initedUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_observer);
    AdsService.instance.isPremium = () => ref.read(isPremiumProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Remote config (ads ids, payment numbers, plans) – changes need no app update.
    ref.listen(remoteConfigProvider, (_, next) {
      final cfg = next.valueOrNull;
      if (cfg != null) AdsService.instance.applyConfig(cfg);
    });

    // Once signed in: register push token, count a daily visit.
    ref.listen(authStateProvider, (_, next) {
      final u = next.valueOrNull;
      if (u != null && u.uid != _initedUid) {
        _initedUid = u.uid;
        NotificationService.instance.init(u.uid);
        ref.read(contentRepoProvider).bumpStat('visits');
        ref.read(authRepoProvider).touchActive(u.uid);
      }
    });

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Study BD',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: const [Locale('bn'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        FirebaseAnalytics.instance; // ensure analytics is initialised
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
