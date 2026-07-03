import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/branding.dart';
import '../core/widgets/brand_mark.dart';
import '../core/widgets/timeline_column.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../widgets/poll_card.dart';

/// Public-facing profile page at `/u/:username`.
///
/// Uses [TimelineColumn] on the body — the same wrapper every other screen
/// uses — so the left/right column hairline borders and max-width constraint
/// are identical to the authenticated [ProfileScreen].
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final FeedService _feedService = FeedService();
  final SocialService _socialService = SocialService();

  bool _loading = true;
  String? _error;
  bool _isPrivate = false;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _polls = [];
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _followBusy = false;

  User? get _currentUser => Supabase.instance.client.auth.currentUser;
  bool get _isGuest => _currentUser == null;

  /// True when the viewer is looking at their own profile.
  bool get _isOwnProfile =>
      _currentUser != null &&
      _currentUser!.id == (_profile?['id']?.toString() ?? '');

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

      // Private profile: show the header but skip polls and social counts.
      if (profile['is_public'] != true) {
        final counts = await Future.wait([
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
        setState(() {
          _profile = profile;
          _followersCount = (counts[0] as num?)?.toInt() ?? 0;
          _followingCount = (counts[1] as num?)?.toInt() ?? 0;
          _loading = false;
          _isPrivate = true;
        });
        return;
      }

      final me = _currentUser?.id;
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
        if (userId.isNotEmpty && me != null && me != userId)
          _socialService.isFollowing(followerId: me, followingId: userId)
        else
          Future.value(false),
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
        _isFollowing = results[3] as bool;
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

  Future<void> _toggleFollow() async {
    final me = _currentUser?.id;
    final targetId = _profile?['id']?.toString();
    if (me == null || targetId == null || _followBusy) return;

    setState(() => _followBusy = true);
    try {
      if (_isFollowing) {
        await _socialService.unfollowUser(
          followerId: me,
          followingId: targetId,
        );
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _followersCount = (_followersCount - 1)
              .clamp(0, double.maxFinite)
              .toInt();
        });
      } else {
        await _socialService.followUser(followerId: me, followingId: targetId);
        if (!mounted) return;
        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  // ── Guest bottom bar ──────────────────────────────────────────────────────

  Widget _buildGuestBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    final hPad = screenW > TimelineColumn.maxWidth
        ? (screenW - TimelineColumn.maxWidth) / 2
        : 20.0;

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
      // Full-width app bar with brand logo — sits above TimelineColumn
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(tile: true, size: 32),
            const SizedBox(width: 10),
            const BrandWordmark(),
          ],
        ),
      ),
      bottomNavigationBar: _isGuest ? _buildGuestBottomBar(context) : null,
      // TimelineColumn provides the same left/right hairline borders and
      // max-width constraint that every other screen in the app uses.
      body: TimelineColumn(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _isPrivate
            ? _buildPrivate(theme, cs)
            : _error != null
            ? _buildError(theme, cs)
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(theme, cs)),
                  _buildPollsTab(cs),
                  if (_polls.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyPolls(theme, cs))
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => PollCard(
                          poll: _polls[i],
                          onPollTap: () {
                            final id = _polls[i]['id']?.toString();
                            if (id != null) context.go('/home/poll/$id');
                          },
                        ),
                        childCount: _polls.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  /// Shows the profile header (avatar, name, bio, stats) with a locked polls
  /// section — matching X's behaviour where identity info stays visible but
  /// content is gated when an account is private.
  Widget _buildPrivate(ThemeData theme, ColorScheme cs) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(theme, cs)),
        _buildPollsTab(cs),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'These polls are private',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This creator has not made their profile public yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, ColorScheme cs) {
    return Center(
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
    );
  }

  /// "Polls" section header styled as a single active tab — pinned below the
  /// profile header, matching the look of the authenticated ProfileScreen's
  /// TabBar (without needing a full TabController for a single tab).
  Widget _buildPollsTab(ColorScheme cs) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SingleTabDelegate(
        label: 'Polls',
        accentColor: cs.primary,
        backgroundColor: cs.surface,
        borderColor: cs.outlineVariant,
      ),
    );
  }

  Widget _buildEmptyPolls(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          'No public polls yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover banner — identical to authenticated ProfileScreen
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
                          username.isNotEmpty ? username[0].toUpperCase() : '?',
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
            // Follow / Following button — only for authenticated non-own profiles
            if (!_isGuest && !_isOwnProfile)
              Positioned(
                right: 16,
                bottom: -16,
                child: OutlinedButton(
                  onPressed: _followBusy ? null : _toggleFollow,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isFollowing ? cs.onSurface : cs.surface,
                    backgroundColor: _isFollowing
                        ? Colors.transparent
                        : cs.onSurface,
                    side: BorderSide(
                      color: _isFollowing ? cs.outlineVariant : cs.onSurface,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 10,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: _followBusy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _isFollowing ? cs.onSurface : cs.surface,
                          ),
                        )
                      : Text(
                          _isFollowing ? 'Following' : 'Follow',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
          ],
        ),

        // Name, username, bio, meta, stats
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

// ── Pinned "Polls" tab header ─────────────────────────────────────────────────

/// Renders a single sticky "Polls" label that looks like the active tab in
/// [ProfileScreen]'s TabBar — same height, same font weight, same primary-
/// color underline indicator.
class _SingleTabDelegate extends SliverPersistentHeaderDelegate {
  const _SingleTabDelegate({
    required this.label,
    required this.accentColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final Color accentColor;
  final Color backgroundColor;
  final Color borderColor;

  static const double _height = 46;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 3,
                width: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SingleTabDelegate old) =>
      label != old.label ||
      accentColor != old.accentColor ||
      backgroundColor != old.backgroundColor ||
      borderColor != old.borderColor;
}

// ── Helper widgets — mirror private widgets from profile_screen.dart ─────────

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
