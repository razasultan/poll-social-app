import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/branding.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../widgets/poll_card.dart';

/// Public-facing profile page, accessible at `/u/:username` without auth.
///
/// Resolves the username to a userId, loads the profile and their public
/// polls, and shows a read-only profile view. Visitors see a CTA to join
/// the app; authenticated users can follow or navigate normally.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final FeedService _feedService = FeedService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _polls = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _profileService.getProfileByUsername(
        widget.username,
      );
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loading = false;
          _error = 'This profile could not be found.';
        });
        return;
      }

      final userId = profile['id']?.toString() ?? '';
      final rawPolls = userId.isNotEmpty
          ? await _feedService.getPollsForUser(userId, publicOnly: true)
          : <dynamic>[];
      final polls = rawPolls.whereType<Map<String, dynamic>>().toList();

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _polls = polls;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load profile. Check your connection and try again.';
      });
    }
  }

  void _openInApp() {
    final userId = _profile?['id']?.toString();
    if (userId == null) {
      context.go('/home');
      return;
    }
    // If we're already inside the shell (e.g. came from a deep link),
    // navigate within it; otherwise push into the home branch.
    context.go('/home/user/$userId');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGuest = Supabase.instance.client.auth.currentUser == null;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(Branding.appName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_off_outlined,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: Text('Go to ${Branding.appName}'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;
    final displayName = profile['display_name']?.toString() ?? '';
    final username = profile['username']?.toString() ?? '';
    final bio = profile['bio']?.toString() ?? '';
    final avatarUrl = profile['avatar_url']?.toString();
    final headerUrl = profile['header_url']?.toString();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: headerUrl != null && headerUrl.isNotEmpty ? 160 : 0,
            pinned: true,
            title: Text(displayName.isNotEmpty ? displayName : '@$username'),
            actions: [
              TextButton.icon(
                onPressed: _openInApp,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(
                  isGuest ? 'Join ${Branding.appName}' : 'Open in app',
                ),
              ),
            ],
            flexibleSpace: headerUrl != null && headerUrl.isNotEmpty
                ? FlexibleSpaceBar(
                    background: Image.network(
                      headerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, e) => const SizedBox.shrink(),
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Text(
                            (displayName.isNotEmpty ? displayName : username)
                                .characters
                                .first
                                .toUpperCase(),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (displayName.isNotEmpty)
                          Text(
                            displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        Text(
                          '@$username',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (bio.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(bio, style: theme.textTheme.bodyMedium),
              ),
            ),
          if (isGuest) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: OutlinedButton.icon(
                  onPressed: _openInApp,
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: Text('Join ${Branding.appName} to vote and follow'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Polls',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (_polls.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No public polls yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => PollCard(
                  poll: _polls[index],
                  onPollTap: () {
                    final pollId = _polls[index]['id']?.toString();
                    if (pollId == null) return;
                    // Open poll detail within the shell.
                    context.go('/home/poll/$pollId');
                  },
                ),
                childCount: _polls.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
