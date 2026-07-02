import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/branding.dart';
import '../core/widgets/brand_mark.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../widgets/poll_card.dart';

/// Public-facing profile page at `/u/:username`.
///
/// The profile header intentionally mirrors the authenticated [ProfileScreen]
/// header — same heights, avatar positioning, border treatment, meta chips,
/// and stat row — so the two views feel like the same product.
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
  int _followingCount = 0;

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
        if (userId.isNotEmpty)
          _socialService.getFollowingCount(userId)
        else
          Future.value(0),
      ]);

      if (!mounted) return;

      final polls = (results[0] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _profile = profile;
        _polls = polls;
        _followersCount = results[1] as int;
        _followingCount = results[2] as int;
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
            SliverToBoxAdapter(child: _buildHeader(theme, cs)),
            SliverToBoxAdapter(child: _constrained(const Divider(height: 1))),
            SliverToBoxAdapter(child: _buildPollsLabel(theme, cs)),
            if (_polls.isEmpty)
              SliverToBoxAdapter(
                child: _constrained(
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
                ),
              )
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

  // ── Profile header — mirrors _ProfileHeader in profile_screen.dart ────────

  Widget _buildHeader(ThemeData theme, ColorScheme cs) {
    final profile = _profile!;
    final username = profile['username']?.toString() ?? '';
    final displayName = profile['display_name']?.toString() ?? '';
    final bio = profile['bio']?.toString() ?? '';
    final avatarUrl = profile['avatar_url']?.toString();
    final headerUrl = profile['header_url']?.toString();
    final website = profile['website']?.toString().trim() ?? '';
    final location = [profile['city'], profile['country']]
        .map((v) => v?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(', ');
    final joined = _joinedLabel(profile['created_at']);
    const avatarRadius = 38.0;

    return _constrained(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover banner + overlapping avatar — identical to ProfileScreen
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRect(
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: headerUrl != null && headerUrl.isNotEmpty
                      ? Image.network(headerUrl, fit: BoxFit.cover)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary.withValues(alpha: 0.65),
                                cs.primary.withValues(alpha: 0.22),
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                right: -36,
                                top: -44,
                                child: _GhostCircle(
                                  size: 140,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              Positioned(
                                right: 60,
                                bottom: -50,
                                child: _GhostCircle(
                                  size: 90,
                                  color: const Color(
                                    0xFFF91880,
                                  ).withValues(alpha: 0.16),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              // Avatar — bottom-left, matching authenticated profile exactly
              Positioned(
                left: 20,
                bottom: -avatarRadius,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              // Open in app — authenticated users (same slot as Follow button)
              if (!_isGuest)
                Positioned(
                  right: 16,
                  bottom: -16,
                  child: OutlinedButton(
                    onPressed: _openInApp,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: cs.outlineVariant),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Open in app',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),

          // Name, username, bio, meta chips, stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, avatarRadius + 14, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty ? displayName : username,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
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
                  const SizedBox(height: 12),
                  Text(
                    bio,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ],
                if (location.isNotEmpty ||
                    website.isNotEmpty ||
                    joined != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (location.isNotEmpty)
                        _MetaChip(icon: Icons.place_outlined, label: location),
                      if (website.isNotEmpty)
                        _LinkChip(
                          icon: Icons.link_rounded,
                          label: _websiteLabel(website),
                          onTap: () async {
                            final uri = Uri.tryParse(website);
                            if (uri != null) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      if (joined != null)
                        _MetaChip(
                          icon: Icons.calendar_month_outlined,
                          label: 'Joined $joined',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Inline stats — same layout as authenticated profile
                Row(
                  children: [
                    _InlineStat(label: 'Following', value: _followingCount),
                    const _StatDivider(),
                    _InlineStat(label: 'Followers', value: _followersCount),
                    const _StatDivider(),
                    _InlineStat(label: 'Polls', value: _polls.length),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPollsLabel(ThemeData theme, ColorScheme cs) {
    return _constrained(
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(
          'Polls',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  // ── Date helpers ──────────────────────────────────────────────────────────

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String? _joinedLabel(dynamic raw) {
    final at = raw == null ? null : DateTime.tryParse(raw.toString());
    if (at == null) return null;
    return '${_months[at.month - 1]} ${at.year}';
  }

  static String _websiteLabel(String url) {
    var label = url.replaceFirst(RegExp(r'^https?://'), '');
    if (label.endsWith('/')) label = label.substring(0, label.length - 1);
    return label;
  }
}

// ── Helper widgets — mirror the private widgets in profile_screen.dart ───────

class _GhostCircle extends StatelessWidget {
  const _GhostCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: cs.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 14,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: cs.outlineVariant,
        ),
      ),
    );
  }
}
