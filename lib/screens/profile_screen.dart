import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../services/social_service.dart';
import '../widgets/poll_card.dart';
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
    final row = e is Map<String, dynamic> ? e : (e is Map ? Map<String, dynamic>.from(e) : null);
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

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  bool get _isOwnProfile {
    final me = _currentUserId;
    return me != null && me == widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isOwnProfile ? 2 : 1, vsync: this);
    _lastReloadToken = widget.reloadToken?.value;
    widget.reloadToken?.addListener(_onReloadTokenChanged);
    _load();
  }

  @override
  void dispose() {
    widget.reloadToken?.removeListener(_onReloadTokenChanged);
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

  List<Map<String, dynamic>> _asLikedPollList(dynamic raw) => asLikedPollList(raw);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rawProfile = await _profileService.getProfile(widget.userId);
      final me = _currentUserId;
      final publicOnly = me == null || me != widget.userId;
      final rawPolls =
          await _feedService.getPollsForUser(widget.userId, publicOnly: publicOnly);

      var likedPolls = <Map<String, dynamic>>[];
      if (_isOwnProfile) {
        try {
          final rawLiked = await _socialService.getLikedPollsForUser(widget.userId);
          likedPolls = _asLikedPollList(rawLiked);
        } catch (_) {
          likedPolls = [];
        }
      }

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

      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(e);
      });
    }
  }

  String _errorMessage(Object e) => profileErrorMessage(e);

  bool _isDuplicateFollowError(PostgrestException e) => isDuplicateFollowError(e);

  void _followSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
    final me = _currentUserId;
    if (me == null || _isOwnProfile || _followBusy) return;

    setState(() => _followBusy = true);
    try {
      if (_isFollowing) {
        await _socialService.unfollowUser(followerId: me, followingId: widget.userId);
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _followersCount = (_followersCount > 0) ? _followersCount - 1 : 0;
        });
      } else {
        await _socialService.followUser(followerId: me, followingId: widget.userId);
        if (!mounted) return;
        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (_isFollowing) {
        _followSnack(e.message.isNotEmpty ? e.message : 'Could not unfollow.');
        await _reloadFollowRelationship();
      } else {
        if (_isDuplicateFollowError(e)) {
          await _reloadFollowRelationship();
          _followSnack('Already following this profile.');
        } else {
          _followSnack(e.message.isNotEmpty ? e.message : 'Could not follow.');
        }
      }
    } catch (_) {
      if (!mounted) return;
      _followSnack('Network error. Try again.');
      if (_isFollowing) {
        await _reloadFollowRelationship();
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
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
                  MaterialPageRoute<void>(builder: (context) => const SettingsScreen()),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Polls'),
            if (_isOwnProfile) const Tab(text: 'Liked'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined, size: 48, color: cs.error),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.tonal(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPollListView(
                      polls: _polls,
                      emptyMessage: 'No polls yet',
                      header: _ProfileHeader(
                        profile: _profile!,
                        followers: _followersCount,
                        following: _followingCount,
                        pollCount: _polls.length,
                        showFollow: !_isOwnProfile && _currentUserId != null,
                        isFollowing: _isFollowing,
                        followBusy: _followBusy,
                        onFollowTap: _toggleFollow,
                      ),
                    ),
                    if (_isOwnProfile)
                      _buildPollListView(
                        polls: _likedPolls,
                        emptyMessage: 'No liked polls yet',
                      ),
                  ],
                ),
    );
  }

  Widget _buildPollListView({
    required List<Map<String, dynamic>> polls,
    required String emptyMessage,
    Widget? header,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          if (polls.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
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
                  },
                  childCount: polls.length,
                ),
              ),
            ),
        ],
      ),
    );
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
    const avatarRadius = 38.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // X-style cover banner with the avatar overlapping its bottom edge.
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary.withValues(alpha: 0.55), cs.primary.withValues(alpha: 0.18)],
                ),
              ),
            ),
            Positioned(
              left: 20,
              bottom: -avatarRadius,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage:
                      avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
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
                    backgroundColor: isFollowing ? Colors.transparent : cs.onSurface,
                    side: BorderSide(color: isFollowing ? cs.outlineVariant : cs.onSurface),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
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
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                '@$username',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  bio,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
              if (location.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 17, color: cs.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      location,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _InlineStat(label: 'Following', value: following),
                  const SizedBox(width: 18),
                  _InlineStat(label: 'Followers', value: followers),
                  const SizedBox(width: 18),
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
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

