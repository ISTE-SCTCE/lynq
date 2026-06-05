import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────
//  LynqIllustrationCard
//  Large colored card with flat vector illustration.
//  Used on the home screen and event sections.
//  Height: ~175px — compact enough for execom's dense info.
// ─────────────────────────────────────────────────────────────

class LynqIllustrationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color textColor;
  final Widget illustration;
  final String? primaryBtnLabel;
  final String? secondaryBtnLabel;
  final VoidCallback? onPrimaryTap;
  final VoidCallback? onSecondaryTap;
  /// If true, renders a single arrow-forward icon button instead of two buttons
  final bool compact;

  const LynqIllustrationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    this.textColor = Colors.white,
    required this.illustration,
    this.primaryBtnLabel,
    this.secondaryBtnLabel,
    this.onPrimaryTap,
    this.onSecondaryTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 175,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Illustration — right side
          Positioned(
            right: 0,
            bottom: 0,
            top: 0,
            width: 155,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              child: illustration,
            ),
          ),

          // Subtle gradient overlay so text stays readable over illustration
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    backgroundColor,
                    backgroundColor.withOpacity(0.85),
                    backgroundColor.withOpacity(0.2),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // Content — left side
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 100, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title + subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: textColor.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),

                // Buttons
                if (compact)
                  _ArrowButton(color: textColor, onTap: onPrimaryTap)
                else if (primaryBtnLabel != null)
                  Row(
                    children: [
                      if (secondaryBtnLabel != null) ...[
                        Expanded(
                          child: _PillButton(
                            label: secondaryBtnLabel!,
                            filled: false,
                            textColor: textColor,
                            onTap: onSecondaryTap,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _PillButton(
                          label: primaryBtnLabel!,
                          filled: true,
                          textColor: textColor,
                          onTap: onPrimaryTap,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final Color textColor;
  final VoidCallback? onTap;

  const _PillButton({
    required this.label,
    required this.filled,
    required this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: filled ? textColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withOpacity(0.6), width: 1.4),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: filled
                  ? (textColor == Colors.white
                      ? const Color(0xFF1A1A1A)
                      : Colors.white)
                  : textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;
  const _ArrowButton({required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_forward_rounded,
          size: 18,
          color: color == Colors.white ? const Color(0xFF1A1A1A) : Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Predefined card color presets (reference-inspired palette)
// ─────────────────────────────────────────────────────────────

class LynqCardColors {
  /// Slate blue — matches reference's first card
  static const slate = Color(0xFF5F7FA8);
  /// Lavender purple — matches reference's second card
  static const lavender = Color(0xFF9B8EC4);
  /// Warm terracotta — lynq's accent
  static const terracotta = Color(0xFFD97D55);
  /// Sage green
  static const sage = Color(0xFF6B9E8A);
  /// Muted teal
  static const teal = Color(0xFF4A8FA0);

  /// Cycling list for sequential cards
  static const List<Color> sequence = [slate, lavender, terracotta, sage, teal];

  static Color atIndex(int i) => sequence[i % sequence.length];
}
