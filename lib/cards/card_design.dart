import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CardTemplate {
  final String id;
  final String name;
  final String? backgroundAsset;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final AlignmentGeometry gradientBegin;
  final AlignmentGeometry gradientEnd;
  final bool darkText;

  const CardTemplate({
    required this.id,
    required this.name,
    this.backgroundAsset,
    this.gradientColors = const [Color(0xFF111827), Color(0xFF374151)],
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.darkText = false,
  });

  Color get textColor => darkText ? Colors.black87 : Colors.white;
  Color get subtextColor => darkText ? Colors.black54 : Colors.white70;
}

// ✅ FIXED: dark/neon/turquoise backgrounds now use white text (darkText = false)
const _cardTemplates = <CardTemplate>[
  CardTemplate(
    id: 'card_bg_light',
    name: 'Light',
    backgroundAsset: 'assets/card-bg-light.PNG',
    darkText: true, // black text on light background
  ),
  CardTemplate(
    id: 'card_bg_dark',
    name: 'Dark',
    backgroundAsset: 'assets/card-bg-dark.png',
    darkText: false, // white text on dark background
  ),
  CardTemplate(
    id: 'card_bg_torquoise',
    name: 'Torquiose',
    backgroundAsset: 'assets/card-bg-torquoise.png',
    darkText: false, // white text on turquoise background
  ),
  CardTemplate(
    id: 'card_bg_neon',
    name: 'Neon',
    backgroundAsset: 'assets/card-bg-neon.png',
    darkText: false, // white text on neon background
  ),
  CardTemplate(
    id: 'card_bg_gold',
    name: 'Gold',
    backgroundAsset: 'assets/card-bg-gold.PNG',
    darkText: true, // black text on gold background
  ),
];

List<CardTemplate> getTemplatesForCard(String brand, String currency) {
  return _cardTemplates;
}

CardTemplate? getTemplateById(String id) {
  for (final template in _cardTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

class PadiCardWidget extends StatelessWidget {
  final CardTemplate template;
  final String brand;
  final String currency;
  final String cardHolder;
  final String cardNumber;
  final String expiry;
  final String cardType;
  final bool showDetails;
  final bool isLoading;
  final Color? colorOverride;
  final double? width;

  const PadiCardWidget({
    super.key,
    required this.template,
    required this.brand,
    required this.currency,
    this.cardHolder = 'CARD HOLDER',
    this.cardNumber = '**** **** **** ****',
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
    final cardH = cardW * 0.63;
    final hasImageBackground =
        template.backgroundAsset != null && colorOverride == null;

    final colors = _resolveColors();
    final textColor = hasImageBackground
        ? template.textColor
        : _isLightColor(colors[colors.length ~/ 2])
        ? Colors.black87
        : Colors.white;
    final subtextColor = hasImageBackground
        ? template.subtextColor
        : _isLightColor(colors[colors.length ~/ 2])
        ? Colors.black45
        : Colors.white70;

    return SizedBox(
      width: cardW,
      height: cardH,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.5),
              spreadRadius: 2,
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Background
              Positioned.fill(
                child: hasImageBackground
                    ? Image.asset(template.backgroundAsset!, fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: colors,
                            stops: template.gradientStops,
                            begin: template.gradientBegin,
                            end: template.gradientEnd,
                          ),
                        ),
                      ),
              ),
              // Currency (top right)
              Positioned(
                top: cardH * 0.14,
                right: cardW * 0.06,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardW * 0.03,
                    vertical: cardH * 0.008,
                  ),
                  decoration: BoxDecoration(
                    color: _getBadgeColor(textColor),
                    borderRadius: BorderRadius.circular(cardW * 0.04),
                  ),
                  child: Text(
                    currency,
                    style: GoogleFonts.inter(
                      color: textColor,
                      fontSize: cardW * 0.04,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Card number
              Positioned(
                top: cardH * 0.52,
                left: cardW * 0.06,
                right: cardW * 0.06,
                child: Text(
                  cardNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sourceCodePro(
                    color: textColor,
                    fontSize: cardW * 0.06,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              // Card holder
              if (cardHolder.trim().isNotEmpty)
                Positioned(
                  bottom: cardH * 0.08,
                  left: cardW * 0.06,
                  right: cardW * 0.36,
                  child: _CardDataBlock(
                    value: cardHolder.toUpperCase(),
                    textColor: textColor,
                    subtextColor: subtextColor,
                    cardW: cardW,
                  ),
                ),
              // Expiry
              Positioned(
                bottom: cardH * 0.25,
                left: cardW * 0.72,
                right: cardW * 0.01,
                child: Text(
                  expiry,
                  style: GoogleFonts.inter(
                    color: textColor,
                    fontSize: cardW * 0.038,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Brand logo
              Positioned(
                right: cardW * 0.06,
                bottom: cardH * 0.08,
                child: _BrandLogo(brand: brand, width: cardW * 0.17),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getBadgeColor(Color textColor) {
    // If text is light, use a dark semi‑transparent background.
    // If text is dark, use a light semi‑transparent background.
    final isLightText = textColor.computeLuminance() > 0.5;
    return isLightText
        ? Colors.black.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.2);
  }

  List<Color> _resolveColors() {
    if (colorOverride == null) return template.gradientColors;

    final hsl = HSLColor.fromColor(colorOverride!);
    return [
      hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor(),
      colorOverride!,
      hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor(),
    ];
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }
}

class _CardDataBlock extends StatelessWidget {
  final String value;
  final Color textColor;
  final Color subtextColor;
  final double cardW;

  const _CardDataBlock({
    required this.value,
    required this.textColor,
    required this.subtextColor,
    required this.cardW,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: textColor,
            fontSize: cardW * 0.05,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final String brand;
  final double width;

  const _BrandLogo({required this.brand, required this.width});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetForBrand(brand),
      width: width,
      fit: BoxFit.contain,
    );
  }

  String _assetForBrand(String value) {
    final brandName = value.toLowerCase();
    if (brandName.contains('master')) return 'assets/mastercard.png';
    if (brandName.contains('verve')) return 'assets/verve.png';
    if (brandName.contains('afrigo')) return 'assets/afrigo.png';
    return 'assets/visa.png';
  }
}
