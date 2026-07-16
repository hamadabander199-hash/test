import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../Filemange/file_manager_screen.dart';
import 'mangecodecamera.dart';

/// شاشة إعدادات كاملة (مش bottom sheet) فيها تابين: "الجودة" و"عن التطبيق
/// وحقوق الملكية"، بالإضافة لزرار بيودّي مباشرة لشاشة الملفات المشفرة
/// عشان المستخدم يقدر يشاركها بسهولة.
class SettingsScreen extends StatefulWidget {
  final CameraControllerManager cameraManager;

  const SettingsScreen({super.key, required this.cameraManager});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static const _presets = [
    (ResolutionPreset.low, "منخفضة", "أصغر حجم، مناسبة لتوفير المساحة"),
    (ResolutionPreset.medium, "متوسطة", "توازن بين الحجم والجودة"),
    (ResolutionPreset.high, "عالية (HD)", "جودة واضحة للاستخدام اليومي"),
    (ResolutionPreset.veryHigh, "عالية جدًا", "تفاصيل أدق، حجم أكبر"),
    (ResolutionPreset.ultraHigh, "فائقة (4K)", "أعلى تفاصيل ممكنة"),
    (ResolutionPreset.max, "أقصى جودة", "أفضل جودة يدعمها جهازك"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الإعدادات"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: "الجودة"),
            Tab(text: "عن التطبيق"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQualityTab(),
          _buildAboutTab(context),
        ],
      ),
    );
  }

  Widget _buildQualityTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _presets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final (preset, title, subtitle) = _presets[index];
        final isSelected = widget.cameraManager.currentPreset == preset;
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () async {
              await widget.cameraManager.setCameraQuality(preset);
              if (mounted) setState(() {});
            },
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color:
                    isSelected ? AppColors.success : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAboutTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بوابة مباشرة لشاشة الملفات المشفرة، عشان تكون قريبة من الإعدادات
        // زي ما طلب - المستخدم يقدر يشارك أي ملف اتصور وتشفر من هنا.
        Material(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              Navigator.of(context).push(
                // ملحوظة: FileManagerScreen مالهاش const constructor،
                // فمينفعش نحط const هنا.
                MaterialPageRoute(builder: (_) => FileManagerScreen()),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.folder_special_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "الملفات المشفرة",
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "عن التطبيق",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Camzone يصوّر الفيديو والصور ويشفرها محليًا على جهازك أولًا "
              "بأول (streaming encryption) قبل رفعها، بحيث محدش يقدر يوصل "
              "للمحتوى الأصلي غير الطرف اللي معاه المفتاح الخاص.",
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "حقوق الملكية",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "© Camzone. جميع الحقوق محفوظة. كل المحتوى اللي بيتصور وبيتشفر عن "
              "طريق التطبيق ملك للمستخدم نفسه، والتطبيق مسؤول فقط عن تأمينه "
              "بالتشفير أثناء الحفظ والنقل.",
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}