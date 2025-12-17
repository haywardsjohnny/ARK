import 'package:flutter/material.dart';

/// A status bar widget that displays a percentage with color gradient
/// 0% = red, 100% = green, gradually transitions between
class StatusBar extends StatelessWidget {
  final double percentage; // 0.0 to 1.0
  final double height;
  final String? label;
  final bool showPercentage;

  const StatusBar({
    super.key,
    required this.percentage,
    this.height = 8.0,
    this.label,
    this.showPercentage = true,
  });

  /// Get color based on percentage (0% = red, 100% = green)
  Color _getColor(double pct) {
    // Clamp percentage between 0 and 1
    final clamped = pct.clamp(0.0, 1.0);
    
    // Interpolate between red and green
    if (clamped <= 0.5) {
      // 0% to 50%: Red to Yellow
      final ratio = clamped * 2; // 0 to 1
      return Color.lerp(Colors.red, Colors.orange, ratio)!;
    } else {
      // 50% to 100%: Yellow to Green
      final ratio = (clamped - 0.5) * 2; // 0 to 1
      return Color.lerp(Colors.orange, Colors.green, ratio)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = percentage.clamp(0.0, 1.0);
    final color = _getColor(pct);
    final percentageText = '${(pct * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (showPercentage)
                Text(
                  percentageText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

