import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../services/auth_service.dart';
import '../services/poll_service.dart';
import '../services/search_service.dart';
import 'auth/login_screen.dart';
import 'auth/signup_screen.dart';

/// Public share link for a poll's [shareSlug]
/// (`$publicShareBaseUrl/p/:shareSlug`). Exposed for testing.
String publicShareUrlForSlug(String shareSlug) {
  return '${AppConfig.publicShareBaseUrl}/p/$shareSlug';
}

/// Parses free-typed hashtag text (space/comma separated, optional leading
/// `#`) into a deduped, lowercased list of tag strings. Exposed for testing.
List<String> parseHashtagInput(
  String input, {
  Set<String> existing = const {},
}) {
  final tokens = input.split(RegExp(r'[\s,]+'));
  final out = <String>[];
  final seen = {...existing.map((e) => e.toLowerCase())};
  for (final raw in tokens) {
    var tag = raw.trim();
    if (tag.startsWith('#')) tag = tag.substring(1);
    tag = tag.toLowerCase();
    if (tag.isEmpty) continue;
    if (seen.contains(tag)) continue;
    seen.add(tag);
    out.add(tag);
  }
  return out;
}

/// Indices into [rawTexts] whose trimmed value is non-empty, in submission
/// order — lets the screen map a submitted option's `option_order` (1-based
/// position among non-blank options) back to its original per-option media
/// slot, since blank option fields are dropped before publishing. Exposed for
/// testing.
List<int> nonEmptyOptionIndices(List<String> rawTexts) {
  final indices = <int>[];
  for (var i = 0; i < rawTexts.length; i++) {
    if (rawTexts[i].trim().isNotEmpty) indices.add(i);
  }
  return indices;
}

const String expirationNone = 'none';
const String expiration1h = '1h';
const String expiration24h = '24h';
const String expiration7d = '7d';
const String expirationCustom = 'custom';

/// Resolves an expiration preset (relative to [now]) into an absolute
/// timestamp, or `null` for "no expiration". Exposed for testing.
DateTime? resolveExpiresAt(
  String preset, {
  DateTime? customExpiresAt,
  required DateTime now,
}) {
  switch (preset) {
    case expirationNone:
      return null;
    case expiration1h:
      return now.add(const Duration(hours: 1));
    case expiration24h:
      return now.add(const Duration(days: 1));
    case expiration7d:
      return now.add(const Duration(days: 7));
    case expirationCustom:
      return customExpiresAt;
    default:
      return null;
  }
}

/// Validates a poll draft's question/options/expiration, mirroring the rules
/// enforced by `_validateForSubmit`. Returns an error message, or `null` when
/// the draft is valid. Exposed for testing.
String? validatePollDraft({
  required String question,
  required List<String> optionTexts,
  required String expirationPreset,
  DateTime? customExpiresAt,
  required DateTime now,
}) {
  if (question.trim().isEmpty) return 'Enter a question.';

  final nonEmpty = optionTexts
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (nonEmpty.length < 2) return 'Add at least two answer choices.';
  if (optionTexts.length > 5) return 'A poll can have at most five options.';

  final seen = <String>{};
  for (final t in nonEmpty) {
    final key = t.toLowerCase();
    if (seen.contains(key)) return 'Each option must be unique.';
    seen.add(key);
  }

  if (expirationPreset == expirationCustom) {
    if (customExpiresAt == null) return 'Pick an expiration date and time.';
    if (!customExpiresAt.isAfter(now)) {
      return 'Expiration must be in the future.';
    }
  }

  return null;
}

/// Lets a signed-in user publish a poll via [PollService.createPoll].
class CreatePollScreen extends StatefulWidget {
  const CreatePollScreen({super.key});

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final PollService _pollService = PollService();
  final AuthService _authService = AuthService();
  final SearchService _searchService = SearchService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _questionCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _countryCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _topicSearchCtrl = TextEditingController();
  final TextEditingController _hashtagCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = <TextEditingController>[];

  /// Per-option media, kept in lockstep with [_optionCtrls] by index.
  final List<XFile?> _optionMedia = <XFile?>[];
  final List<Uint8List?> _optionMediaBytes = <Uint8List?>[];
  final List<String?> _optionMediaType = <String?>[];

  String _visibility = 'public';
  String _expirationPreset = expirationNone;

  /// Used when [_expirationPreset] is [expirationCustom].
  DateTime? _customExpiresAt;

  static const int _maxTopics = 3;
  static const int _maxHashtags = 5;

  /// Selected topics as `{id, name}` maps.
  final List<Map<String, String>> _selectedTopics = [];
  List<Map<String, String>> _topicSuggestions = [];
  bool _searchingTopics = false;
  Timer? _topicSearchDebounce;

  final List<String> _hashtags = [];

  XFile? _pickedMedia;
  Uint8List? _pickedMediaBytes;
  String? _pickedMediaType; // 'image' or 'video'

  bool _submitting = false;

  StreamSubscription<AuthState>? _authSubscription;

  static const List<(String, String)> _visibilityChoices = [
    ('public', 'Public'),
    ('followers', 'Followers'),
    ('private', 'Private'),
  ];

  OutlineInputBorder get _fieldBorder =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12));

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: _fieldBorder,
      enabledBorder: _fieldBorder,
      filled: true,
    );
  }

  @override
  void initState() {
    super.initState();
    _addOptionSlot();
    _addOptionSlot();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _topicSearchDebounce?.cancel();
    _questionCtrl.dispose();
    _descriptionCtrl.dispose();
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    _topicSearchCtrl.dispose();
    _hashtagCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateForSubmit() {
    final user =
        _authService.currentUser ?? Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _snack('You must be signed in to publish a poll.');
      return false;
    }

    final error = validatePollDraft(
      question: _questionCtrl.text,
      optionTexts: _optionCtrls.map((c) => c.text).toList(),
      expirationPreset: _expirationPreset,
      customExpiresAt: _customExpiresAt,
      now: DateTime.now(),
    );
    if (error != null) {
      _snack(error);
      return false;
    }

    return true;
  }

  DateTime? _resolveExpiresAt() {
    return resolveExpiresAt(
      _expirationPreset,
      customExpiresAt: _customExpiresAt,
      now: DateTime.now(),
    );
  }

  String _expirationSummary() {
    switch (_expirationPreset) {
      case expirationNone:
        return 'No expiration';
      case expiration1h:
        return 'Expires in about 1 hour';
      case expiration24h:
        return 'Expires in about 24 hours';
      case expiration7d:
        return 'Expires in about 7 days';
      case expirationCustom:
        final dt = _customExpiresAt;
        return dt == null ? 'Pick date & time' : _formatDateTime(dt);
      default:
        return '';
    }
  }

  String _formatDateTime(DateTime dt) {
    final d =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  Future<void> _pickCustomExpiration() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (_customExpiresAt ?? now).isAfter(now)
          ? (_customExpiresAt ?? now)
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _customExpiresAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _customExpiresAt = combined);
  }

  /// Appends a new option text controller plus its (initially empty) media slots.
  void _addOptionSlot() {
    _optionCtrls.add(TextEditingController());
    _optionMedia.add(null);
    _optionMediaBytes.add(null);
    _optionMediaType.add(null);
  }

  void _addOption() {
    if (_optionCtrls.length >= 5) {
      _snack('You can add at most five options.');
      return;
    }
    setState(_addOptionSlot);
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) {
      _snack('A poll needs at least two options.');
      return;
    }
    final removed = _optionCtrls.removeAt(index);
    removed.dispose();
    _optionMedia.removeAt(index);
    _optionMediaBytes.removeAt(index);
    _optionMediaType.removeAt(index);
    setState(() {});
  }

  Future<void> _pickOptionMedia(int index, String mediaType) async {
    try {
      final XFile? file = mediaType == 'video'
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _optionMedia[index] = file;
        _optionMediaBytes[index] = bytes;
        _optionMediaType[index] = mediaType;
      });
    } catch (_) {
      _snack('Could not pick media. Try again.');
    }
  }

  void _removeOptionMedia(int index) {
    setState(() {
      _optionMedia[index] = null;
      _optionMediaBytes[index] = null;
      _optionMediaType[index] = null;
    });
  }

  void _onTopicSearchChanged(String query) {
    _topicSearchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _topicSuggestions = [];
        _searchingTopics = false;
      });
      return;
    }
    setState(() => _searchingTopics = true);
    _topicSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final raw = await _searchService.searchTopics(trimmed);
        if (!mounted) return;
        setState(() {
          _topicSuggestions = raw
              .whereType<Map>()
              .map(
                (e) => {
                  'id': e['id']?.toString() ?? '',
                  'name': e['name']?.toString() ?? '',
                },
              )
              .where((t) => t['id']!.isNotEmpty && t['name']!.isNotEmpty)
              .toList();
          _searchingTopics = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _topicSuggestions = [];
          _searchingTopics = false;
        });
      }
    });
  }

  void _selectTopic(Map<String, String> topic) {
    if (_selectedTopics.any((t) => t['id'] == topic['id'])) return;
    if (_selectedTopics.length >= _maxTopics) {
      _snack('You can pick at most $_maxTopics topics.');
      return;
    }
    setState(() {
      _selectedTopics.add(topic);
      _topicSuggestions = [];
      _topicSearchCtrl.clear();
    });
  }

  void _removeTopic(String topicId) {
    setState(() => _selectedTopics.removeWhere((t) => t['id'] == topicId));
  }

  void _addHashtagsFromInput() {
    final input = _hashtagCtrl.text;
    if (input.trim().isEmpty) return;
    final parsed = parseHashtagInput(input, existing: _hashtags.toSet());
    if (parsed.isEmpty) {
      _hashtagCtrl.clear();
      return;
    }
    setState(() {
      for (final tag in parsed) {
        if (_hashtags.length >= _maxHashtags) break;
        _hashtags.add(tag);
      }
      _hashtagCtrl.clear();
    });
    if (_hashtags.length >= _maxHashtags) {
      _snack('You can add at most $_maxHashtags hashtags.');
    }
  }

  void _removeHashtag(String tag) {
    setState(() => _hashtags.remove(tag));
  }

  Future<void> _pickMedia(String mediaType) async {
    try {
      final XFile? file = mediaType == 'video'
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedMedia = file;
        _pickedMediaBytes = bytes;
        _pickedMediaType = mediaType;
      });
    } catch (_) {
      _snack('Could not pick media. Try again.');
    }
  }

  void _removeMedia() {
    setState(() {
      _pickedMedia = null;
      _pickedMediaBytes = null;
      _pickedMediaType = null;
    });
  }

  Future<void> _publish() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();
    if (!_validateForSubmit()) return;

    final user =
        _authService.currentUser ?? Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _snack('You must be signed in to publish a poll.');
      return;
    }

    final rawOptionTexts = _optionCtrls.map((c) => c.text).toList();
    final optionIndices = nonEmptyOptionIndices(rawOptionTexts);
    final options = [for (final i in optionIndices) rawOptionTexts[i].trim()];
    final country = _countryCtrl.text.trim();
    final city = _cityCtrl.text.trim();

    setState(() => _submitting = true);
    try {
      final poll = await _pollService.createPoll(
        userId: user.id,
        question: _questionCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        options: options,
        visibility: _visibility,
        country: country.isEmpty ? null : country,
        city: city.isEmpty ? null : city,
        expiresAt: _resolveExpiresAt(),
      );
      final pollId = poll['id']?.toString();

      if (pollId != null) {
        await _attachExtras(
          userId: user.id,
          pollId: pollId,
          optionIndices: optionIndices,
        );
      }

      if (!mounted) return;
      final shareSlug = poll['share_slug']?.toString().trim();
      if (shareSlug != null && shareSlug.isNotEmpty) {
        await _showSharePrompt(
          question: _questionCtrl.text.trim(),
          shareSlug: shareSlug,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      _snack(e.message.isNotEmpty ? e.message : 'Could not publish poll.');
    } catch (_) {
      _snack('Network error. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Shows the post-publish "share your poll" bottom sheet and waits for it
  /// to be dismissed (Share/Copy link don't dismiss it; Done and
  /// swipe/tap-outside do).
  Future<void> _showSharePrompt({
    required String question,
    required String shareSlug,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _SharePromptSheet(question: question, shareSlug: shareSlug),
      ),
    );
  }

  /// Attaches topics, hashtags, and media to a poll that was already created
  /// successfully. [optionIndices] maps each submitted option's 1-based
  /// `option_order` (its position in this list) back to its original
  /// `_optionCtrls`/`_optionMedia` slot, since blank option fields were
  /// dropped before publishing. Failures here are non-fatal — the poll and
  /// its options exist regardless.
  Future<void> _attachExtras({
    required String userId,
    required String pollId,
    required List<int> optionIndices,
  }) async {
    if (_selectedTopics.isNotEmpty) {
      try {
        await _pollService.attachTopics(
          pollId: pollId,
          topicIds: _selectedTopics.map((t) => t['id']!).toList(),
        );
      } catch (_) {
        _snack('Poll published, but topics could not be saved.');
      }
    }

    if (_hashtags.isNotEmpty) {
      try {
        await _pollService.attachHashtags(pollId: pollId, tags: _hashtags);
      } catch (_) {
        _snack('Poll published, but hashtags could not be saved.');
      }
    }

    final bytes = _pickedMediaBytes;
    final mediaType = _pickedMediaType;
    final media = _pickedMedia;
    if (bytes != null && mediaType != null && media != null) {
      try {
        await _pollService.uploadPollMedia(
          userId: userId,
          pollId: pollId,
          bytes: bytes,
          fileName: media.name,
          mediaType: mediaType,
        );
      } catch (_) {
        _snack('Poll published, but the media could not be uploaded.');
      }
    }

    var optionMediaFailed = false;
    for (var order = 0; order < optionIndices.length; order++) {
      final slot = optionIndices[order];
      final optBytes = _optionMediaBytes[slot];
      final optType = _optionMediaType[slot];
      final optFile = _optionMedia[slot];
      if (optBytes == null || optType == null || optFile == null) continue;
      try {
        await _pollService.uploadOptionMedia(
          userId: userId,
          pollId: pollId,
          optionOrder: order + 1,
          bytes: optBytes,
          fileName: optFile.name,
          mediaType: optType,
        );
      } catch (_) {
        optionMediaFailed = true;
      }
    }
    if (optionMediaFailed) {
      _snack('Poll published, but some option media could not be uploaded.');
    }
  }

  Widget _buildGuestPrompt(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Create Poll'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.how_to_vote_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Create an account to publish polls',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
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

  @override
  Widget build(BuildContext context) {
    final user =
        _authService.currentUser ?? Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return _buildGuestPrompt(context);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Create Poll'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: FilledButton(
                onPressed: _submitting ? null : _publish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 10,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.surface,
                        ),
                      )
                    : const Text('Post'),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
        children: [
          TextFormField(
            controller: _descriptionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration(
              'Post text (optional)',
              hint: 'Add context, opinion, or story around your poll...',
            ),
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _questionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration(
              'Question',
              hint: 'What do you want to ask?',
            ),
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 20),
          Text(
            'Answer choices',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'At least 2, up to 5.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _optionCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _optionCtrls[i],
                          decoration: _decoration('Option ${i + 1}'),
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: i == _optionCtrls.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remove option',
                        onPressed: _optionCtrls.length > 2
                            ? () => _removeOption(i)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  if (_optionMediaBytes[i] != null &&
                      _optionMediaType[i] == 'image')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          _optionMediaBytes[i]!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else if (_optionMedia[i] != null &&
                      _optionMediaType[i] == 'video')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        height: 56,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            const Icon(Icons.videocam_outlined, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _optionMedia[i]!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_optionMedia[i] != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _removeOptionMedia(i),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove media'),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => _pickOptionMedia(i, 'image'),
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('Add photo'),
                          ),
                          TextButton.icon(
                            onPressed: () => _pickOptionMedia(i, 'video'),
                            icon: const Icon(Icons.videocam_outlined, size: 18),
                            label: const Text('Add video'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _optionCtrls.length >= 5 ? null : _addOption,
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Expiration',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: _decoration('When does voting close?', hint: null),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                borderRadius: BorderRadius.circular(12),
                value: _expirationPreset,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: expirationNone,
                    child: Text('No expiration'),
                  ),
                  DropdownMenuItem(
                    value: expiration1h,
                    child: Text('In 1 hour'),
                  ),
                  DropdownMenuItem(
                    value: expiration24h,
                    child: Text('In 24 hours'),
                  ),
                  DropdownMenuItem(
                    value: expiration7d,
                    child: Text('In 7 days'),
                  ),
                  DropdownMenuItem(
                    value: expirationCustom,
                    child: Text('Custom date & time'),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) async {
                        if (value == null) return;
                        final previous = _expirationPreset;
                        if (value == expirationCustom) {
                          setState(() => _expirationPreset = expirationCustom);
                          await _pickCustomExpiration();
                          if (!mounted) return;
                          if (_customExpiresAt == null) {
                            setState(() => _expirationPreset = previous);
                          }
                        } else {
                          setState(() {
                            _expirationPreset = value;
                            _customExpiresAt = null;
                          });
                        }
                      },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _expirationSummary(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Who can see this?',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: _decoration('Visibility'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                borderRadius: BorderRadius.circular(12),
                value: _visibility,
                isExpanded: true,
                items: [
                  for (final pair in _visibilityChoices)
                    DropdownMenuItem<String>(
                      value: pair.$1,
                      child: Text(pair.$2),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) {
                        if (v != null) setState(() => _visibility = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Topics',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick up to $_maxTopics.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedTopics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final topic in _selectedTopics)
                    InputChip(
                      label: Text(topic['name'] ?? ''),
                      onDeleted: () => _removeTopic(topic['id']!),
                    ),
                ],
              ),
            ),
          if (_selectedTopics.length < _maxTopics)
            TextFormField(
              controller: _topicSearchCtrl,
              decoration: _decoration(
                'Search topics',
                hint: 'e.g. Sports, Music',
              ),
              onChanged: _onTopicSearchChanged,
            ),
          if (_searchingTopics)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (_topicSuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final topic in _topicSuggestions)
                    ActionChip(
                      label: Text(topic['name'] ?? ''),
                      onPressed: () => _selectTopic(topic),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text(
            'Hashtags',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Add up to $_maxHashtags, separated by spaces or commas.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_hashtags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _hashtags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () => _removeHashtag(tag),
                    ),
                ],
              ),
            ),
          if (_hashtags.length < _maxHashtags)
            TextFormField(
              controller: _hashtagCtrl,
              decoration: _decoration('Add hashtags', hint: '#travel #food'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _addHashtagsFromInput(),
              onChanged: (value) {
                if (value.endsWith(' ') || value.endsWith(',')) {
                  _addHashtagsFromInput();
                }
              },
            ),
          const SizedBox(height: 18),
          Text(
            'Photo or video',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_pickedMediaBytes != null && _pickedMediaType == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _pickedMediaBytes!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else if (_pickedMedia != null && _pickedMediaType == 'video')
            Container(
              height: 80,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(Icons.videocam_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pickedMedia!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_pickedMedia != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _removeMedia,
                icon: const Icon(Icons.close),
                label: const Text('Remove media'),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickMedia('image'),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Add photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickMedia('video'),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Add video'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _countryCtrl,
            decoration: _decoration('Country (optional)'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cityCtrl,
            decoration: _decoration('City (optional)'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Post-publish "share your poll" prompt: the public link plus a native
/// share sheet / copy-link fallback, dismissible without sharing.
class _SharePromptSheet extends StatelessWidget {
  const _SharePromptSheet({required this.question, required this.shareSlug});

  final String question;
  final String shareSlug;

  String get _shareUrl => publicShareUrlForSlug(shareSlug);

  String get _shareText {
    final q = question.trim();
    final intro = q.isEmpty
        ? 'I just published a poll on Poll Social!'
        : 'I just published "$q" on Poll Social!';
    return '$intro\n$_shareUrl';
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied to clipboard.')));
  }

  Future<void> _share() => Share.share(_shareText);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your poll is live — share it!',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Polls get votes when people outside the app can see them too.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shareUrl,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyLink(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy link'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
