//
//  CryptoNative.h
//  Runner
//
//  الند بتاع Android: CryptoBridge.kt + native-lib.cpp.
//  ده الـ interface بتاع الـ streaming AES-256-GCM + فحص السلامة الهيكلي
//  للفيديو، مبني بنفس منطق الـ OpenSSL المستخدم في الأندرويد بالظبط
//  عشان صيغة الملف الناتج ("ENCv1" header) تكون متطابقة ١٠٠٪ بين المنصتين.
//
//  ملاحظة: التشفير العادي (one-shot, للصور) لسه موجود في AppDelegate.swift
//  باستخدام CryptoKit + Security framework، ومحتاجش يتغيّر لأنه شغال
//  ومطابق لنفس الـ header format. الملف ده بيضيف بس الجزء الناقص:
//  التشفير التدريجي (streaming) اللي بيتغذى وهو التسجيل شغال.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CryptoNative : NSObject

/// بيبدأ جلسة تشفير AES-256-GCM تدريجية: بيولّد AES key + IV، بيغلّفهم
/// بالمفتاح العام RSA، بيكتب الـ header في outputPath، ويرجع "handle"
/// (المؤشر للـ context) لاستخدامه في باقي النداءات. 0 = فشل.
+ (int64_t)startStreamEncryptionWithOutputPath:(NSString *)outputPath
                                  publicKeyPath:(NSString *)publicKeyPath;

/// بيغذي بايتات جديدة (اللي اتكتبت في الفيديو الأصلي) للجلسة الشغالة.
/// بترجع NO لو فيه خطأ في التشفير.
+ (BOOL)feedStreamEncryptionWithHandle:(int64_t)handle data:(NSData *)data;

/// بينهي الجلسة: بيكتب الـ GCM tag النهائي ويقفل الملف. بترجع YES لو
/// اتنهت بنجاح.
+ (BOOL)finishStreamEncryptionWithHandle:(int64_t)handle;

/// بيلغي جلسة لسه شغالة (لو التسجيل اتقفل فجأة) وبيسيب أي موارد اتحجزت.
+ (void)abortStreamEncryptionWithHandle:(int64_t)handle;

/// فحص هيكلي (مش تشفيري) لملف مشفر خلص: بيتأكد من الـ "ENCv1" header
/// وطول المفتاح المغلف وإن حجم الملف منطقي بما يكفي لاحتواء IV + tag +
/// محتوى حقيقي. نفس منطق verifyEncryptedFileNative بتاع الأندرويد
/// بالظبط - مش بيفك التشفير لأن الجهاز مالوش المفتاح الخاص.
+ (BOOL)verifyEncryptedFileAtPath:(NSString *)path;

/// بيفك تشفير ملف ENCv1 كامل (صورة أو فيديو صغير) في الذاكرة بالكامل
/// ويرجع الـ plaintext bytes مباشرة - من غير ما يكتب أي حاجة على القرص.
/// بيتحقق من الـ GCM authentication tag؛ بيرجع nil لو الملف تالف/متلاعب
/// فيه أو المفتاح الخاص غلط. نفس منطق decryptFileToBytesNative بتاع
/// الأندرويد بالظبط.
+ (nullable NSData *)decryptFileToBytesAtPath:(NSString *)inputPath
                                privateKeyPem:(NSString *)privateKeyPem;

@end

NS_ASSUME_NONNULL_END
