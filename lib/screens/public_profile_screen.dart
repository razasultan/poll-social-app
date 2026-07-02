import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/branding.dart';
import '../core/widgets/brand_mark.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../widgets/poll_card.dart';

/// Public-facing profile page at `/u/:username`.
///
/// Accessible without auth. Content is constrained to a readable column width.
/// Unauthenticated visitors see a sticky bottom bar prompting them to join.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  static const double _maxWidth = 680;

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

  bool get _isGuest => Supabase.instance.client.auth.currentUser == null;

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
    context.go(userId != null ? '/home/user/$userId' : '/home');
  }

  Widget _constrained(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: PublicProfileScreen._maxWidth,
      ),
      child: child,
    ),
  );

  // ── App bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(tile: true, size: 32),
          const SizedBox(width: 10),
          const BrandWordmark(),
        ],
      ),
    );
  }

  // ── Guest bottom bar ─────────────────────────────────────────────────────

  Widget _buildGuestBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    const maxW = PublicProfileScreen._maxWidth;
    final hPad = screenW > maxW ? (screenW - maxW) / 2 : 20.0;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.primary,
          border: Border(
            top: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
          ),
        ),
        padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
        child: Row(
          children: [
            BrandMark(size: 28, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Have your say on everything',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Vote on polls, follow creators, start debates.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => context.push('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              child: const Text('Log in'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => context.push('/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
              child: const Text('Sign up'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      bottomNavigationBar: _isGuest ? _buildGuestBottomBar(context) : null,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: PublicProfileScreen._maxWidth,
                    ),
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
              ),
            )
          else ...[
            // ── Profile header (image, avatar, name, bio) ────────────────
            SliverToBoxAdapter(child: _buildHeader(theme, cs)),

            // ── Polls label ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _constrained(
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    'Polls',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),

            // ── Poll cards — SliverList matches authenticated profile ──────
            if (_polls.isEmpty)
              SliverToBoxAdapter(
                child: _constrained(
                  Padding(
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
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _constrained(
                    PollCard(
                      poll: _polls[i],
                      onPollTap: () {
                        final pollId = _polls[i]['id']?.toString();
                        if (pollId == null) return;
                        context.go('/home/poll/$pollId');
                      },
                    ),
                  ),
                  childCount: _polls.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }

  // ── Profile header widget ─────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final profile = _profile!;
    final displayName = profile['display_name']?.toString() ?? '';
    final username = profile['username']?.toString() ?? '';
    final bio = profile['bio']?.toString() ?? '';
    final avatarUrl = profile['avatar_url']?.toString();
    final headerUrl = profile['header_url']?.toString();
    final nameOrUsername = displayName.isNotEmpty ? displayName : username;
    final initials = nameOrUsername.isNotEmpty
        ? nameOrUsername[0].toUpperCase()
        : '?';

    return _constrained(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header image
          if (headerUrl != null && headerUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 3,
                child: Image.network(
                  headerUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, e) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Avatar + name
          Padding(
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
                          initials,
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
                if (!_isGuest)
                  TextButton.icon(
                    onPressed: _openInApp,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open in app'),
                  ),
              ],
            ),
          ),

          // Bio
          if (bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(bio, style: theme.textTheme.bodyMedium),
            ),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Divider(),
          ),
        ],
      ),
    );
  }
}
