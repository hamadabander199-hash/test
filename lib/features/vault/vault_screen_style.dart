import 'package:flutter/material.dart';
import 'vault_item.dart';

/// خلية واحدة في شبكة الخزنة: ثامبنيل من الذاكرة (Image.memory)، مع
/// أيقونة تشغيل ومدة للفيديو. Widget عرض بحت - كل منطق تحميل/فتح
/// العنصر موجود في vault_screen.dart.
class VaultGridCell extends StatelessWidget {
  final VaultItem item;
  final VoidCallback onTap;

  const VaultGridCell({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              item.thumbnailBlob,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            if (item.type == VaultItemType.video) ...[
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 20,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.formattedDuration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
