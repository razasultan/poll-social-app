import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import '../core/state/poll_notifier.dart';
import '../services/poll_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/option_media_accordion.dart';
import '../widgets/video_preview.dart';

/// Full-screen edit view for a poll the current user owns.
/// Receives the poll map as returned by [PollService.getPollById].
/// Pops with [true] when saved, ['deleted'] when the poll is deleted,
/// or null/false when the user cancels without changes.
class EditPollScreen extends StatefulWidget {
  const EditPollScreen({super.key, required this.poll});

  final Map<String, dynamic> poll;

  @override
  State<EditPollScreen> createState() => _EditPollScreenState();
}

class _EditPollScreenState extends State<EditPollScreen> {
  final PollService _pollService = PollService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;

  // True when any votes have been cast — locks option text fields.
  bool _optionsLocked = false;

  late final TextEditingController _questionCtrl;
  late final TextEditingController _descriptionCtrl;

  // Options sorted by option_order
  late List<Map<String, dynamic>> _options;
  late List<TextEditingController> _optionCtrls;

  // Per-option new media (null = no change)
  late List<XFile?> _newOptionMedia;
  late List<Uint8List?> _newOptionMediaBytes;
  late List<String?> _newOptionMediaType;
  // Per-option remove flag (clears existing without replacing)
  late List<bool> _clearOptionMedia;

  // Poll-level media state
  String? _existingPollMediaUrl;
  String? _existingPollMediaType;
  bool _clearPollMedia = false;
  XFile? _newPollMedia;
  Uint8List? _newPollMediaBytes;
  String? _newPollMediaType;

  String _visibility = 'public';
  String _mediaLayout = 'scrim';
  DateTime? _expiresAt;

  String get _pollId => widget.poll['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _seedFromPoll();
    _checkVoteCount();
  }

  void _seedFromPoll() {
    final poll = widget.poll;

    _questionCtrl = TextEditingController(
      text: poll['question']?.toString() ?? '',
    );
    _descriptionCtrl = TextEditingController(
      text: poll['description']?.toString() ?? '',
    );
    _visibility = poll['visibility']?.toString() ?? 'public';
    _mediaLayout = poll['media_layout']?.toString() ?? 'scrim';

    final rawExpiry = poll['expires_at'];
    _expiresAt = rawExpiry != null
        ? DateTime.tryParse(rawExpiry.toString())
        : null;

    final rawOptions =
        (poll['poll_options'] as List? ?? [])
            .whereType<Map>()
            .map((o) => Map<String, dynamic>.from(o))
            .toList()
          ..sort(
            (a, b) => ((a['option_order'] as num?) ?? 0).compareTo(
              (b['option_order'] as num?) ?? 0,
            ),
          );

    _options = rawOptions;
    _optionCtrls = _options
        .map(
          (o) =>
              TextEditingController(text: o['option_text']?.toString() ?? ''),
        )
        .toList();

    _newOptionMedia = List.filled(_options.length, null);
    _newOptionMediaBytes = List.filled(_options.length, null);
    _newOptionMediaType = List.filled(_options.length, null);
    _clearOptionMedia = List.filled(_options.length, false);

    final mediaCandidates = (poll['poll_media'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (mediaCandidates.isNotEmpty) {
      _existingPollMediaUrl = mediaCandidates.first['media_url']?.toString();
      _existingPollMediaType = mediaCandidates.first['media_type']?.toString();
    }
  }

  Future<void> _checkVoteCount() async {
    try {
      final count = await _pollService.getPollVoteCount(_pollId);
      if (mounted) setState(() => _optionsLocked = count > 0);
    } catch (_) {
      // Non-fatal; default stays unlocked.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _descriptionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatExpiry(DateTime dt) {
    final d =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d at $t';
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = (_expiresAt != null && _expiresAt!.isAfter(now))
        ? _expiresAt!
        : now.add(const Duration(days: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _expiresAt ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickOptionMedia(int index, String mediaType) async {
    try {
      final file = mediaType == 'video'
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _newOptionMedia[index] = file;
        _newOptionMediaBytes[index] = bytes;
        _newOptionMediaType[index] = mediaType;
        _clearOptionMedia[index] = false;
      });
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not pick media. Try again.');
    }
  }

  Future<void> _pickPollMedia(String mediaType) async {
    try {
      final file = mediaType == 'video'
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _newPollMedia = file;
        _newPollMediaBytes = bytes;
        _newPollMediaType = mediaType;
        _clearPollMedia = false;
      });
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not pick media. Try again.');
    }
  }

  void _showMediaPicker({required void Function(String) onPick}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Replace media',
                style: Theme.of(
                  ctx,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Choose photo'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPick('image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Choose video'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPick('video');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  /// Evicts a network image URL from Flutter's [imageCache] so the next
  /// render fetches the new version rather than showing the stale cached copy.
  void _evictUrl(String? url) {
    if (url != null && url.isNotEmpty) {
      imageCache.evict(NetworkImage(url));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    if (_questionCtrl.text.trim().isEmpty) {
      AppToast.warning(context, 'Question cannot be empty.');
      return;
    }

    if (!_optionsLocked) {
      final nonEmpty = _optionCtrls
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .length;
      if (nonEmpty < 2) {
        AppToast.warning(context, 'At least two options are required.');
        return;
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      await _pollService.updatePoll(
        pollId: _pollId,
        question: _questionCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        visibility: _visibility,
        expiresAt: _expiresAt,
        clearExpiry: _expiresAt == null,
        mediaLayout: _mediaLayout,
      );

      if (!_optionsLocked) {
        for (var i = 0; i < _options.length; i++) {
          final optionId = _options[i]['id']?.toString() ?? '';
          final newText = _optionCtrls[i].text.trim();
          final oldText = _options[i]['option_text']?.toString() ?? '';
          if (optionId.isNotEmpty && newText.isNotEmpty && newText != oldText) {
            await _pollService.updatePollOptionText(
              optionId: optionId,
              optionText: newText,
            );
          }
        }
      }

      for (var i = 0; i < _options.length; i++) {
        final optionId = _options[i]['id']?.toString() ?? '';
        if (optionId.isEmpty) continue;
        if (_clearOptionMedia[i]) {
          await _pollService.removeOptionMedia(optionId: optionId);
          _evictUrl(_options[i]['media_url']?.toString());
        } else if (_newOptionMediaBytes[i] != null &&
            _newOptionMedia[i] != null &&
            _newOptionMediaType[i] != null) {
          _evictUrl(_options[i]['media_url']?.toString());
          await _pollService.replaceOptionMedia(
            userId: user.id,
            pollId: _pollId,
            optionId: optionId,
            bytes: _newOptionMediaBytes[i]!,
            fileName: _newOptionMedia[i]!.name,
            mediaType: _newOptionMediaType[i]!,
          );
        }
      }

      if (_clearPollMedia) {
        _evictUrl(_existingPollMediaUrl);
        await _pollService.removePollMedia(pollId: _pollId);
      } else if (_newPollMediaBytes != null &&
          _newPollMedia != null &&
          _newPollMediaType != null) {
        _evictUrl(_existingPollMediaUrl);
        await _pollService.replacePollMedia(
          userId: user.id,
          pollId: _pollId,
          bytes: _newPollMediaBytes!,
          fileName: _newPollMedia!.name,
          mediaType: _newPollMediaType!,
        );
      }

      // Signal feed to reload so edited poll appears with new media.
      pollUpdateNotifier.value++;

      if (!mounted) return;
      context.pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      AppToast.error(
        context,
        e.message.isNotEmpty ? e.message : 'Could not save changes.',
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Network error. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 32),
        title: const Text('Delete this poll?'),
        content: const Text(
          'This permanently removes the poll and all its votes. There is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _saving = true);
    try {
      await _pollService.deletePoll(_pollId);
      if (!mounted) return;
      context.pop('deleted');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not delete poll. Try again.');
      setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: _buildAppBar(cs),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _saving,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + bottomPad),
                children: [
                  _buildContentCard(cs, theme),
                  const SizedBox(height: 12),
                  _buildSettingsCard(cs, theme),
                  const SizedBox(height: 12),
                  _buildOptionsCard(cs, theme),
                  const SizedBox(height: 12),
                  _buildPollMediaCard(cs, theme),
                  const SizedBox(height: 28),
                  _buildDangerZone(cs, theme),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _saving ? null : () => context.pop(),
        tooltip: 'Discard changes',
      ),
      title: const Text('Edit Poll'),
      centerTitle: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: const StadiumBorder(),
            ),
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Text('Save changes'),
          ),
        ),
      ],
    );
  }

  // ── Section scaffolding ───────────────────────────────────────────────────

  Widget _card({required Widget child, Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color ?? cs.surfaceContainerLow,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _sectionLabel(String label, {IconData? icon, Color? color}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = color ?? cs.primary;
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (icon != null) ...[
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: c,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
    );
  }

  // ── Content card ──────────────────────────────────────────────────────────

  Widget _buildContentCard(ColorScheme cs, ThemeData theme) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Content', icon: Icons.edit_note_rounded),
          const SizedBox(height: 16),
          TextFormField(
            controller: _questionCtrl,
            decoration: _fieldDecoration(
              'Question',
              hint: 'What do you want to ask?',
            ),
            style: theme.textTheme.titleMedium,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionCtrl,
            decoration: _fieldDecoration(
              'Description (optional)',
              hint: 'Add context or background for this poll…',
            ),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            minLines: 1,
            enabled: !_saving,
          ),
        ],
      ),
    );
  }

  // ── Settings card ─────────────────────────────────────────────────────────

  static const List<(String, String, IconData)> _visibilityOptions = [
    ('public', 'Public', Icons.public_rounded),
    ('followers', 'Followers', Icons.group_rounded),
    ('private', 'Private', Icons.lock_outline_rounded),
  ];

  static const List<(String, String, IconData)> _layoutChoices = [
    ('scrim', 'Scrim', Icons.grid_view_rounded),
    ('list', 'List', Icons.view_list_rounded),
    ('mosaic', 'Mosaic', Icons.auto_awesome_mosaic_rounded),
  ];

  Widget _buildSettingsCard(ColorScheme cs, ThemeData theme) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Settings', icon: Icons.tune_rounded),
          const SizedBox(height: 16),
          Text(
            'Who can see this poll?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final v in _visibilityOptions)
                ButtonSegment<String>(
                  value: v.$1,
                  label: Text(v.$2),
                  icon: Icon(v.$3, size: 15),
                ),
            ],
            selected: {_visibility},
            onSelectionChanged: _saving
                ? null
                : (s) => setState(() => _visibility = s.first),
            style: SegmentedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Media layout',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (value, label, icon) in _layoutChoices) ...[
                if (value != 'scrim') const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _saving
                        ? null
                        : () => setState(() => _mediaLayout = value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mediaLayout == value
                            ? cs.primary.withValues(alpha: 0.12)
                            : null,
                        border: Border.all(
                          color: _mediaLayout == value
                              ? cs.primary
                              : cs.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: _mediaLayout == value
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _mediaLayout == value
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Voting closes',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 20,
                color: _expiresAt != null ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _expiresAt != null
                      ? _formatExpiry(_expiresAt!)
                      : 'No expiration',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _expiresAt != null
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _pickExpiry,
                child: Text(_expiresAt != null ? 'Change' : 'Set expiry'),
              ),
              if (_expiresAt != null)
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: 'Remove expiry',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _expiresAt = null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Options card ──────────────────────────────────────────────────────────

  Widget _buildOptionsCard(ColorScheme cs, ThemeData theme) {
    final locked = _optionsLocked;
    final cardColor = locked
        ? cs.tertiaryContainer.withValues(alpha: 0.28)
        : cs.surfaceContainerLow;

    return _card(
      color: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionLabel(
                'Answer choices',
                icon: locked
                    ? Icons.lock_outline_rounded
                    : Icons.format_list_bulleted_rounded,
                color: locked ? cs.tertiary : cs.primary,
              ),
              const Spacer(),
              if (locked)
                _chip(
                  icon: Icons.how_to_vote_outlined,
                  label: 'Has votes',
                  background: cs.tertiaryContainer,
                  foreground: cs.onTertiaryContainer,
                ),
            ],
          ),
          if (locked) ...[
            const SizedBox(height: 10),
            Text(
              'Option text is locked once votes are cast. You can still replace or add media.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < _options.length; i++) ...[
            _buildOptionRow(i, cs, theme),
            if (i < _options.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionRow(int i, ColorScheme cs, ThemeData theme) {
    final option = _options[i];
    final locked = _optionsLocked;
    final badgeBg = locked ? cs.tertiaryContainer : cs.primaryContainer;
    final badgeFg = locked ? cs.onTertiaryContainer : cs.onPrimaryContainer;

    final hasNew = _newOptionMediaBytes[i] != null;
    final hasExisting =
        !_clearOptionMedia[i] &&
        !hasNew &&
        (option['media_url']?.toString().isNotEmpty == true);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numbered badge
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 10, right: 10),
                decoration: BoxDecoration(
                  color: badgeBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _optionCtrls[i],
                  enabled: !locked && !_saving,
                  decoration: InputDecoration(
                    hintText: 'Option ${i + 1}',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    filled: true,
                    fillColor: locked
                        ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _mediaSlot(
            i,
            cs,
            theme,
            hasNew: hasNew,
            hasExisting: hasExisting,
            existingUrl: option['media_url']?.toString(),
            existingType: option['media_type']?.toString(),
          ),
        ],
      ),
    );
  }

  Widget _mediaSlot(
    int i,
    ColorScheme cs,
    ThemeData theme, {
    required bool hasNew,
    required bool hasExisting,
    String? existingUrl,
    String? existingType,
  }) {
    if (hasNew) {
      return OptionMediaAccordion(
        imageBytes: _newOptionMediaType[i] == 'image'
            ? _newOptionMediaBytes[i]
            : null,
        videoUrl: _newOptionMediaType[i] == 'video'
            ? _newOptionMedia[i]?.path
            : null,
        fileName: _newOptionMedia[i]?.name ?? '',
        mediaType: _newOptionMediaType[i] ?? 'image',
        onReplace: () =>
            _showMediaPicker(onPick: (type) => _pickOptionMedia(i, type)),
        onRemove: () => setState(() {
          _newOptionMedia[i] = null;
          _newOptionMediaBytes[i] = null;
          _newOptionMediaType[i] = null;
        }),
      );
    }
    if (hasExisting) {
      return OptionMediaAccordion(
        imageUrl: existingType != 'video' ? existingUrl : null,
        videoUrl: existingType == 'video' ? existingUrl : null,
        fileName: '',
        mediaType: existingType ?? 'image',
        onReplace: () =>
            _showMediaPicker(onPick: (type) => _pickOptionMedia(i, type)),
        onRemove: () => setState(() => _clearOptionMedia[i] = true),
      );
    }
    return _addMediaButtons(
      cs: cs,
      onPickImage: () => _pickOptionMedia(i, 'image'),
      onPickVideo: () => _pickOptionMedia(i, 'video'),
    );
  }

  // ── Poll-level media card ─────────────────────────────────────────────────

  Widget _buildPollMediaCard(ColorScheme cs, ThemeData theme) {
    final hasNew = _newPollMediaBytes != null;
    final hasExisting =
        !_clearPollMedia &&
        !hasNew &&
        (_existingPollMediaUrl?.isNotEmpty == true);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Photo or video', icon: Icons.perm_media_outlined),
          const SizedBox(height: 16),
          if (hasNew)
            _newMediaPreview(
              isImage: _newPollMediaType == 'image',
              bytes: _newPollMediaBytes,
              fileName: _newPollMedia?.name ?? '',
              videoUrl: _newPollMediaType == 'video'
                  ? _newPollMedia?.path
                  : null,
              cs: cs,
              onReplace: () =>
                  _showMediaPicker(onPick: (t) => _pickPollMedia(t)),
              onRemove: () => setState(() {
                _newPollMedia = null;
                _newPollMediaBytes = null;
                _newPollMediaType = null;
              }),
            )
          else if (hasExisting)
            _existingMediaPreview(
              url: _existingPollMediaUrl!,
              mediaType: _existingPollMediaType ?? 'image',
              cs: cs,
              theme: theme,
              onReplace: () =>
                  _showMediaPicker(onPick: (t) => _pickPollMedia(t)),
              onRemove: () => setState(() {
                _clearPollMedia = true;
                _existingPollMediaUrl = null;
              }),
            )
          else
            _addMediaButtons(
              cs: cs,
              onPickImage: () => _pickPollMedia('image'),
              onPickVideo: () => _pickPollMedia('video'),
            ),
        ],
      ),
    );
  }

  // ── Shared media widgets ──────────────────────────────────────────────────

  Widget _newMediaPreview({
    required bool isImage,
    required Uint8List? bytes,
    required String fileName,
    required String? videoUrl,
    required ColorScheme cs,
    required VoidCallback onReplace,
    required VoidCallback onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isImage && bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (videoUrl != null)
          VideoPreview(url: videoUrl, height: 160)
        else
          const SizedBox.shrink(),
        const SizedBox(height: 8),
        _mediaActions(cs: cs, onReplace: onReplace, onRemove: onRemove),
      ],
    );
  }

  Widget _existingMediaPreview({
    required String url,
    required String mediaType,
    required ColorScheme cs,
    required ThemeData theme,
    required VoidCallback onReplace,
    required VoidCallback onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mediaType == 'image')
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
            ),
          )
        else
          VideoPreview(url: url, height: 160),
        const SizedBox(height: 8),
        _mediaActions(cs: cs, onReplace: onReplace, onRemove: onRemove),
      ],
    );
  }

  Widget _mediaActions({
    required ColorScheme cs,
    required VoidCallback onReplace,
    required VoidCallback onRemove,
  }) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _saving ? null : onReplace,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Replace'),
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: _saving ? null : onRemove,
          style: TextButton.styleFrom(foregroundColor: cs.error),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Remove'),
        ),
      ],
    );
  }

  Widget _addMediaButtons({
    required ColorScheme cs,
    required VoidCallback onPickImage,
    required VoidCallback onPickVideo,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : onPickImage,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Add photo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : onPickVideo,
            icon: const Icon(Icons.videocam_outlined, size: 18),
            label: const Text('Add video'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Danger zone ───────────────────────────────────────────────────────────

  Widget _buildDangerZone(ColorScheme cs, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            'Danger zone',
            icon: Icons.warning_amber_rounded,
            color: cs.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Permanently deletes this poll, all its votes, and all comments. There is no undo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Delete this poll'),
            ),
          ),
        ],
      ),
    );
  }
}
