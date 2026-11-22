import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'frontdesk_design.dart';

const _resolvedColor = Color(0xFF167362);
const _inactivityColor = Color(0xFFBF8030);
const _chartTrack = Color(0xFFE7EDE9);

class ClosureBucket {
  ClosureBucket.fromJson(Map<String, dynamic> data)
    : start = DateTime.parse(data['from'] as String),
      end = DateTime.parse(data['to'] as String),
      resolved = data['resolved'] as int,
      inactive = data['closed_inactivity'] as int;

  final DateTime start, end;
  final int resolved, inactive;

  String dateLabel(MaterialLocalizations locale) {
    final first = locale.formatShortMonthDay(start);
    return start == end ? first : '$first – ${locale.formatShortMonthDay(end)}';
  }
}

class ResolverTotal {
  ResolverTotal.fromJson(Map<String, dynamic> data)
    : name = data['name'] as String,
      resolved = data['resolved'] as int,
      onTime = data['on_time'] as int;

  final String name;
  final int resolved, onTime;
}

class ClosureActivityChart extends StatefulWidget {
  const ClosureActivityChart({
    super.key,
    required this.buckets,
    required this.intervalDays,
  });

  final List<ClosureBucket> buckets;
  final int intervalDays;

  @override
  State<ClosureActivityChart> createState() => _ClosureActivityChartState();
}

class _ClosureActivityChartState extends State<ClosureActivityChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    const height = 156.0;
    const gridLines = 4;
    final peak = buckets.fold(
      0,
      (highest, bucket) =>
          math.max(highest, math.max(bucket.resolved, bucket.inactive)),
    );
    final step = math.max(1, (peak / gridLines).ceil());
    final maximum = step * gridLines;
    final locale = MaterialLocalizations.of(context);
    final selectedIndex =
        _selectedIndex != null && _selectedIndex! < buckets.length
        ? _selectedIndex!
        : buckets.lastIndexWhere(
            (bucket) => bucket.resolved + bucket.inactive > 0,
          );

    return _ReportPanel(
      title: 'Closure activity',
      subtitle: widget.intervalDays == 1
          ? 'Daily totals · IST'
          : '${widget.intervalDays}-day totals · IST',
      children: [
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _LegendItem('Resolved', _resolvedColor),
            _LegendItem('Closed for inactivity', _inactivityColor),
          ],
        ),
        const SizedBox(height: 18),
        if (peak == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No ticket closures in this period.',
              style: TextStyle(color: deskMuted),
            ),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: height + 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var tick = maximum; tick >= 0; tick -= step)
                          Text(
                            locale.formatDecimal(tick),
                            style: const TextStyle(
                              color: deskMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final groupWidth = bounds.maxWidth / buckets.length;
                    final labelEvery = math.max(1, (30 / groupWidth).ceil());
                    return Stack(
                      children: [
                        Positioned(
                          top: 6,
                          left: 0,
                          right: 0,
                          height: height - 6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (var i = 0; i <= gridLines; i++)
                                const Divider(height: 1, color: _chartTrack),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < buckets.length; i++)
                              Expanded(
                                child: _ChartGroup(
                                  bucket: buckets[i],
                                  height: height,
                                  maximum: maximum,
                                  selected: selectedIndex == i,
                                  axisLabel: groupWidth >= 62
                                      ? locale.formatShortMonthDay(
                                          buckets[i].start,
                                        )
                                      : i % labelEvery == 0
                                      ? locale.formatDecimal(
                                          buckets[i].start.day,
                                        )
                                      : '',
                                  onTap: () =>
                                      setState(() => _selectedIndex = i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (selectedIndex >= 0)
            _ActivitySelection(bucket: buckets[selectedIndex]),
        ],
      ],
    );
  }
}

class _ChartGroup extends StatelessWidget {
  const _ChartGroup({
    required this.bucket,
    required this.height,
    required this.maximum,
    required this.selected,
    required this.axisLabel,
    required this.onTap,
  });

  final ClosureBucket bucket;
  final double height;
  final int maximum;
  final bool selected;
  final String axisLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    final label =
        '${bucket.dateLabel(locale)}, ${bucket.resolved} resolved, ${bucket.inactive} closed for inactivity';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Column(
            children: [
              SizedBox(
                height: height,
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final barWidth = math.min(28.0, bounds.maxWidth * .43);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: bounds.maxWidth * .08,
                        children: [
                          for (final (total, color) in [
                            (bucket.resolved, _resolvedColor),
                            (bucket.inactive, _inactivityColor),
                          ])
                            Container(
                              width: barWidth,
                              height: (height - 6) * total / maximum,
                              decoration: BoxDecoration(
                                color: selected
                                    ? color
                                    : color.withValues(alpha: .80),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 17,
                child: Text(
                  axisLabel,
                  overflow: TextOverflow.clip,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected ? deskGreen : deskMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: deskMuted)),
    ],
  );
}

class _ActivitySelection extends StatelessWidget {
  const _ActivitySelection({required this.bucket});
  final ClosureBucket bucket;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: deskCanvas,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          bucket.dateLabel(MaterialLocalizations.of(context)),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        Text(
          '${bucket.resolved} resolved',
          style: const TextStyle(color: deskMuted, fontSize: 12),
        ),
        Text(
          '${bucket.inactive} closed for inactivity',
          style: const TextStyle(color: deskMuted, fontSize: 12),
        ),
      ],
    ),
  );
}

class ResolutionLeaderboard extends StatefulWidget {
  const ResolutionLeaderboard({super.key, required this.entries});
  final List<ResolverTotal> entries;

  @override
  State<ResolutionLeaderboard> createState() => _ResolutionLeaderboardState();
}

class _ResolutionLeaderboardState extends State<ResolutionLeaderboard> {
  static const _previewLength = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final visible = _showAll ? entries : entries.take(_previewLength);
    final rows = <Widget>[];
    var rank = 0;
    var position = 0;
    int? previousTotal;
    for (final entry in visible) {
      position++;
      if (entry.resolved != previousTotal) rank = position;
      previousTotal = entry.resolved;
      rows.add(
        _LeaderboardRow(
          rank: rank,
          entry: entry,
          highest: entries.first.resolved,
        ),
      );
    }
    return _ReportPanel(
      title: 'Resolution leaderboard',
      subtitle:
          'Each resolution credits the staff member who closed that cycle.',
      children: [
        if (entries.isEmpty)
          const Text(
            'No recorded staff resolutions in this period.',
            style: TextStyle(color: deskMuted),
          ),
        ...rows,
        if (entries.length > _previewLength)
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(
              _showAll
                  ? 'Show top $_previewLength'
                  : 'Show all ${entries.length} staff',
            ),
          ),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.entry,
    required this.highest,
  });
  final int rank, highest;
  final ResolverTotal entry;

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label:
            'Rank $rank, ${entry.name}, ${entry.resolved} resolved, ${entry.onTime} on time',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 9,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: rank == 1 ? deskMint : deskCanvas,
              foregroundColor: rank == 1 ? deskInk : deskMuted,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: entry.resolved / highest,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                    color: _resolvedColor,
                    backgroundColor: _chartTrack,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${locale.formatDecimal(entry.onTime)} on time',
                    style: const TextStyle(fontSize: 12, color: deskMuted),
                  ),
                ],
              ),
            ),
            Text(
              locale.formatDecimal(entry.resolved),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    semanticContainer: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: deskMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}
