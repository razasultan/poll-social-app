import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/profile_service.dart';
import 'auth/login_screen.dart';
import 'auth/signup_screen.dart';

const String _kAppVersion = '0.1.0';

/// Root settings: account, profile, privacy, and app info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();

  Map<String, dynamic>? _profile;
  bool _profileLoading = false;
  String? _profileError;

  StreamSubscription<AuthState>? _authSubscription;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    final uid = _user?.id;
    if (uid != null) {
      _profileLoading = true;
      _loadProfile(uid);
    }
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (!mounted) return;
      final uid = data.session?.user.id;
      if (uid != null && _profile == null && !_profileLoading) {
        setState(() => _profileLoading = true);
        _loadProfile(uid);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile(String userId) async {
    try {
      final raw = await _profileService.getProfile(userId);
      if (!mounted) return;
      setState(() {
        _profile = _asMap(raw);
        _profileLoading = false;
        _profileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError = _errorLabel(e);
      });
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  String _errorLabel(Object e) {
    if (e is PostgrestException && e.message.isNotEmpty) return e.message;
    return 'Something went wrong. Try again.';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmLogout() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text(
          'You will need to sign in again to post or manage your profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await _authService.signOut();
    } catch (e) {
      if (!mounted) return;
      _snack(_errorLabel(e));
      return;
    }

    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
  }

  Future<void> _openEditProfile() async {
    final uid = _user?.id;
    if (uid == null) {
      _snack('Sign in to edit your profile.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _EditProfileSheet(
            userId: uid,
            initialProfile: _profile ?? {},
            profileService: _profileService,
            onSaved: () {
              _snack('Profile updated');
              _loadProfile(uid);
            },
          ),
        );
      },
    );
  }

  void _openBlockedUsers() {
    final uid = _user?.id;
    if (uid == null) {
      _snack('Sign in to manage blocked users.');
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const BlockedUsersScreen()),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About Poll Social'),
        content: const Text(
          'Discover and vote on polls from people you follow. '
          'Manage your profile and privacy here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = _user?.email;
    final signedIn = _user != null;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 48,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Log in to manage your account and settings',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text('Login'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      ),
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (signedIn && _profileLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (signedIn && _profileError != null && !_profileLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Material(
                color: cs.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: cs.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _profileError!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _loadProfile(_user!.id),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _SectionHeader(label: 'Account', colorScheme: cs),
          _SettingsCard(
            colorScheme: cs,
            children: [
              ListTile(
                leading: Icon(Icons.mail_outline_rounded, color: cs.primary),
                title: const Text('Email'),
                subtitle: Text(
                  signedIn ? (email ?? 'Not available') : 'Not signed in',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: cs.error),
                title: Text(
                  'Sign out',
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                enabled: signedIn,
                onTap: signedIn
                    ? _confirmLogout
                    : () => _snack('You are not signed in.'),
              ),
            ],
          ),
          _SectionHeader(label: 'Profile', colorScheme: cs),
          _SettingsCard(
            colorScheme: cs,
            children: [
              ListTile(
                leading: Icon(Icons.person_outline_rounded, color: cs.primary),
                title: const Text('Edit profile'),
                subtitle: const Text('Display name, bio, location'),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: signedIn && !_profileLoading,
                onTap: signedIn
                    ? _openEditProfile
                    : () => _snack('Sign in to edit your profile.'),
              ),
            ],
          ),
          _SectionHeader(label: 'Privacy & Safety', colorScheme: cs),
          _SettingsCard(
            colorScheme: cs,
            children: [
              ListTile(
                leading: Icon(Icons.block_rounded, color: cs.primary),
                title: const Text('Blocked users'),
                subtitle: const Text('View or unblock accounts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                enabled: signedIn,
                onTap: signedIn
                    ? _openBlockedUsers
                    : () => _snack('Sign in to manage blocked users.'),
              ),
            ],
          ),
          _SectionHeader(label: 'App', colorScheme: cs),
          _SettingsCard(
            colorScheme: cs,
            children: [
              ListTile(
                leading: Icon(Icons.info_outline_rounded, color: cs.primary),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _showAbout,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.tag_rounded, color: cs.primary),
                title: const Text('Version'),
                subtitle: Text(
                  _kAppVersion,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.colorScheme});

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.colorScheme});

  final List<Widget> children;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

/// Full-screen list of blocked users with unblock actions.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final ModerationService _moderationService = ModerationService();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  final Set<String> _unblocking = {};

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _user?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await _moderationService.getBlockedUsers(uid);
      if (!mounted) return;
      setState(() {
        _rows = raw.map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return <String, dynamic>{};
        }).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PostgrestException && e.message.isNotEmpty
            ? e.message
            : 'Could not load blocked users.';
      });
    }
  }

  Map<String, dynamic>? _nestedProfile(Map<String, dynamic> row) {
    final raw = row['profiles'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  String _blockedId(Map<String, dynamic> row) =>
      row['blocked_id']?.toString() ?? '';

  Future<void> _unblock(Map<String, dynamic> row) async {
    final me = _user?.id;
    final blockedId = _blockedId(row);
    if (me == null || blockedId.isEmpty || _unblocking.contains(blockedId)) {
      return;
    }

    setState(() => _unblocking.add(blockedId));

    try {
      await _moderationService.unblockUser(blockerId: me, blockedId: blockedId);
      if (!mounted) return;
      setState(() {
        _rows = _rows.where((r) => _blockedId(r) != blockedId).toList();
        _unblocking.remove(blockedId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User unblocked')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _unblocking.remove(blockedId));
      final msg = e is PostgrestException && e.message.isNotEmpty
          ? e.message
          : 'Could not unblock.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block_rounded, size: 56, color: cs.outline),
                    const SizedBox(height: 16),
                    Text(
                      'No blocked users',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accounts you block will appear here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _rows.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, indent: 72, color: cs.outlineVariant),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final blockedId = _blockedId(row);
                  final prof = _nestedProfile(row) ?? {};
                  final username =
                      prof['username']?.toString() ?? 'Unknown user';
                  final avatarUrl = prof['avatar_url']?.toString();
                  final busy = _unblocking.contains(blockedId);

                  return ListTile(
                    leading: CircleAvatar(
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
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    title: Text(username),
                    subtitle: Text(
                      'Blocked · interactions hidden',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: busy
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton(
                            onPressed: () => _unblock(row),
                            child: const Text('Unblock'),
                          ),
                  );
                },
              ),
            ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.userId,
    required this.initialProfile,
    required this.profileService,
    required this.onSaved,
  });

  final String userId;
  final Map<String, dynamic> initialProfile;
  final ProfileService profileService;
  final VoidCallback onSaved;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _displayName;
  late final TextEditingController _bio;
  late final TextEditingController _country;
  late final TextEditingController _city;
  late final TextEditingController _website;
  DateTime? _birthDate;
  bool _birthDateCleared = false;
  bool _saving = false;

  String? _avatarUrl;
  String? _headerUrl;
  Uint8List? _avatarBytes;
  Uint8List? _headerBytes;
  String? _avatarExt;
  String? _headerExt;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _displayName = TextEditingController(
      text: p['display_name']?.toString() ?? '',
    );
    _bio = TextEditingController(text: p['bio']?.toString() ?? '');
    _country = TextEditingController(text: p['country']?.toString() ?? '');
    _city = TextEditingController(text: p['city']?.toString() ?? '');
    _website = TextEditingController(text: p['website']?.toString() ?? '');
    _birthDate = DateTime.tryParse(p['birth_date']?.toString() ?? '');
    _avatarUrl = p['avatar_url']?.toString();
    _headerUrl = p['header_url']?.toString();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _country.dispose();
    _city.dispose();
    _website.dispose();
    super.dispose();
  }

  String? _validateWebsite(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v.contains('://') ? v : 'https://$v');
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return 'Enter a valid URL';
    }
    return null;
  }

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarExt = _extensionOf(file.name);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image. Try again.')),
      );
    }
  }

  Future<void> _pickHeader() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1500,
        maxHeight: 500,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _headerBytes = bytes;
        _headerExt = _extensionOf(file.name);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image. Try again.')),
      );
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateCleared = false;
      });
    }
  }

  void _clearBirthDate() {
    setState(() {
      _birthDate = null;
      _birthDateCleared = true;
    });
  }

  String _formatBirthDate(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() => _saving = true);

    try {
      if (_avatarBytes != null) {
        await widget.profileService.uploadAvatar(
          userId: widget.userId,
          bytes: _avatarBytes!,
          fileExtension: _avatarExt ?? 'jpg',
        );
      }
      if (_headerBytes != null) {
        await widget.profileService.uploadHeader(
          userId: widget.userId,
          bytes: _headerBytes!,
          fileExtension: _headerExt ?? 'jpg',
        );
      }

      var website = _website.text.trim();
      if (website.isNotEmpty && !website.contains('://')) {
        website = 'https://$website';
      }
      await widget.profileService.updateProfile(
        userId: widget.userId,
        displayName: _displayName.text.trim(),
        bio: _bio.text.trim(),
        country: _country.text.trim(),
        city: _city.text.trim(),
        website: website,
        birthDate: _birthDate,
        clearBirthDate: _birthDateCleared && _birthDate == null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is PostgrestException && e.message.isNotEmpty
          ? e.message
          : 'Could not save profile.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Edit profile',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _ProfileMediaEditor(
                avatarUrl: _avatarUrl,
                headerUrl: _headerUrl,
                avatarBytes: _avatarBytes,
                headerBytes: _headerBytes,
                initials: (widget.initialProfile['username']?.toString() ?? '')
                    .trim(),
                onPickAvatar: _pickAvatar,
                onPickHeader: _pickHeader,
              ),
              const SizedBox(height: 44),
              TextFormField(
                controller: _displayName,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bio,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 4,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _country,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _website,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  hintText: 'yoursite.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                validator: _validateWebsite,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.cake_outlined),
                      suffixIcon: _birthDate == null
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clearBirthDate,
                            ),
                    ),
                    child: Text(
                      _birthDate == null
                          ? 'Not set'
                          : _formatBirthDate(_birthDate!),
                      style: _birthDate == null
                          ? TextStyle(color: cs.onSurfaceVariant)
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover banner + overlapping avatar with camera-icon edit buttons, used in
/// the Edit Profile sheet to preview and pick new header/avatar images.
class _ProfileMediaEditor extends StatelessWidget {
  const _ProfileMediaEditor({
    required this.avatarUrl,
    required this.headerUrl,
    required this.avatarBytes,
    required this.headerBytes,
    required this.initials,
    required this.onPickAvatar,
    required this.onPickHeader,
  });

  final String? avatarUrl;
  final String? headerUrl;
  final Uint8List? avatarBytes;
  final Uint8List? headerBytes;
  final String initials;
  final VoidCallback onPickAvatar;
  final VoidCallback onPickHeader;

  static const double _avatarRadius = 36;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget headerContent;
    if (headerBytes != null) {
      headerContent = Image.memory(headerBytes!, fit: BoxFit.cover);
    } else if (headerUrl != null && headerUrl!.isNotEmpty) {
      headerContent = Image.network(headerUrl!, fit: BoxFit.cover);
    } else {
      headerContent = DecoratedBox(
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
      );
    }

    ImageProvider? avatarImage;
    if (avatarBytes != null) {
      avatarImage = MemoryImage(avatarBytes!);
    } else if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      avatarImage = NetworkImage(avatarUrl!);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: headerContent,
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: _EditMediaButton(onTap: onPickHeader),
        ),
        Positioned(
          left: 16,
          bottom: -_avatarRadius,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: cs.surface,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: _avatarRadius,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: _EditMediaButton(onTap: onPickAvatar, small: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small circular camera-icon button overlaid on media previews.
class _EditMediaButton extends StatelessWidget {
  const _EditMediaButton({required this.onTap, this.small = false});

  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 32.0;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.camera_alt_rounded,
            color: Colors.white,
            size: small ? 14 : 16,
          ),
        ),
      ),
    );
  }
}
