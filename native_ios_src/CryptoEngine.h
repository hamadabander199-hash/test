// CryptoEngine.h
// نفس منطق native-lib.cpp (Android) بالظبط - RSA-OAEP + AES-256-GCM chunked (ENCv2)
// متوافق مع ملفات اتشفرت من نسخة Android والعكس.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CryptoEngine : NSObject

+ (BOOL)encryptFileAtPath:(NSString *)inputPath
                toPath:(NSString *)outputPath
        publicKeyPath:(NSString *)publicKeyPath
                 error:(NSString * _Nullable * _Nullable)errorOut;

+ (BOOL)decryptFileAtPath:(NSString *)inputPath
                toPath:(NSString *)outputPath
       privateKeyPath:(NSString *)privateKeyPath
                 error:(NSString * _Nullable * _Nullable)errorOut;

@end

NS_ASSUME_NONNULL_END
