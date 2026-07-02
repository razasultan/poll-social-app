import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/branding.dart';
import '../core/widgets/brand_mark.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../widgets/poll_card.dart';

/// Public-facing profile page at `/u/:username`.
///
/// Layout: pinned app-bar → header image with avatar straddling the fold
/// (bottom-right placement) → name/bio → 3-column stat strip → poll list.
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
  final SocialService _socialService = SocialService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _polls = [];
  int _followersCount = 0;
  int _totalVotes = 0;

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

      final results = await Future.wait([
        if (userId.isNotEmpty)
          _feedService.getPollsForUser(userId, publicOnly: true)
        else
          Future.value(<dynamic>[]),
        if (userId.isNotEmpty)
          _socialService.getFollowersCount(userId)
        else
          Future.value(0),
      ]);

      if (!mounted) return;

      final rawPolls = results[0] as List<dynamic>;
      final polls = rawPolls.whereType<Map<String, dynamic>>().toList();
      final followersCount = results[1] as int;

      int totalVotes = 0;
      for (final p in polls) {
        final analytics = p['poll_analytics'];
        final a = analytics is Map
            ? analytics
            : (analytics is List && analytics.isNotEmpty
                  ? analytics.first as Map?
                  : null);
        final v = a?['votes_count'];
        totalVotes += (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
      }

      setState(() {
        _profile = profile;
        _polls = polls;
        _followersCount = followersCount;
        _totalVotes = totalVotes;
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Formats large numbers: 1234 → "1.2K", 1234567 → "1.2M".
  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _constrained(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: PublicProfileScreen._maxWidth,
      ),
      child: child,
    ),
  );

  // ── App bar ───────────────────────────────────────────────────────────────

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

  // ── Guest bottom bar ──────────────────────────────────────────────────────

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
            SliverToBoxAdapter(child: _buildProfileHeader(theme, cs)),
            SliverToBoxAdapter(child: _buildStatsStrip(theme, cs)),
            SliverToBoxAdapter(child: _buildPollsEyebrow(theme, cs)),
            if (_polls.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyPolls(theme, cs))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _constrained(
                    PollCard(
                      poll: _polls[i],
                      onPollTap: () {
                        final id = _polls[i]['id']?.toString();
                        if (id != null) context.go('/home/poll/$id');
                      },
                    ),
                  ),
                  childCount: _polls.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ],
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────

  Widget _buildProfileHeader(ThemeData theme, ColorScheme cs) {
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

    const avatarRadius = 44.0;
    const avatarBorder = 3.0;
    const avatarTotal = avatarRadius + avatarBorder;

    Widget avatar = CircleAvatar(
      radius: avatarRadius,
      backgroundColor: cs.primaryContainer,
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(
              initials,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );

    // White/surface border ring around avatar — separates it from both
    // the header image above and the page background below.
    avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.surface, width: avatarBorder),
      ),
      child: avatar,
    );

    final hasHeader = headerUrl != null && headerUrl.isNotEmpty;

    return _constrained(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header image with avatar straddling the fold (bottom-right) ──
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Header image or gradient placeholder
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(4),
                ),
                child: AspectRatio(
                  aspectRatio: 3,
                  child: hasHeader
                      ? Image.network(
                          headerUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, st) =>
                              _buildHeaderGradient(cs),
                        )
                      : _buildHeaderGradient(cs),
                ),
              ),

              // Avatar — bottom-right, straddling the header fold.
              // The distinctive placement (right side instead of the
              // Twitter convention of left) keeps the name block clean.
              Positioned(bottom: -avatarTotal, right: 20, child: avatar),

              // Open-in-app for authenticated users
              if (!_isGuest)
                Positioned(
                  top: 10,
                  right: 10,
                  child: FilledButton.tonal(
                    onPressed: _openInApp,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.open_in_new_rounded, size: 14),
                        SizedBox(width: 6),
                        Text('Open in app'),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Space for the overlapping avatar
          SizedBox(height: avatarTotal + 12),

          // ── Name + username ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (displayName.isNotEmpty)
                  Text(
                    displayName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '@$username',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    bio,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Subtle primary-tinted gradient used when no header image is set.
  Widget _buildHeaderGradient(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.15),
            cs.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  // ── Stat strip ────────────────────────────────────────────────────────────

  Widget _buildStatsStrip(ThemeData theme, ColorScheme cs) {
    return _constrained(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: cs.outlineVariant),
          IntrinsicHeight(
            child: Row(
              children: [
                _StatCell(
                  theme: theme,
                  cs: cs,
                  value: _fmt(_polls.length),
                  label: 'POLLS',
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                _StatCell(
                  theme: theme,
                  cs: cs,
                  value: _fmt(_totalVotes),
                  label: 'VOTES',
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                _StatCell(
                  theme: theme,
                  cs: cs,
                  value: _fmt(_followersCount),
                  label: 'FOLLOWERS',
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Polls eyebrow ─────────────────────────────────────────────────────────

  Widget _buildPollsEyebrow(ThemeData theme, ColorScheme cs) {
    return _constrained(
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            Text(
              'POLLS',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPolls(ThemeData theme, ColorScheme cs) {
    return _constrained(
      Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No public polls yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stat cell ──────────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.theme,
    required this.cs,
    required this.value,
    required this.label,
  });

  final ThemeData theme;
  final ColorScheme cs;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
