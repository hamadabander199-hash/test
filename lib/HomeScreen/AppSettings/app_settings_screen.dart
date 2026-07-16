import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../Services/PrivateKeyStorageService.dart';
import '../../theme/app_theme.dart';

/// شاشة إعدادات التطبيق العامة (مختلفة عن SettingsScreen بتاعة إعدادات
/// الكاميرا الموجودة في Camscreen).
///
/// المسؤولية هنا: استيراد المفتاح الخاص (private key) اللي الكاميرا
/// بتشفّر بيه، وحفظه بأمان في iOS Keychain / Android Keystore عن طريق
/// PrivateKeyStorageService، عشان يُستخدم بعدين في فك تشفير الخزنة.
///
/// ⚠️ لسه ناقص: ربط المفتاح فعليًا بمنطق فك التشفير (NativeCryptoService /
/// StreamingVideoEncryptor)، والـ biometric gate على الشاشة دي. هيتضافوا
/// في خطوة لاحقة.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _isLoading = true;
  bool _isBusy = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _refreshKeyStatus();
  }

  Future<void> _refreshKeyStatus() async {
    final hasKey = await PrivateKeyStorageService.hasPrivateKey();
    if (!mounted) return;
    setState(() {
      _hasKey = hasKey;
      _isLoading = false;
    });
  }

  Future<void> _importPrivateKey() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'key'],
      );

      if (result == null || result.files.single.path == null) {
        // المستخدم لغى الاختيار.
        return;
      }

      final path = result.files.single.path!;
      final file = File(path);
      final content = await file.readAsString();

      if (!_looksLikePemKey(content)) {
        _showSnack(
          "الملف ده مش شكله مفتاح صالح (لازم يكون بصيغة PEM).",
          isError: true,
        );
        return;
      }

      setState(() => _isBusy = true);
      await PrivateKeyStorageService.savePrivateKey(content);
      if (!mounted) return;

      setState(() {
        _hasKey = true;
        _isBusy = false;
      });

      _showSnack("تم حفظ المفتاح الخاص بنجاح ✅");
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showSnack("حصل خطأ أثناء استيراد المفتاح: $e", isError: true);
    }
  }

  bool _looksLikePemKey(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith('-----BEGIN') && trimmed.contains('-----END');
  }

  Future<void> _confirmDeleteKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          "حذف المفتاح الخاص؟",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          "لو مسحت المفتاح مش هتقدر تفتح أو تفك تشفير أي محتوى في الخزنة "
              "غير لو استوردت المفتاح تاني.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "حذف",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isBusy = true);
    await PrivateKeyStorageService.deletePrivateKey();
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _isBusy = false;
    });
    _showSnack("تم حذف المفتاح الخاص.");
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.surfaceElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          "الإعدادات",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildKeyStatusCard(),
          const SizedBox(height: 16),
          if (_isBusy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            _buildActionButton(
              icon: Icons.upload_file_rounded,
              label: _hasKey ? "استبدال المفتاح الخاص" : "استيراد المفتاح الخاص",
              onTap: _importPrivateKey,
            ),
            if (_hasKey) ...[
              const SizedBox(height: 10),
              _buildActionButton(
                icon: Icons.delete_outline_rounded,
                label: "حذف المفتاح الخاص",
                color: Colors.redAccent,
                onTap: _confirmDeleteKey,
              ),
            ],
          ],
          const SizedBox(height: 24),
          const Text(
            "المفتاح الخاص بيتخزن بأمان جوه iCloud Keychain (iOS) أو "
                "Android Keystore (أندرويد)، ومش بيتعرض تاني على الشاشة "
                "بعد ما يتحفظ. بيُستخدم بس علشان تفتح وتفك تشفير محتوى "
                "الخزنة.",
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: _hasKey ? AppColors.success : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasKey ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            color: _hasKey ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasKey ? "المفتاح الخاص مُخزّن" : "لا يوجد مفتاح مسجل",
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _hasKey
                      ? "تقدر تفك تشفير محتوى الخزنة بيه."
                      : "استورد المفتاح عشان تقدر تفتح الخزنة.",
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.primary,
  }) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color == Colors.redAccent
                        ? Colors.redAccent
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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
    );
  }
}