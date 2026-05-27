import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final AlignmentGeometry? alignment;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.margin,
    this.borderRadius = 24.0,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF141414) 
                : Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
            border: isDark ? Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.0,
            ) : null,
            boxShadow: isDark ? [] : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Align(
            alignment: alignment ?? Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
