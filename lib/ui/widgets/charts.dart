import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';

class ChartPoint {
  final String label;
  final double value;
  const ChartPoint(this.label, this.value);
}

/// Hand-drawn bar chart. Deliberately dependency-free: one CustomPainter is
/// far lighter than a charting package on a 4 GB Windows machine.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.points,
    this.height = 170,
    this.color,
    this.showValues = true,
  });

  final List<ChartPoint> points;
  final double height;
  final Color? color;
  final bool showValues;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data for this period',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final scheme = Theme.of(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarPainter(
          points: points,
          color: color ?? scheme.colorScheme.primary,
          gridColor: AppTheme.borderOf(context),
          labelColor: scheme.colorScheme.onSurfaceVariant,
          valueColor: scheme.colorScheme.onSurface,
          showValues: showValues,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.points,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.valueColor,
    required this.showValues,
  });

  final List<ChartPoint> points;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final Color valueColor;
  final bool showValues;

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 18.0;
    const valueHeight = 14.0;
    final chartTop = showValues ? valueHeight : 0.0;
    final chartHeight = size.height - labelHeight - chartTop;
    if (chartHeight <= 0) return;

    final maxValue =
        points.fold<double>(0, (m, p) => math.max(m, p.value.abs()));
    final scale = maxValue <= 0 ? 0.0 : chartHeight / (maxValue * 1.15);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartTop + chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final slot = size.width / points.length;
    final barWidth = math.min(34.0, slot * 0.55);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final barHeight = (p.value.abs() * scale).clamp(0.0, chartHeight);
      final left = slot * i + (slot - barWidth) / 2;
      final top = chartTop + chartHeight - barHeight;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, math.max(barHeight, 1)),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0.55)],
      ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);

      _text(canvas, p.label, Offset(slot * i + slot / 2, size.height - 14),
          labelColor, 9.5, slot);
      if (showValues && p.value != 0) {
        _text(canvas, Fmt.compact(p.value),
            Offset(slot * i + slot / 2, top - 13), valueColor, 9.5, slot);
      }
    }
  }

  void _text(Canvas canvas, String text, Offset center, Color color,
      double size, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.points != points || old.color != color;
}

/// Horizontal ranked bars — top products, top customers, ageing buckets.
class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.points,
    this.color,
    this.moneyFormat = true,
    this.maxRows = 8,
  });

  final List<ChartPoint> points;
  final Color? color;
  final bool moneyFormat;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Nothing to show yet',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final rows = points.take(maxRows).toList();
    final max = rows.fold<double>(0, (m, p) => math.max(m, p.value.abs()));
    final c = color ?? Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppTheme.subtleOf(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor:
                            max <= 0 ? 0 : (p.value.abs() / max).clamp(0.02, 1),
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: Text(
                    moneyFormat ? Fmt.money(p.value) : Fmt.qty(p.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
