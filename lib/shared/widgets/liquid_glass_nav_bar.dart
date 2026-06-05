import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class LiquidGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final List<LiquidNavItem> items;
  final Function(int) onItemSelected;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final navBarHeight = 70.0;
    final navBarWidth = (size.width * 0.95).clamp(300.0, 500.0);
    final safeSelectedIndex = selectedIndex.clamp(0, items.length - 1).toInt();

    return SizedBox(
      height: navBarHeight + 35,
      width: size.width,
      child: Center(
        child: Container(
          width: navBarWidth,
          height: navBarHeight,
          margin: const EdgeInsets.only(bottom: 25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
                spreadRadius: -5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141414).withValues(alpha: 0.65)
                      : Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(35),
                  border: isDark ? Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.0,
                  ) : Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: isDark ? [] : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    _LiquidSelector(
                      selectedIndex: safeSelectedIndex,
                      itemsCount: items.length,
                      navBarWidth: navBarWidth - 20,
                      isDark: isDark,
                    ),
                    Row(
                      children: List.generate(items.length, (index) {
                        final isSelected = safeSelectedIndex == index;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => onItemSelected(index),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 450),
                                    curve: Curves.easeOutBack,
                                    top: isSelected ? 14 : 23,
                                    child: AnimatedScale(
                                      scale: isSelected ? 1.15 : 1.0,
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      curve: Curves.easeOutBack,
                                      child: Icon(
                                        isSelected
                                            ? items[index].selectedIcon
                                            : items[index].icon,
                                        color: isSelected
                                            ? (isDark
                                                  ? AppTheme.secondary
                                                  : AppTheme.darkGreen)
                                            : Colors.grey.withValues(
                                                alpha: 0.6,
                                              ),
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOutCubic,
                                    bottom: isSelected ? 14 : -20,
                                    child: AnimatedOpacity(
                                      opacity: isSelected ? 1.0 : 0.0,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: Text(
                                        items[index].label.toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                          color: isDark
                                              ? Colors.white
                                              : AppTheme.darkGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidSelector extends StatefulWidget {
  final int selectedIndex;
  final int itemsCount;
  final double navBarWidth;
  final bool isDark;

  const _LiquidSelector({
    required this.selectedIndex,
    required this.itemsCount,
    required this.navBarWidth,
    required this.isDark,
  });

  @override
  State<_LiquidSelector> createState() => _LiquidSelectorState();
}

class _LiquidSelectorState extends State<_LiquidSelector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _stretchAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _stretchAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.3,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(_LiquidSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemsCount <= 0) return const SizedBox.shrink();

    final itemWidth = widget.navBarWidth / widget.itemsCount;
    final clampedIndex = widget.selectedIndex
        .clamp(0, widget.itemsCount - 1)
        .toInt();
    const selectorWidth = 64.0;
    const selectorHeight = 54.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      left: clampedIndex * itemWidth + (itemWidth - selectorWidth) / 2,
      top: (70 - selectorHeight) / 2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scaleX: _stretchAnimation.value,
            scaleY: 1.0 / _stretchAnimation.value.clamp(0.8, 1.2),
            child: Container(
              width: selectorWidth,
              height: selectorHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.secondary.withValues(
                      alpha: widget.isDark ? 0.25 : 0.4,
                    ),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    color: widget.isDark
                        ? AppTheme.secondary.withValues(alpha: 0.2)
                        : AppTheme.secondary.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppTheme.secondary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LiquidNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
