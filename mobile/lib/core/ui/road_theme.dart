import 'package:flutter/material.dart';

class RoadUi {
  const RoadUi._();

  static const Color asphalt900 = Color(0xFF111317);
  static const Color asphalt800 = Color(0xFF1D2128);
  static const Color asphalt700 = Color(0xFF2A2D33);
  static const Color laneMark = Color(0xFFEDEFF3);
  static const Color caution = Color(0xFFFFB200);
  static const Color panel = Color(0xFFF8FAFD);
  static const Color panelBorder = Color(0xFFDDE3EE);
  static const Color textPrimary = Color(0xFF1F2530);
  static const Color textMuted = Color(0xFF61708B);

  static ThemeData buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: caution,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: asphalt900,
      appBarTheme: const AppBarTheme(
        backgroundColor: asphalt900,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
        prefixIconColor: textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: panelBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: caution, width: 1.6),
        ),
      ),
    );
  }
}

class RoadBackground extends StatelessWidget {
  const RoadBackground({
    super.key,
    required this.child,
    this.showCenterLane = true,
  });

  final Widget child;
  final bool showCenterLane;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[RoadUi.asphalt700, RoadUi.asphalt900],
            ),
          ),
        ),
        if (showCenterLane) const Positioned.fill(child: _LaneMarking()),
        child,
      ],
    );
  }
}

class RoadPanel extends StatelessWidget {
  const RoadPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: RoadUi.panel.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RoadUi.panelBorder),
      ),
      child: child,
    );
  }
}

class RoadSectionHeader extends StatelessWidget {
  const RoadSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.shield_outlined,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: RoadUi.caution.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: RoadUi.caution),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: RoadUi.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: RoadUi.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class RoadStatusChip extends StatelessWidget {
  const RoadStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LaneMarking extends StatelessWidget {
  const _LaneMarking();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: 26,
          child: Column(
            children: List<Widget>.generate(16, (index) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? RoadUi.laneMark.withValues(alpha: 0.34)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
