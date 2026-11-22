import 'dart:math' as math;

import 'package:flutter/material.dart';

const deskInk = Color(0xFF142F34);
const deskGreen = Color(0xFF116858);
const deskMint = Color(0xFFD1F2AD);
const deskCanvas = Color(0xFFF4F6F5);
const deskLine = Color(0xFFD6DFDB);
const deskMuted = Color(0xFF536961);
const deskPaper = Colors.white;
const deskRail = Color(0xFF153631);
const deskRailText = Color(0xFFD3E2DA);
const deskAmber = Color(0xFF825410);
const deskLate = Color(0xFFA33C35);

ThemeData frontdeskTheme() {
  final colors = ColorScheme.fromSeed(seedColor: deskGreen).copyWith(
    primary: deskGreen,
    onPrimary: Colors.white,
    surface: deskPaper,
    onSurface: deskInk,
    outlineVariant: deskLine,
    secondaryContainer: deskMint,
    onSecondaryContainer: deskInk,
    error: const Color(0xFFAB3B32),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'Roboto',
  );
  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: deskLine),
  );
  return base.copyWith(
    scaffoldBackgroundColor: deskCanvas,
    dividerColor: deskLine,
    textTheme: base.textTheme.copyWith(
      headlineMedium: const TextStyle(
        fontSize: 31,
        height: 1.12,
        letterSpacing: -1.15,
        fontWeight: FontWeight.w700,
        color: deskInk,
      ),
      titleLarge: const TextStyle(
        fontSize: 22,
        height: 1.2,
        letterSpacing: -.65,
        fontWeight: FontWeight.w700,
        color: deskInk,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: deskInk,
      ),
    ),
    appBarTheme: const AppBarThemeData(
      backgroundColor: deskPaper,
      foregroundColor: deskInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: deskInk,
      ),
    ),
    cardTheme: CardThemeData(
      color: deskPaper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: deskLine),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: buttonShape,
        side: const BorderSide(color: deskLine),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: Colors.white,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(width: 2, color: deskGreen),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: deskPaper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class DeskPageHeading extends StatelessWidget {
  const DeskPageHeading(
    this.title, {
    super.key,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: const TextStyle(color: deskMuted, height: 1.45),
          ),
        ],
      ],
    );
    if (actions.isEmpty) return heading;
    final buttons = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), buttons],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            buttons,
          ],
        );
      },
    );
  }
}

// A short row of metrics can wrap its labels without misaligning adjacent tiles.
class DeskTileGrid extends StatelessWidget {
  const DeskTileGrid({super.key, required this.columns, required this.children})
    : assert(columns > 0);
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 8,
    children: [
      for (var start = 0; start < children.length; start += columns)
        IntrinsicHeight(
          child: Row(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = start; i < start + columns; i++)
                Expanded(
                  child: i < children.length
                      ? children[i]
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
    ],
  );
}

class DeskEmptyState extends StatelessWidget {
  const DeskEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    semanticContainer: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE9F1EB),
            foregroundColor: deskGreen,
            child: Icon(icon, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    ),
  );
}

class DeskBrand extends StatelessWidget {
  const DeskBrand({super.key, this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? deskMint : deskInk,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CustomPaint(
            size: const Size(22, 22),
            painter: _BrandMark(dark ? deskInk : deskMint),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Frontdesk',
            style: TextStyle(
              fontSize: 23,
              letterSpacing: -1.1,
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : deskInk,
            ),
          ),
        ),
      ),
    ],
  );
}

class _BrandMark extends CustomPainter {
  const _BrandMark(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(2, 3)
      ..lineTo(21, 3)
      ..lineTo(18, 9)
      ..lineTo(9, 9)
      ..lineTo(9, 12)
      ..lineTo(16, 12)
      ..lineTo(13, 17)
      ..lineTo(9, 17)
      ..lineTo(9, 21)
      ..lineTo(2, 21)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BrandMark old) => old.color != color;
}

// The sign-in illustration scales to the available panel.
class TicketArtwork extends StatelessWidget {
  const TicketArtwork({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(painter: const _TicketPrint(), size: Size.infinite),
  );
}

class _TicketPrint extends CustomPainter {
  const _TicketPrint();
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.clipRect(Offset.zero & size);
    final scale = math.min(size.width / 400, size.height / 245);
    c.translate(size.width / 2, size.height / 2);
    c.scale(scale);
    final line = Paint()
      ..color = const Color(0xFF41615B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85;
    for (int i = 0; i < 8; i++) {
      c.drawOval(
        Rect.fromCenter(
          center: const Offset(0, 15),
          width: 338.0 + i * 17,
          height: 142.0 + i * 14,
        ),
        line,
      );
    }
    void ticket(double x, double y, double angle, Color fill, bool front) {
      c.save();
      c.translate(x, y);
      c.rotate(angle);
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-107, -53, 214, 106),
        const Radius.circular(9),
      );
      final shape = Path()..addRRect(rect);
      final cuts = Path()
        ..addOval(Rect.fromCircle(center: const Offset(54, -53), radius: 8))
        ..addOval(Rect.fromCircle(center: const Offset(54, 53), radius: 8));
      final body = Path.combine(PathOperation.difference, shape, cuts);
      c.drawShadow(body, const Color(0xFF112F2E), 4, true);
      c.drawPath(body, Paint()..color = fill);
      final ink = Paint()..color = front ? deskInk : const Color(0xFF5E4837);
      for (int y = -38; y < 40; y += 8) {
        c.drawLine(
          Offset(54, y.toDouble()),
          Offset(54, y + 4.0),
          ink..strokeWidth = 1,
        );
      }
      for (int i = 0; i < 13; i++) {
        c.drawRect(
          Rect.fromLTWH(69, -36 + i * 5.4, 22, i % 3 == 0 ? 3 : 1),
          ink,
        );
      }
      if (front) {
        final title = TextPainter(
          text: const TextSpan(
            text: 'ARVO',
            style: TextStyle(
              color: deskInk,
              fontSize: 35,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        title.paint(c, const Offset(-90, -34));
        title.dispose();
        c.drawLine(
          const Offset(-89, 16),
          const Offset(35, 16),
          ink..strokeWidth = 1,
        );
        for (int i = 0; i < 3; i++) {
          c.drawCircle(Offset(-85.0 + 10 * i, 32), 2.4, ink);
        }
        c.drawLine(const Offset(-48, 32), const Offset(34, 32), ink);
      }
      c.restore();
    }

    ticket(-16, -17, -.31, const Color(0xFFEEA77E), false);
    ticket(12, 18, .14, deskMint, true);
    c.restore();
  }

  @override
  bool shouldRepaint(_TicketPrint old) => false;
}
