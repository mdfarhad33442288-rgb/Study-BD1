import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers.dart';

/// Google's public TEST ad units. They are used in debug builds and whenever
/// no real unit id is configured in Firestore `config/app.ads`.
class _Test {
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const appOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const native = 'ca-app-pub-3940256099942544/2247696110';
}

class AdsService {
  AdsService._();
  static final instance = AdsService._();

  bool enabled = true;
  bool Function() isPremium = () => false;
  Map<String, dynamic> _cfg = {};

  InterstitialAd? _inter;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  int _screenOpens = 0;
  DateTime _lastInter = DateTime.fromMillisecondsSinceEpoch(0);
  bool _showingFullScreen = false;

  Future<void> init() async {
    await MobileAds.instance.initialize();
  }

  void applyConfig(Map<String, dynamic> cfg) {
    _cfg = Map<String, dynamic>.from(cfg['ads'] ?? {});
    enabled = _cfg['enabled'] ?? true;
    _preloadAll();
  }

  String _unit(String key, String test) {
    final v = (_cfg[key] ?? '') as String;
    return (kDebugMode || v.isEmpty) ? test : v;
  }

  String get bannerId => _unit('banner', _Test.banner);
  String get nativeId => _unit('native', _Test.native);
  bool get active => enabled && !isPremium();

  void _preloadAll() {
    if (!active) return;
    _loadInterstitial();
    _loadRewarded();
    _loadAppOpen();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _unit('interstitial', _Test.interstitial),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (a) => _inter = a, onAdFailedToLoad: (_) => _inter = null),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _unit('rewarded', _Test.rewarded),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: (a) => _rewarded = a, onAdFailedToLoad: (_) => _rewarded = null),
    );
  }

  void _loadAppOpen() {
    AppOpenAd.load(
      adUnitId: _unit('appOpen', _Test.appOpen),
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(onAdLoaded: (a) => _appOpen = a, onAdFailedToLoad: (_) => _appOpen = null),
    );
  }

  /// Call whenever the user opens a piece of content. Shows an interstitial
  /// every 4th open, at most once per 2 minutes (keeps UX and policy-safe).
  void maybeShowInterstitial() {
    if (!active) return;
    _screenOpens++;
    if (_screenOpens % 4 != 0) return;
    if (DateTime.now().difference(_lastInter).inSeconds < 120) return;
    final ad = _inter;
    if (ad == null) return;
    _inter = null;
    _showingFullScreen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showingFullScreen = false;
        _lastInter = DateTime.now();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _showingFullScreen = false;
        _loadInterstitial();
      },
    );
    ad.show();
  }

  /// Returns true if the user earned the reward (or ads are off/unavailable
  /// and `grantIfUnavailable` is set).
  Future<bool> showRewarded({bool grantIfUnavailable = false}) async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return grantIfUnavailable;
    }
    _rewarded = null;
    var earned = false;
    _showingFullScreen = true;
    final done = ValueNotifier(false);
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showingFullScreen = false;
        _loadRewarded();
        done.value = true;
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _showingFullScreen = false;
        done.value = true;
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    while (!done.value) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return earned;
  }

  void showAppOpen() {
    if (!active || _showingFullScreen) return;
    final ad = _appOpen;
    if (ad == null) {
      _loadAppOpen();
      return;
    }
    _appOpen = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
    );
    ad.show();
  }
}

/// Shows App Open ads when the app returns to the foreground.
class AppOpenObserver with WidgetsBindingObserver {
  DateTime _paused = DateTime.now();
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _paused = DateTime.now();
    if (s == AppLifecycleState.resumed && DateTime.now().difference(_paused).inSeconds > 30) {
      AdsService.instance.showAppOpen();
    }
  }
}

class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});
  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _ad;

  @override
  void initState() {
    super.initState();
    if (AdsService.instance.active) {
      _ad = BannerAd(
        adUnitId: AdsService.instance.bannerId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) => mounted ? setState(() {}) : null,
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            _ad = null;
          },
        ),
      )..load();
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(isPremiumProvider);
    if (premium || _ad == null) return const SizedBox.shrink();
    return SizedBox(width: _ad!.size.width.toDouble(), height: _ad!.size.height.toDouble(), child: AdWidget(ad: _ad!));
  }
}

class NativeAdTile extends ConsumerStatefulWidget {
  const NativeAdTile({super.key});
  @override
  ConsumerState<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends ConsumerState<NativeAdTile> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (AdsService.instance.active) {
      _ad = NativeAd(
        adUnitId: AdsService.instance.nativeId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small),
        listener: NativeAdListener(
          onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
          onAdFailedToLoad: (ad, _) => ad.dispose(),
        ),
      )..load();
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isPremiumProvider) || !_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 90, maxHeight: 120), child: AdWidget(ad: _ad!)),
    );
  }
}
