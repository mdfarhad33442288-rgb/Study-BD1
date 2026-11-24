import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../content/content_screens.dart';
import '../content/viewers.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile'))),
      body: ListView(children: [
        const SizedBox(height: 8),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: cs.primaryContainer,
            backgroundImage: (user?.photoUrl ?? '').isNotEmpty ? NetworkImage(user!.photoUrl) : null,
            child: (user?.photoUrl ?? '').isEmpty ? Icon(Icons.person, size: 40, color: cs.primary) : null,
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(user == null || user.name.isEmpty ? (user?.isGuest ?? false ? 'Guest' : '') : user.name, style: Theme.of(context).textTheme.titleLarge)),
        Center(child: Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 16),
        if (!(user?.isGuest ?? true)) ListTile(leading: const Icon(Icons.edit), title: const Text('Edit profile'), onTap: () => context.push('/edit-profile')),
        ListTile(leading: const Icon(Icons.bookmark), title: Text(context.tr('bookmarks')), onTap: () => context.push('/bookmarks')),
        ListTile(leading: const Icon(Icons.download_done), title: Text(context.tr('downloads')), onTap: () => context.push('/downloads')),
        ListTile(leading: Icon(Icons.workspace_premium, color: cs.tertiary), title: Text(user?.isPremium ?? false ? context.tr('premium') : context.tr('goPremium')), onTap: () => context.push('/premium')),
        ListTile(leading: const Icon(Icons.insights), title: Text(context.lang == 'bn' ? 'স্কোর ইতিহাস ও বিশ্লেষণ' : 'Score history & analysis'), onTap: () => context.push('/analysis')),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode),
          title: Text(context.tr('darkMode')),
          value: themeMode == ThemeMode.dark,
          onChanged: (v) => ref.read(themeModeProvider.notifier).set(v ? ThemeMode.dark : ThemeMode.light),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(context.tr('language')),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'bn', label: Text('বাংলা')), ButtonSegment(value: 'en', label: Text('EN'))],
            selected: {locale.languageCode},
            onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
          ),
        ),
        if (user?.isAdmin ?? false) ListTile(leading: const Icon(Icons.admin_panel_settings), title: Text(context.tr('admin')), onTap: () => context.push('/admin')),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout), title: Text(context.tr('logout')), onTap: () => ref.read(authRepoProvider).signOut()),
        const SizedBox(height: 24),
        Center(child: Text('Study BD v1.0.0', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _name = TextEditingController(text: ref.read(appUserProvider).valueOrNull?.name ?? '');
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Field(context.tr('name'), _name),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await ref.read(authRepoProvider).updateProfile(uid: ref.read(authStateProvider).valueOrNull!.uid, name: _name.text.trim());
                    if (context.mounted) context.pop();
                  },
            child: Text(context.tr('save')),
          ),
        ]),
      ),
    );
  }
}

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(bookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('bookmarks'))),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.bookmark_border)
          : ListView.separated(padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) => ContentTile(item: items[i], playlist: items)),
    );
  }
}

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    final dl = ref.watch(downloadServiceProvider);
    final list = dl.all();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('downloads'))),
      body: list.isEmpty
          ? const EmptyState(icon: Icons.download_for_offline)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final e = list[i];
                final item = ContentItem(id: e['id'], title: e['title'] ?? '', section: e['section'] ?? '', category: '', kind: e['kind'] ?? 'pdf');
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(kindIcon(item.kind)),
                    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await dl.remove(item.id);
                        if (mounted) setState(() {});
                      },
                    ),
                    onTap: () {
                      switch (item.kind) {
                        case 'pdf':
                          context.push('/pdf', extra: item);
                        case 'video':
                          context.push('/video', extra: VideoArgs(item, const []));
                        case 'image':
                          context.push('/image', extra: item);
                        default:
                          OpenFilex.open(e['path']);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
