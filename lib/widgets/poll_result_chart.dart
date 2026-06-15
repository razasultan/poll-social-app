import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vote_service.dart';
import 'poll_card.dart' show pollResultPercentage;

/// One bar's worth of data for [PollResultChart]. Exposed for testing.
class PollChartEntry {
  const PollChartEntry({
    required this.label,
    required this.count,
    required this.percentage,
    required this.selected,
  });

  final String label;
  final int count;
  final double percentage;
  final bool selected;
}

/// Maps poll options + raw vote counts into chart-ready entries, in the
/// options' display order. Exposed as a top-level pure function for testing.
List<PollChartEntry> buildPollChartEntries({
  required List<Map<String, dynamic>> options,
  required Map<String, int> voteCounts,
  required int totalVotes,
  String? selectedOptionId,
}) {
  return [
    for (final option in options)
      () {
        final id = option['id']?.toString() ?? '';
        final count = voteCounts[id] ?? 0;
        return PollChartEntry(
          label: option['option_text']?.toString() ?? '',
          count: count,
          percentage: pollResultPercentage(count, totalVotes),
          selected: id.isNotEmpty && id == selectedOptionId,
        );
      }(),
  ];
}

/// Rich per-option vote breakdown for [PollDetailScreen], built with fl_chart.
///
/// Loads its own vote data (mirroring [PollCard]'s bootstrap) so the detail
/// screen doesn't need to duplicate vote-fetching/highlight logic. Renders
/// nothing for polls with fewer than two options, and a "vote to see results"
/// placeholder until the viewer has voted or the poll has expired — matching
/// the reveal rule used by the lightweight bars in the feed.
class PollResultChart extends StatefulWidget {
  const PollResultChart({super.key, required this.poll});

  final Map<String, dynamic> poll;

  @override
  State<PollResultChart> createState() => _PollResultChartState();
}

class _PollResultChartState extends State<PollResultChart> {
  final VoteService _voteService = VoteService();

  bool _loading = true;
  String? _selectedOptionId;
  Map<String, int> _optionVotes = const {};

  String get _pollId => widget.poll['id']?.toString() ?? '';

  List<Map<String, dynamic>> get _options {
    final raw = widget.poll['poll_options'];
    if (raw is! List) return const [];
    final list = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        list.add(item);
      } else if (item is Map) {
        list.add(Map<String, dynamic>.from(item));
      }
    }
    list.sort((a, b) {
      final ao = a['option_order'];
      final bo = b['option_order'];
      final ai = ao is int ? ao : int.tryParse('$ao') ?? 0;
      final bi = bo is int ? bo : int.tryParse('$bo') ?? 0;
      return ai.compareTo(bi);
    });
    return list;
  }

  bool get _isExpired {
    final raw = widget.poll['expires_at'];
    if (raw == null) return false;
    final at = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
    if (at == null) return false;
    return DateTime.now().isAfter(at);
  }

  bool get _showResults => _selectedOptionId != null || _isExpired;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final vote = await _voteService.getUserVote(
          pollId: _pollId,
          userId: user.id,
        );
        if (vote is Map && vote['option_id'] != null) {
          _selectedOptionId = vote['option_id'].toString();
        }
      }

      if (_selectedOptionId != null || _isExpired) {
        final rows = await _voteService.getPollVotes(_pollId);
        final next = <String, int>{};
        for (final r in rows) {
          if (r is! Map) continue;
          final oid = r['option_id']?.toString();
          if (oid == null) continue;
          next[oid] = (next[oid] ?? 0) + 1;
        }
        for (final o in _options) {
          final id = o['id']?.toString();
          if (id != null) next.putIfAbsent(id, () => 0);
        }
        _optionVotes = next;
      }
    } catch (_) {
      // Non-fatal; the placeholder/empty state still renders.
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (_pollId.isEmpty || options.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (!_showResults) {
      body = Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Text(
          'Vote to see the full results breakdown.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    } else {
      final total = _optionVotes.values.fold<int>(0, (a, b) => a + b);
      final entries = buildPollChartEntries(
        options: options,
        voteCounts: _optionVotes,
        totalVotes: total,
        selectedOptionId: _selectedOptionId,
      );
      body = SizedBox(
        height: 240,
        child: _PollBarChart(
          entries: entries,
          colorScheme: cs,
          textTheme: theme.textTheme,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results breakdown',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

class _PollBarChart extends StatelessWidget {
  const _PollBarChart({
    required this.entries,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<PollChartEntry> entries;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final labelStyle = textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 11,
    );

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 25,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 25,
              getTitlesWidget: (value, meta) =>
                  Text('${value.toInt()}%', style: labelStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    entries[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final entry = entries[group.x.toInt()];
              return BarTooltipItem(
                '${entry.label}\n${entry.percentage.toStringAsFixed(0)}% · ${entry.count} ${entry.count == 1 ? 'vote' : 'votes'}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].percentage,
                  width: 28,
                  borderRadius: BorderRadius.circular(6),
                  color: entries[i].selected
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0.35),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 100,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
