import 'dart:typed_data';

/// نوع العنصر المخزّن في الخزنة.
enum VaultItemType { photo, video }

/// موديل عنصر واحد في الخزنة — بيمثّل صف واحد في قاعدة بيانات
/// [VaultDatabaseService] (SQLCipher). البيانات الحساسة (الصورة/الفيديو
/// الأصلي) مش متخزنة هنا كـ bytes؛ متخزنة مشفّرة على القرص، وإحنا بس
/// شايلين مسارها (`originalFilePath`) + ثامبنيل صغير (`thumbnailBlob`)
/// عشان نعرضه في الـ grid من غير ما نفك تشفير الملف الأصلي كل مرة.
class VaultItem {
  /// الـ primary key في قاعدة البيانات.
  final int id;

  /// نوع العنصر: صورة أو فيديو.
  final VaultItemType type;

  /// مسار الملف المشفّر (.enc) على القرص — ده اللي بيتفك تشفيره وقت
  /// العرض الفعلي (lazy decrypt)، مش بيتخزن أي نسخة مفكوكة بشكل دائم.
  final String originalFilePath;

  /// صورة مصغّرة (thumbnail) بايتس خام (JPEG) بنعرضها في الـ grid.
  /// دي بتتولد وقت الاستيراد وبتتخزن في قاعدة البيانات المشفّرة نفسها،
  /// عشان نتجنب فك تشفير الملف الأصلي كامل بس عشان نعرض ثامبنيل.
  final Uint8List thumbnailBlob;

  /// تاريخ إضافة العنصر للخزنة (مش بالضرورة تاريخ التقاط الصورة/الفيديو
  /// الأصلي، لكنه بيُستخدم للترتيب والتجميع في الشاشة).
  final DateTime dateCreated;

  /// مدة الفيديو بالميلي ثانية. 0 للصور.
  final int durationMs;

  const VaultItem({
    required this.id,
    required this.type,
    required this.originalFilePath,
    required this.thumbnailBlob,
    required this.dateCreated,
    this.durationMs = 0,
  });

  /// نص جاهز لعرض مدة الفيديو بصيغة mm:ss تحت الثامبنيل.
  String get formattedDuration {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// بناء عنصر من صف قاعدة بيانات (Map<String, Object?> اللي بيرجعه
  /// sqflite/sqlcipher).
  factory VaultItem.fromMap(Map<String, Object?> map) {
    return VaultItem(
      id: map['id'] as int,
      type: (map['type'] as String) == 'video'
          ? VaultItemType.video
          : VaultItemType.photo,
      originalFilePath: map['original_file_path'] as String,
      thumbnailBlob: map['thumbnail_blob'] as Uint8List,
      dateCreated: DateTime.fromMillisecondsSinceEpoch(
        map['date_created'] as int,
      ),
      durationMs: (map['duration_ms'] as int?) ?? 0,
    );
  }

  /// تحويل العنصر لصف جاهز للحفظ في قاعدة البيانات.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type == VaultItemType.video ? 'video' : 'photo',
      'original_file_path': originalFilePath,
      'thumbnail_blob': thumbnailBlob,
      'date_created': dateCreated.millisecondsSinceEpoch,
      'duration_ms': durationMs,
    };
  }
}
