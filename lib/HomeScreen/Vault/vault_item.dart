import 'dart:typed_data';

/// نوع المحتوى المخزّن في الخزنة.
enum VaultItemType { photo, video }

VaultItemType vaultItemTypeFromString(String value) {
  return value == 'video' ? VaultItemType.video : VaultItemType.photo;
}

String vaultItemTypeToString(VaultItemType type) {
  return type == VaultItemType.video ? 'video' : 'photo';
}

/// يمثل صف واحد في جدول `vault_items` جوه قاعدة بيانات SQLCipher.
///
/// ملحوظة أمان: `thumbnailBlob` هو الشكل الوحيد المسموح بيه للثامبنيل —
/// بيانات JPEG مصغّرة جوه الـ blob نفسه، ومفيش أي نسخة منها بتتكتب كملف
/// منفصل على التخزين أبدًا. الملف الأصلي (`originalFilePath`) هو ملف
/// الـ .enc المشفّر فقط، وده اللي بيتفك تشفيره وقت الفتح بس.
class VaultItem {
  final int? id;
  final String originalFilePath;
  final VaultItemType type;
  final DateTime dateCreated;

  /// مدة الفيديو بالثواني — null للصور.
  final int? durationSeconds;

  final Uint8List thumbnailBlob;

  const VaultItem({
    this.id,
    required this.originalFilePath,
    required this.type,
    required this.dateCreated,
    required this.thumbnailBlob,
    this.durationSeconds,
  });

  VaultItem copyWith({int? id}) {
    return VaultItem(
      id: id ?? this.id,
      originalFilePath: originalFilePath,
      type: type,
      dateCreated: dateCreated,
      thumbnailBlob: thumbnailBlob,
      durationSeconds: durationSeconds,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'original_file_path': originalFilePath,
      'type': vaultItemTypeToString(type),
      'date_created': dateCreated.millisecondsSinceEpoch,
      'duration': durationSeconds,
      'thumbnail_blob': thumbnailBlob,
    };
  }

  factory VaultItem.fromMap(Map<String, Object?> map) {
    return VaultItem(
      id: map['id'] as int?,
      originalFilePath: map['original_file_path'] as String,
      type: vaultItemTypeFromString(map['type'] as String),
      dateCreated:
          DateTime.fromMillisecondsSinceEpoch(map['date_created'] as int),
      durationSeconds: map['duration'] as int?,
      thumbnailBlob: map['thumbnail_blob'] as Uint8List,
    );
  }

  String get formattedDuration {
    final seconds = durationSeconds ?? 0;
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
