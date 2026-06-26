import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/widgets/timeline_column.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';
import '../widgets/poll_card.dart';
import 'create_poll_screen.dart';
import 'poll_detail_screen.dart';
import 'settings_screen.dart';

/// Normalizes a raw profile row into a `Map<String, dynamic>`. Exposed for testing.
Map<String, dynamic> asProfileMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

/// Normalizes a raw list of poll rows into `List<Map<String, dynamic>>`. Exposed for testing.
List<Map<String, dynamic>> asPollList(dynamic raw) {
  if (raw is! List) return [];
  return raw.map((e) {
    if (e is Map<String, dynamic>) return e;
    if (e is Map) return Map<String, dynamic>.from(e);
    return <String, dynamic>{};
  }).toList();
}

/// Unwraps the embedded `polls` map from each `likes` row into a flat list. Exposed for testing.
List<Map<String, dynamic>> asLikedPollList(dynamic raw) {
  if (raw is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    final row = e is Map<String, dynamic>
        ? e
        : (e is Map ? Map<String, dynamic>.from(e) : null);
    if (row == null) continue;
    final pollRaw = row['polls'];
    final poll = pollRaw is Map<String, dynamic>
        ? pollRaw
        : (pollRaw is Map ? Map<String, dynamic>.from(pollRaw) : null);
    if (poll != null && poll.isNotEmpty) out.add(poll);
  }
  return out;
}

/// Maps a profile-load error to a user-facing message. Exposed for testing.
String profileErrorMessage(Object e) {
  if (e is PostgrestException) {
    final code = e.code;
    if (code == 'PGRST116' || e.message.toLowerCase().contains('0 rows')) {
      return 'Profile not found.';
    }
    return e.message.isNotEmpty ? e.message : 'Could not load profile.';
  }
  return 'Could not load profile. Check your connection.';
}

/// True when a follow-insert [PostgrestException] indicates a duplicate row. Exposed for testing.
bool isDuplicateFollowError(PostgrestException e) {
  final code = e.code ?? '';
  if (code == '23505') return true;
  final msg = e.message.toLowerCase();
  return msg.contains('duplicate') ||
      msg.contains('unique') ||
      msg.contains('already exists');
}

/// Profile header and authored polls for [userId].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId, this.reloadToken});

  final String userId;

  /// Bumped by an ancestor (e.g. after publishing a poll) to trigger a reload
  /// even while this screen is kept alive in an [IndexedStack].
  final ValueListenable<int>? reloadToken;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final ProfileService _profileService = ProfileService();
  final FeedService _feedService = FeedService();
  final SocialService _socialService = SocialService();

  late TabController _tabController;
  int? _lastReloadToken;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _polls = [];
  List<Map<String, dynamic>> _likedPolls = [];

  int _followersCount = 0;
  int _followingCount = 0;
  bool _isFollowing = false;
  bool _followBusy = false;
  int _loadGeneration = 0;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  bool get _isOwnProfile {
    final me = _currentUserId;
    return me != null && me == widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isOwnProfile ? 2 : 1, vsync: this);
    _tabController.addListener(_onTabChanged);
    _lastReloadToken = widget.reloadToken?.value;
    widget.reloadToken?.addListener(_onReloadTokenChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    widget.reloadToken?.removeListener(_onReloadTokenChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onReloadTokenChanged() {
    final value = widget.reloadToken?.value;
    if (value == null || value == _lastReloadToken) return;
    _lastReloadToken = value;
    _load();
  }

  Map<String, dynamic> _asProfileMap(dynamic raw) => asProfileMap(raw);

  List<Map<String, dynamic>> _asPollList(dynamic raw) => asPollList(raw);

  List<Map<String, dynamic>> _asLikedPollList(dynamic raw) =>
      asLikedPollList(raw);

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rawProfile = await _profileService.getProfile(widget.userId);
      if (!mounted || gen != _loadGeneration) return;

      final me = _currentUserId;
      final publicOnly = me == null || me != widget.userId;
      final rawPolls = await _feedService.getPollsForUser(
        widget.userId,
        publicOnly: publicOnly,
      );
      if (!mounted || gen != _loadGeneration) return;

      var likedPolls = <Map<String, dynamic>>[];
      if (_isOwnProfile) {
        try {
          final rawLiked = await _socialService.getLikedPollsForUser(
            widget.userId,
          );
          likedPolls = _asLikedPollList(rawLiked);
        } catch (_) {
          likedPolls = [];
        }
      }
      if (!mounted || gen != _loadGeneration) return;

      var followers = 0;
      var following = 0;
      var followingUser = false;

      try {
        followers = await _socialService.getFollowersCount(widget.userId);
        following = await _socialService.getFollowingCount(widget.userId);
      } catch (_) {
        followers = 0;
        following = 0;
      }
      if (!mounted || gen != _loadGeneration) return;

      if (me != null && me != widget.userId) {
        try {
          followingUser = await _socialService.getFollowStatus(
            followerId: me,
            followingId: widget.userId,
          );
        } catch (_) {
          followingUser = false;
        }
      }

      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _profile = _asProfileMap(rawProfile);
        _polls = _asPollList(rawPolls);
        _likedPolls = likedPolls;
        _followersCount = followers;
        _followingCount = following;
        _isFollowing = followingUser;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(e);
      });
    }
  }

  Future<void> _openCreatePoll() async {
    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (context) => const CreatePollScreen(),
          ),
        );
        if (created == true) await _load();
      },
    );
  }

  String _errorMessage(Object e) => profileErrorMessage(e);

  bool _isDuplicateFollowError(PostgrestException e) =>
      isDuplicateFollowError(e);

  Future<void> _reloadFollowRelationship() async {
    final me = _currentUserId;
    if (me == null || me == widget.userId) return;

    try {
      final status = await _socialService.getFollowStatus(
        followerId: me,
        followingId: widget.userId,
      );
      final followers = await _socialService.getFollowersCount(widget.userId);
      if (!mounted) return;
      setState(() {
        _isFollowing = status;
        _followersCount = followers;
      });
    } catch (_) {
      /* Best-effort refresh */
    }
  }

  Future<void> _toggleFollow() async {
    if (_isOwnProfile || _followBusy) return;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final me = _currentUserId;
        if (me == null || _isOwnProfile || _followBusy) return;

        setState(() => _followBusy = true);
        try {
          if (_isFollowing) {
            await _socialService.unfollowUser(
              followerId: me,
              followingId: widget.userId,
            );
            if (!mounted) return;
            setState(() {
              _isFollowing = false;
              _followersCount = (_followersCount > 0) ? _followersCount - 1 : 0;
            });
          } else {
            await _socialService.followUser(
              followerId: me,
              followingId: widget.userId,
            );
            if (!mounted) return;
            setState(() {
              _isFollowing = true;
              _followersCount++;
            });
          }
        } on PostgrestException catch (e) {
          if (!mounted) return;
          if (_isFollowing) {
            AppToast.error(
              context,
              e.message.isNotEmpty ? e.message : 'Could not unfollow.',
            );
            await _reloadFollowRelationship();
          } else {
            if (_isDuplicateFollowError(e)) {
              await _reloadFollowRelationship();
              if (!mounted) return;
              AppToast.warning(context, 'Already following this profile.');
            } else {
              AppToast.error(
                context,
                e.message.isNotEmpty ? e.message : 'Could not follow.',
              );
            }
          }
        } catch (_) {
          if (!mounted) return;
          AppToast.error(context, 'Network error. Try again.');
          if (_isFollowing) {
            await _reloadFollowRelationship();
          }
        } finally {
          if (mounted) setState(() => _followBusy = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_isOwnProfile && _currentUserId != null)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: TimelineColumn(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: cs.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.tonal(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _ProfileHeader(
                        profile: _profile!,
                        followers: _followersCount,
                        following: _followingCount,
                        pollCount: _polls.length,
                        showFollow: !_isOwnProfile,
                        isFollowing: _isFollowing,
                        followBusy: _followBusy,
                        onFollowTap: _toggleFollow,
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ProfileTabBarDelegate(
                        TabBar(
                          controller: _tabController,
                          indicatorColor: cs.primary,
                          indicatorWeight: 3,
                          indicatorSize: TabBarIndicatorSize.label,
                          labelColor: cs.onSurface,
                          unselectedLabelColor: cs.onSurfaceVariant,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: [
                            const Tab(text: 'Polls'),
                            if (_isOwnProfile) const Tab(text: 'Liked'),
                          ],
                        ),
                        backgroundColor: cs.surface,
                        borderColor: cs.outlineVariant,
                      ),
                    ),
                    if (_isOwnProfile && _tabController.index == 1)
                      ..._pollListSlivers(
                        polls: _likedPolls,
                        emptyMessage: 'Polls you like will show up here',
                        emptyIcon: Icons.favorite_border_rounded,
                      )
                    else
                      ..._pollListSlivers(
                        polls: _polls,
                        emptyMessage: _isOwnProfile
                            ? "You haven't posted any polls yet"
                            : "This account hasn't posted any polls yet",
                        emptyIcon: Icons.how_to_vote_outlined,
                        showCreateCta: _isOwnProfile,
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _pollListSlivers({
    required List<Map<String, dynamic>> polls,
    required String emptyMessage,
    IconData emptyIcon = Icons.how_to_vote_outlined,
    bool showCreateCta = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (polls.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    emptyIcon,
                    size: 40,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (showCreateCta) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _openCreatePoll,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create a poll'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final poll = polls[index];
            return PollCard(
              poll: poll,
              showTrendingScore: false,
              onPollTap: () {
                final id = poll['id']?.toString();
                if (id == null || id.isEmpty) return;
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => PollDetailScreen(pollId: id),
                  ),
                );
              },
            );
          }, childCount: polls.length),
        ),
      ),
    ];
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.followers,
    required this.following,
    required this.pollCount,
    required this.showFollow,
    required this.isFollowing,
    required this.followBusy,
    required this.onFollowTap,
  });

  final Map<String, dynamic> profile;
  final int followers;
  final int following;
  final int pollCount;
  final bool showFollow;
  final bool isFollowing;
  final bool followBusy;
  final VoidCallback onFollowTap;

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

  /// "Month Year" the profile was created, or `null` if unavailable.
  static String? _joinedLabel(dynamic raw) {
    final at = raw == null ? null : DateTime.tryParse(raw.toString());
    if (at == null) return null;
    return '${_months[at.month - 1]} ${at.year}';
  }

  /// "Month Day, Year" the profile owner was born, or `null` if unset.
  static String? _birthLabel(dynamic raw) {
    final at = raw == null ? null : DateTime.tryParse(raw.toString());
    if (at == null) return null;
    return '${_months[at.month - 1]} ${at.day}, ${at.year}';
  }

  /// Display label for a website URL: strips the scheme and trailing slash.
  static String _websiteLabel(String url) {
    var label = url.replaceFirst(RegExp(r'^https?://'), '');
    if (label.endsWith('/')) label = label.substring(0, label.length - 1);
    return label;
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final username = profile['username']?.toString() ?? 'Unknown';
    final displayName = profile['display_name']?.toString() ?? '';
    final bio = profile['bio']?.toString() ?? '';
    final location = [profile['city'], profile['country']]
        .map((v) => v?.toString().trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(', ');
    final avatarUrl = profile['avatar_url']?.toString();
    final headerUrl = profile['header_url']?.toString();
    final joined = _joinedLabel(profile['created_at']);
    final born = _birthLabel(profile['birth_date']);
    final website = profile['website']?.toString().trim() ?? '';
    const avatarRadius = 38.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // X-style cover banner with the avatar overlapping its bottom edge.
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
            if (showFollow)
              Positioned(
                right: 16,
                bottom: -16,
                child: OutlinedButton(
                  onPressed: followBusy ? null : onFollowTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isFollowing ? cs.onSurface : cs.surface,
                    backgroundColor: isFollowing
                        ? Colors.transparent
                        : cs.onSurface,
                    side: BorderSide(
                      color: isFollowing ? cs.outlineVariant : cs.onSurface,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 10,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: followBusy
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isFollowing ? cs.onSurface : cs.surface,
                          ),
                        )
                      : Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
          ],
        ),
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
                  born != null ||
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
                        onTap: () => _openWebsite(website),
                      ),
                    if (born != null)
                      _MetaChip(icon: Icons.cake_outlined, label: 'Born $born'),
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
                  _InlineStat(label: 'Following', value: following),
                  _StatDivider(),
                  _InlineStat(label: 'Followers', value: followers),
                  _StatDivider(),
                  _InlineStat(label: 'Polls', value: pollCount),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// "**12** Followers" inline stat, X-profile style.
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

/// Thin vertical separator between [_InlineStat]s.
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

/// Small icon + label pair used for location / join date metadata.
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

/// Tappable variant of [_MetaChip] used for the profile's website link.
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

/// Pins the profile's Polls/Liked [TabBar] beneath the header, X-style.
class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  _ProfileTabBarDelegate(
    this.tabBar, {
    required this.backgroundColor,
    required this.borderColor,
  });

  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor ||
        borderColor != oldDelegate.borderColor;
  }
}

/// Soft decorative circle used to add depth to the cover banner.
class _GhostCircle extends StatelessWidget {
  const _GhostCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
