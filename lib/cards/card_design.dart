import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Card template model ───────────────────────────────────────────────────

class CardTemplate {
  final String id;
  final String name;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final AlignmentGeometry gradientBegin;
  final AlignmentGeometry gradientEnd;
  final String? patternType;  // 'circles', 'waves', 'diagonals', 'mesh', 'none'
  final Color patternColor;
  final bool darkText;

  const CardTemplate({
    required this.id,
    required this.name,
    required this.gradientColors,
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.patternType = 'none',
    this.patternColor = Colors.white,
    this.darkText = false,
  });

  Color get textColor => darkText ? Colors.black87 : Colors.white;
  Color get subtextColor => darkText ? Colors.black54 : Colors.white70;
}

// ── Pre-designed templates per brand + currency ───────────────────────────

const _kTemplates = <String, List<CardTemplate>>{
  // --- USD Visa ---
  'Visa_USD': [
    CardTemplate(
      id: 'visa_usd_midnight',
      name: 'Midnight',
      gradientColors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
      patternType: 'circles',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'visa_usd_ocean',
      name: 'Ocean',
      gradientColors: [Color(0xFF1565C0), Color(0xFF0288D1), Color(0xFF00ACC1)],
      patternType: 'waves',
      patternColor: Color(0x20FFFFFF),
    ),
    CardTemplate(
      id: 'visa_usd_pearl',
      name: 'Pearl',
      gradientColors: [Color(0xFFF5F5F5), Color(0xFFE8E8E8), Color(0xFFD4D4D4)],
      patternType: 'diagonals',
      patternColor: Color(0x12000000),
      darkText: true,
    ),
    CardTemplate(
      id: 'visa_usd_dusk',
      name: 'Dusk',
      gradientColors: [Color(0xFF4A0072), Color(0xFFAD1457), Color(0xFFFF6090)],
      patternType: 'waves',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'visa_usd_slate',
      name: 'Slate',
      gradientColors: [Color(0xFF263238), Color(0xFF37474F), Color(0xFF546E7A)],
      patternType: 'mesh',
      patternColor: Color(0x14FFFFFF),
    ),
  ],

  // --- USD MasterCard ---
  'MasterCard_USD': [
    CardTemplate(
      id: 'mc_usd_ember',
      name: 'Ember',
      gradientColors: [Color(0xFFE53935), Color(0xFFFF6F00), Color(0xFFFFCA28)],
      patternType: 'mesh',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'mc_usd_graphite',
      name: 'Graphite',
      gradientColors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
      patternType: 'circles',
      patternColor: Color(0x15FFFFFF),
    ),
    CardTemplate(
      id: 'mc_usd_aurora',
      name: 'Aurora',
      gradientColors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
      patternType: 'waves',
      patternColor: Color(0x1AFFFFFF),
    ),
    CardTemplate(
      id: 'mc_usd_lava',
      name: 'Lava',
      gradientColors: [Color(0xFF0D0D0D), Color(0xFF7B0000), Color(0xFFE53935)],
      patternType: 'circles',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'mc_usd_frost',
      name: 'Frost',
      gradientColors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF80DEEA)],
      patternType: 'diagonals',
      patternColor: Color(0x10000000),
      darkText: true,
    ),
  ],

  // --- NGN Verve ---
  'Verve_NGN': [
    CardTemplate(
      id: 'verve_ngn_forest',
      name: 'Forest',
      gradientColors: [Color(0xFF0B3D2E), Color(0xFF1B5E20), Color(0xFF2E7D32)],
      patternType: 'diagonals',
      patternColor: Color(0x1AFFFFFF),
    ),
    CardTemplate(
      id: 'verve_ngn_cocoa',
      name: 'Cocoa',
      gradientColors: [Color(0xFF3E2723), Color(0xFF5D4037), Color(0xFF795548)],
      patternType: 'mesh',
      patternColor: Color(0x15FFFFFF),
    ),
    CardTemplate(
      id: 'verve_ngn_savanna',
      name: 'Savanna',
      gradientColors: [Color(0xFFF9A825), Color(0xFFFF8F00), Color(0xFFEF6C00)],
      patternType: 'circles',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'verve_ngn_lagoon',
      name: 'Lagoon',
      gradientColors: [Color(0xFF006064), Color(0xFF00838F), Color(0xFF26C6DA)],
      patternType: 'waves',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'verve_ngn_sunburst',
      name: 'Sunburst',
      gradientColors: [Color(0xFFFF6F00), Color(0xFFFFCA28), Color(0xFFFFF9C4)],
      patternType: 'diagonals',
      patternColor: Color(0x12000000),
      darkText: true,
    ),
  ],

  // --- NGN AfriGo ---
  'AfriGo_NGN': [
    CardTemplate(
      id: 'afrigo_ngn_indigo',
      name: 'Indigo',
      gradientColors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF3949AB)],
      patternType: 'waves',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'afrigo_ngn_terracotta',
      name: 'Terracotta',
      gradientColors: [Color(0xFFBF360C), Color(0xFFD84315), Color(0xFFF4511E)],
      patternType: 'diagonals',
      patternColor: Color(0x15FFFFFF),
    ),
    CardTemplate(
      id: 'afrigo_ngn_onyx',
      name: 'Onyx',
      gradientColors: [Color(0xFF212121), Color(0xFF424242), Color(0xFF616161)],
      patternType: 'mesh',
      patternColor: Color(0x12FFFFFF),
    ),
    CardTemplate(
      id: 'afrigo_ngn_royal',
      name: 'Royal',
      gradientColors: [Color(0xFF1A0533), Color(0xFF4A148C), Color(0xFF7B1FA2)],
      patternType: 'circles',
      patternColor: Color(0x18FFFFFF),
    ),
    CardTemplate(
      id: 'afrigo_ngn_bronze',
      name: 'Bronze',
      gradientColors: [Color(0xFF3E1C00), Color(0xFF7B4800), Color(0xFFBF8940)],
      patternType: 'mesh',
      patternColor: Color(0x15FFFFFF),
    ),
  ],
};

List<CardTemplate> getTemplatesForCard(String brand, String currency) {
  final key = '${brand}_$currency';
  return _kTemplates[key] ?? _kTemplates.values.first;
}

CardTemplate? getTemplateById(String id) {
  for (final list in _kTemplates.values) {
    for (final t in list) {
      if (t.id == id) return t;
    }
  }
  return null;
}

// ── The card widget itself ────────────────────────────────────────────────

class PadiCardWidget extends StatelessWidget {
  final CardTemplate template;
  final String brand;       // 'Visa', 'MasterCard', 'Verve', 'AfriGo'
  final String currency;    // 'NGN', 'USD'
  final String cardHolder;
  final String cardNumber;  // e.g. '•••• •••• •••• 1234'
  final String expiry;      // 'MM/YY'
  final String cardType;    // 'Virtual', 'Anonymous', 'Physical'
  final bool showDetails;
  final bool isLoading;
  final Color? colorOverride;  // For virtual card color customization
  final double? width;

  const PadiCardWidget({
    super.key,
    required this.template,
    required this.brand,
    required this.currency,
    this.cardHolder = 'CARD HOLDER',
    this.cardNumber = '•••• •••• •••• ••••',
    this.expiry = 'MM/YY',
    this.cardType = 'Virtual',
    this.showDetails = true,
    this.isLoading = false,
    this.colorOverride,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cardW = width ?? MediaQuery.of(context).size.width * 0.85;
    final cardH = cardW * 0.63; // standard card ratio

    List<Color> colors = template.gradientColors;
    if (colorOverride != null) {
      // Create a gradient from the override color
      final hsl = HSLColor.fromColor(colorOverride!);
      colors = [
        hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor(),
        colorOverride!,
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor(),
      ];
    }

    final textColor = _isLightColor(colors[colors.length ~/ 2])
        ? Colors.black87
        : Colors.white;
    final subtextColor = _isLightColor(colors[colors.length ~/ 2])
        ? Colors.black45
        : Colors.white70;

    return SizedBox(
      width: cardW,
      height: cardH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // ── Gradient background ──
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  stops: template.gradientStops,
                  begin: template.gradientBegin,
                  end: template.gradientEnd,
                ),
              ),
            ),

            // ── Pattern overlay ──
            if (template.patternType != 'none')
              Positioned.fill(
                child: CustomPaint(
                  painter: _PatternPainter(
                    type: template.patternType ?? 'none',
                    color: colorOverride != null
                        ? (textColor == Colors.white
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06))
                        : template.patternColor,
                  ),
                ),
              ),

            // ── Chip icon ──
            Positioned(
              top: cardH * 0.35,
              left: cardW * 0.06,
              child: Container(
                width: cardW * 0.1,
                height: cardH * 0.18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFD4AF37),
                      const Color(0xFFF5E6A3),
                      const Color(0xFFD4AF37),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (_) => Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 3),
                      color: const Color(0xAAC09800),
                    )),
                  ),
                ),
              ),
            ),

            // ── Contactless icon ──
            Positioned(
              top: cardH * 0.35,
              left: cardW * 0.18,
              child: Transform.rotate(
                angle: math.pi / 2,
                child: Icon(
                  Icons.wifi,
                  color: textColor.withValues(alpha: 0.6),
                  size: cardW * 0.055,
                ),
              ),
            ),

            // ── Card type label (top-right: brand + type/currency) ──
            Positioned(
              top: cardH * 0.05,
              right: cardW * 0.06,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BrandLogo(brand: brand, size: cardW * 0.16),
                  SizedBox(height: cardH * 0.015),
                  Text(
                    '${cardType.toUpperCase()} $currency',
                    style: GoogleFonts.inter(
                      color: subtextColor,
                      fontSize: cardW * 0.028,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── PadiPay logo ──
            Positioned(
              top: cardH * 0.05,
              left: cardW * 0.06,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: cardW * 0.14,
                    height: cardW * 0.14,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(width: cardW * 0.025),
                  Text(
                    'PadiPay',
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: cardW * 0.068,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // ── Card number ──
            Positioned(
              top: cardH * 0.56,
              left: cardW * 0.06,
              right: cardW * 0.06,
              child: Text(
                cardNumber,
                style: GoogleFonts.sourceCodePro(
                  color: textColor,
                  fontSize: cardW * 0.048,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ),

            // ── Card holder ──
            if (cardHolder.trim().isNotEmpty)
              Positioned(
                bottom: cardH * 0.08,
                left: cardW * 0.06,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CARD HOLDER',
                      style: GoogleFonts.inter(
                        color: subtextColor,
                        fontSize: cardW * 0.022,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cardHolder.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: cardW * 0.032,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Expiry ──
            Positioned(
              bottom: cardH * 0.08,
              right: cardW * 0.25,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EXPIRES',
                    style: GoogleFonts.inter(
                      color: subtextColor,
                      fontSize: cardW * 0.022,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expiry,
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: cardW * 0.032,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),


          ],
        ),
      ),
    );
  }

  bool _isLightColor(Color c) {
    return c.computeLuminance() > 0.5;
  }
}

// ── Brand logo ─────────────────────────────────────────────────────────────

class _BrandLogo extends StatelessWidget {
  final String brand;
  final double size;
  const _BrandLogo({required this.brand, required this.size});

  @override
  Widget build(BuildContext context) {
    final b = brand.toLowerCase();
    String asset;
    if (b.contains('master')) {
      asset = 'assets/mastercard.png';
    } else if (b.contains('verve')) {
      asset = 'assets/verve.png';
    } else if (b.contains('afrigo')) {
      asset = 'assets/afrigo.png';
    } else {
      asset = 'assets/visa.png';
    }
    return Image.asset(
      asset,
      width: size,
      fit: BoxFit.contain,
    );
  }
}

// ── Pattern painter ────────────────────────────────────────────────────────

class _PatternPainter extends CustomPainter {
  final String type;
  final Color color;
  _PatternPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    switch (type) {
      case 'circles':
        _paintCircles(canvas, size, paint);
        break;
      case 'waves':
        _paintWaves(canvas, size, paint);
        break;
      case 'diagonals':
        _paintDiagonals(canvas, size, paint);
        break;
      case 'mesh':
        _paintMesh(canvas, size, paint);
        break;
    }
  }

  void _paintCircles(Canvas canvas, Size size, Paint paint) {
    final cx = size.width * 0.75;
    final cy = size.height * 0.4;
    for (int i = 1; i <= 6; i++) {
      canvas.drawCircle(Offset(cx, cy), i * size.width * 0.08, paint);
    }
  }

  void _paintWaves(Canvas canvas, Size size, Paint paint) {
    for (int i = 0; i < 5; i++) {
      final path = Path();
      final y = size.height * (0.2 + i * 0.18);
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += size.width * 0.1) {
        path.quadraticBezierTo(
          x + size.width * 0.025, y - 12 + (i % 2 == 0 ? -8 : 8),
          x + size.width * 0.05, y,
        );
        path.quadraticBezierTo(
          x + size.width * 0.075, y + 12 + (i % 2 == 0 ? 8 : -8),
          x + size.width * 0.1, y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintDiagonals(Canvas canvas, Size size, Paint paint) {
    const spacing = 28.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  void _paintMesh(Canvas canvas, Size size, Paint paint) {
    // Hexagonal mesh
    const hexR = 30.0;
    final dw = hexR * 1.732; // sqrt(3)
    final dh = hexR * 1.5;
    bool oddRow = false;
    for (double y = -hexR; y < size.height + hexR; y += dh) {
      final offset = oddRow ? dw / 2 : 0.0;
      for (double x = -dw + offset; x < size.width + dw; x += dw) {
        _drawHex(canvas, Offset(x, y), hexR, paint);
      }
      oddRow = !oddRow;
    }
  }

  void _drawHex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (60 * i - 30) * math.pi / 180;
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.type != type || old.color != color;
}
