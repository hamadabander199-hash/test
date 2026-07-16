import 'dart:ui';
import 'package:flutter/material.dart';

/// شريط تنقل سفلي بتأثير "Liquid Glass" لأندرويد (شفافية + blur + نقطة
/// متحركة بتتبع التاب المختار). مفيش هنا أي state دايم - بياخد الـ index
/// الحالي والأيقونات كـ parameters بس.
class LiquidNavBar extends StatelessWidget {
  final int currentIndex;
  final List<IconData> icons;
  final ValueChanged<int> onTap;

  const LiquidNavBar({
    super.key,
    required this.currentIndex,
    required this.icons,
    required this.onTap,
  });

  double _indicatorX(int index) {
    final n = icons.length;
    if (n <= 1) return 0;
    return (2 * index + 1) / n - 1;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 70,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 25,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.25),
                    Colors.white.withOpacity(0.08),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    alignment: Alignment(_indicatorX(currentIndex), 0),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.15),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      icons.length,
                      (index) => _NavItem(
                        icon: icons[index],
                        isSelected: currentIndex == index,
                        onTap: () => onTap(index),
                      ),
                    ),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 300),
            scale: isSelected ? 1.15 : 1.0,
            curve: Curves.easeOutBack,
            child: Icon(
              icon,
              size: 26,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.45),
            ),
          ),
        ),
      ),
    );
  }
}
