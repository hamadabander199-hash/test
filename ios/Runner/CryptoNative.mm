//
//  CryptoNative.mm
//  Runner
//
//  بورت مباشر لمنطق native-lib.cpp بتاع الأندرويد (نفس نداءات OpenSSL
//  EVP بالظبط)، بس بواجهة Objective-C++ بدل JNI. المحتوى الفعلي للملف
//  المشفر (header "ENCv1" + مفتاح AES مغلف بـ RSA-OAEP + IV + ciphertext
//  + GCM tag) نفسه تمامًا زي الأندرويد، فالملفات متبادلة بين المنصتين
//  من غير أي فرق.
//
//  محتاج مكتبة OpenSSL على iOS (مش موجودة افتراضيًا زي الأندرويد اللي
//  بيجيب libcrypto.a/libssl.a جاهزين). أسهل طريقة: ضيف الـ Pod
//  'OpenSSL-Universal' في الـ Podfile وشغّل `pod install` - شرحتها في
//  الرسالة.
//

#import "CryptoNative.h"

#include <fstream>
#include <cstring>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/err.h>
#include <openssl/rand.h>
#include <openssl/bio.h>
#include <openssl/crypto.h>
#include <vector>

static void logOpenSSLError(const char *msg) {
    char err_buf[256];
    unsigned long err;
    NSLog(@"--- CryptoNative error at: %s ---", msg);
    while ((err = ERR_get_error()) != 0) {
        ERR_error_string_n(err, err_buf, sizeof(err_buf));
        NSLog(@"OpenSSL Error: %s", err_buf);
    }
}

// نفس الـ struct المستخدم في الأندرويد بالظبط: بيحمل الـ GCM context
// المفتوح وملف الإخراج، وبيتحول لـ handle (int64_t) نمرره لـ Dart
// ونرجعه في كل نداء لاحق.
struct StreamEncCtx {
    EVP_CIPHER_CTX *gcm_ctx;
    std::ofstream *os;
};

@implementation CryptoNative

+ (int64_t)startStreamEncryptionWithOutputPath:(NSString *)outputPath
                                  publicKeyPath:(NSString *)publicKeyPath {

    const char *out_path = outputPath.UTF8String;
    const char *pub_path = publicKeyPath.UTF8String;

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    unsigned char aes_key[32];
    unsigned char iv[12];
    FILE *kf = nullptr;
    EVP_PKEY *pubKey = nullptr;
    EVP_PKEY_CTX *rsa_ctx = nullptr;
    EVP_CIPHER_CTX *gcm_ctx = nullptr;
    std::ofstream *os = nullptr;
    unsigned char enc_aes_key[512];
    size_t enc_aes_key_len = sizeof(enc_aes_key);
    int64_t result = 0;

    if (!RAND_bytes(aes_key, sizeof(aes_key)) ||
        !RAND_bytes(iv, sizeof(iv))) {
        logOpenSSLError("Random generation failed (stream)");
        goto cleanup;
    }

    kf = fopen(pub_path, "rb");
    if (!kf) {
        NSLog(@"CryptoNative: public key file not found (stream)");
        goto cleanup;
    }

    pubKey = PEM_read_PUBKEY(kf, NULL, NULL, NULL);
    fclose(kf);
    kf = nullptr;

    if (!pubKey) {
        logOpenSSLError("Failed to read public key (stream)");
        goto cleanup;
    }

    rsa_ctx = EVP_PKEY_CTX_new(pubKey, NULL);
    if (!rsa_ctx ||
        EVP_PKEY_encrypt_init(rsa_ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_encrypt(rsa_ctx, enc_aes_key, &enc_aes_key_len, aes_key, 32) <= 0) {

        logOpenSSLError("RSA encryption failed (stream)");
        goto cleanup;
    }

    os = new std::ofstream(out_path, std::ios::binary);
    if (!os->is_open()) {
        NSLog(@"CryptoNative: output file open error (stream)");
        goto cleanup;
    }

    // نفس صيغة الهيدر بالظبط اللي بيكتبها الأندرويد، عشان الملفين
    // يبقوا متبادلين (interchangeable) على جانب فك التشفير.
    os->write("ENCv1", 5);
    os->put((enc_aes_key_len >> 8) & 0xFF);
    os->put(enc_aes_key_len & 0xFF);
    os->write((char *)enc_aes_key, enc_aes_key_len);
    os->write((char *)iv, 12);

    gcm_ctx = EVP_CIPHER_CTX_new();
    if (!gcm_ctx || EVP_EncryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv) != 1) {
        logOpenSSLError("AES init failed (stream)");
        goto cleanup;
    }

    {
        StreamEncCtx *ctx = new StreamEncCtx();
        ctx->gcm_ctx = gcm_ctx;
        ctx->os = os;
        result = reinterpret_cast<int64_t>(ctx);
        // الملكية اتنقلت للـ ctx، مبنمسحهاش تحت
        gcm_ctx = nullptr;
        os = nullptr;
    }

cleanup:
    if (rsa_ctx) EVP_PKEY_CTX_free(rsa_ctx);
    if (pubKey) EVP_PKEY_free(pubKey);
    if (kf) fclose(kf);
    if (gcm_ctx) EVP_CIPHER_CTX_free(gcm_ctx);
    if (os) { os->close(); delete os; }

    return result;
}

+ (BOOL)feedStreamEncryptionWithHandle:(int64_t)handle data:(NSData *)data {
    if (handle == 0) return NO;
    StreamEncCtx *ctx = reinterpret_cast<StreamEncCtx *>(handle);

    NSUInteger len = data.length;
    if (len == 0) return YES;

    const unsigned char *buf = (const unsigned char *)data.bytes;

    BOOL ok = YES;
    unsigned char out_buf[65536 + 16];
    NSUInteger remaining = len;
    NSUInteger offset = 0;

    while (remaining > 0) {
        int chunk = (int)(remaining > 65536 ? 65536 : remaining);
        int out_len = 0;
        if (!EVP_EncryptUpdate(ctx->gcm_ctx, out_buf, &out_len, buf + offset, chunk)) {
            logOpenSSLError("Stream AES update failed");
            ok = NO;
            break;
        }
        ctx->os->write((char *)out_buf, out_len);
        offset += chunk;
        remaining -= chunk;
    }

    return ok;
}

+ (BOOL)finishStreamEncryptionWithHandle:(int64_t)handle {
    if (handle == 0) return NO;
    StreamEncCtx *ctx = reinterpret_cast<StreamEncCtx *>(handle);

    BOOL ok = YES;
    unsigned char out_buf[32];
    int out_len = 0;

    if (!EVP_EncryptFinal_ex(ctx->gcm_ctx, out_buf, &out_len)) {
        logOpenSSLError("Stream AES final failed");
        ok = NO;
    } else {
        ctx->os->write((char *)out_buf, out_len);
        unsigned char tag[16];
        EVP_CIPHER_CTX_ctrl(ctx->gcm_ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
        ctx->os->write((char *)tag, 16);
    }

    ctx->os->flush();
    ctx->os->close();

    EVP_CIPHER_CTX_free(ctx->gcm_ctx);
    delete ctx->os;
    delete ctx;

    return ok;
}

+ (void)abortStreamEncryptionWithHandle:(int64_t)handle {
    if (handle == 0) return;
    StreamEncCtx *ctx = reinterpret_cast<StreamEncCtx *>(handle);
    if (ctx->gcm_ctx) EVP_CIPHER_CTX_free(ctx->gcm_ctx);
    if (ctx->os) { ctx->os->close(); delete ctx->os; }
    delete ctx;
}

+ (BOOL)verifyEncryptedFileAtPath:(NSString *)path {
    const char *file_path = path.UTF8String;

    std::ifstream is(file_path, std::ios::binary);
    if (!is.is_open()) {
        NSLog(@"CryptoNative verify: cannot open file %s", file_path);
        return NO;
    }

    is.seekg(0, std::ios::end);
    std::streamoff totalSize = is.tellg();
    is.seekg(0, std::ios::beg);

    // أقل حجم ممكن منطقيًا: هيدر "ENCv1" (5) + حقل طول المفتاح (2) +
    // IV (12) + GCM tag في الآخر (16). أي ملف أصغر من كده يبقى ناقص أكيد.
    const std::streamoff minPossibleSize = 5 + 2 + 12 + 16;
    if (totalSize < minPossibleSize) {
        NSLog(@"CryptoNative verify: file too small (%lld bytes)", (long long)totalSize);
        is.close();
        return NO;
    }

    char magic[5];
    is.read(magic, 5);
    if (is.gcount() != 5 || std::memcmp(magic, "ENCv1", 5) != 0) {
        NSLog(@"CryptoNative verify: bad or missing ENCv1 header");
        is.close();
        return NO;
    }

    unsigned char lenBytes[2];
    is.read((char *)lenBytes, 2);
    if (is.gcount() != 2) {
        NSLog(@"CryptoNative verify: truncated key-length field");
        is.close();
        return NO;
    }
    int encKeyLen = (lenBytes[0] << 8) | lenBytes[1];

    // طول مفتاح RSA المشفر (OAEP) لازم يكون منطقي - عادة 256 بايت لمفتاح
    // 2048-bit أو 512 بايت لمفتاح 4096-bit. أي رقم برا النطاق ده معناه
    // الهيدر نفسه تالف.
    if (encKeyLen <= 0 || encKeyLen > 512) {
        NSLog(@"CryptoNative verify: implausible encrypted-key length %d", encKeyLen);
        is.close();
        return NO;
    }

    const std::streamoff expectedMinWithKey = 5 + 2 + encKeyLen + 12 + 16;
    if (totalSize < expectedMinWithKey) {
        NSLog(@"CryptoNative verify: file smaller than header+IV+tag implies (need >= %lld, got %lld)",
              (long long)expectedMinWithKey, (long long)totalSize);
        is.close();
        return NO;
    }

    // فيه بيانات فيديو فعلية بعد الهيدر (مش بس هيدر + tag فاضي بلا محتوى)
    std::streamoff cipherTextSize = totalSize - expectedMinWithKey;
    if (cipherTextSize <= 0) {
        NSLog(@"CryptoNative verify: no actual ciphertext payload found");
        is.close();
        return NO;
    }

    is.close();
    return YES;
}

// ============================================================================
// بورت مباشر لـ Java_com_bander_camzone_CryptoBridge_decryptFileToBytesNative
// (native-lib.cpp) - نفس المنطق بالظبط، بما فيه التحقق من GCM tag.
// ============================================================================
+ (nullable NSData *)decryptFileToBytesAtPath:(NSString *)inputPath
                                privateKeyPem:(NSString *)privateKeyPem {

    const char *in_path = inputPath.UTF8String;
    const char *priv_pem = privateKeyPem.UTF8String;

    NSData *result = nil;

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    BIO *keyBio = nullptr;
    EVP_PKEY *privKey = nullptr;
    EVP_PKEY_CTX *rsa_ctx = nullptr;
    EVP_CIPHER_CTX *gcm_ctx = nullptr;
    std::ifstream is;
    std::vector<unsigned char> encAesKey;
    std::vector<unsigned char> ciphertext;
    std::vector<unsigned char> plaintext;

    unsigned char header[5];
    unsigned char lenBytes[2];
    int encKeyLen = 0;
    unsigned char aes_key[32];
    size_t aes_key_len = sizeof(aes_key);
    unsigned char iv[12];
    unsigned char tag[16];
    std::streampos ciphertextStart;
    std::streamoff cipherLen = 0;
    int out_len = 0;
    int total_len = 0;

    is.open(in_path, std::ios::binary);
    if (!is.is_open()) {
        NSLog(@"CryptoNative decrypt: cannot open input file");
        goto cleanup;
    }

    is.read((char *)header, 5);
    if (is.gcount() != 5 || memcmp(header, "ENCv1", 5) != 0) {
        NSLog(@"CryptoNative decrypt: bad or missing ENCv1 header");
        goto cleanup;
    }

    is.read((char *)lenBytes, 2);
    if (is.gcount() != 2) { NSLog(@"CryptoNative decrypt: truncated key-length field"); goto cleanup; }
    encKeyLen = (lenBytes[0] << 8) | lenBytes[1];
    if (encKeyLen <= 0 || encKeyLen > 512) {
        NSLog(@"CryptoNative decrypt: implausible wrapped-key length %d", encKeyLen);
        goto cleanup;
    }

    encAesKey.resize(encKeyLen);
    is.read((char *)encAesKey.data(), encKeyLen);
    if (is.gcount() != encKeyLen) { NSLog(@"CryptoNative decrypt: truncated wrapped key"); goto cleanup; }

    is.read((char *)iv, 12);
    if (is.gcount() != 12) { NSLog(@"CryptoNative decrypt: truncated iv"); goto cleanup; }

    // قراءة المفتاح الخاص من الذاكرة (نص PEM) - مفيش أي كتابة على القرص أبدًا.
    keyBio = BIO_new_mem_buf(priv_pem, -1);
    if (!keyBio) { NSLog(@"CryptoNative decrypt: BIO alloc failed"); goto cleanup; }

    privKey = PEM_read_bio_PrivateKey(keyBio, NULL, NULL, NULL);
    if (!privKey) {
        logOpenSSLError("decrypt: failed to parse private key (wrong format or corrupted)");
        goto cleanup;
    }

    rsa_ctx = EVP_PKEY_CTX_new(privKey, NULL);
    if (!rsa_ctx ||
        EVP_PKEY_decrypt_init(rsa_ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_decrypt(rsa_ctx, aes_key, &aes_key_len, encAesKey.data(), encAesKey.size()) <= 0) {
        logOpenSSLError("decrypt: RSA unwrap failed (wrong private key for this file?)");
        goto cleanup;
    }

    if (aes_key_len != 32) {
        NSLog(@"CryptoNative decrypt: unexpected unwrapped AES key length %zu", aes_key_len);
        goto cleanup;
    }

    ciphertextStart = is.tellg();
    is.seekg(0, std::ios::end);
    cipherLen = (std::streamoff)is.tellg() - (std::streamoff)ciphertextStart - 16;
    if (cipherLen < 0) { NSLog(@"CryptoNative decrypt: file smaller than header+tag implies"); goto cleanup; }
    is.seekg(ciphertextStart);

    ciphertext.resize(cipherLen);
    if (cipherLen > 0) {
        is.read((char *)ciphertext.data(), cipherLen);
        if (is.gcount() != cipherLen) { NSLog(@"CryptoNative decrypt: truncated ciphertext"); goto cleanup; }
    }

    is.read((char *)tag, 16);
    if (is.gcount() != 16) { NSLog(@"CryptoNative decrypt: truncated GCM tag"); goto cleanup; }

    gcm_ctx = EVP_CIPHER_CTX_new();
    if (!gcm_ctx || EVP_DecryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv) != 1) {
        logOpenSSLError("decrypt: AES-GCM init failed");
        goto cleanup;
    }

    plaintext.resize((size_t)cipherLen);
    if (cipherLen > 0) {
        if (!EVP_DecryptUpdate(gcm_ctx, plaintext.data(), &out_len, ciphertext.data(), (int)cipherLen)) {
            logOpenSSLError("decrypt: AES update failed");
            goto cleanup;
        }
        total_len = out_len;
    }

    if (EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_SET_TAG, 16, tag) != 1) {
        logOpenSSLError("decrypt: failed to set expected GCM tag");
        goto cleanup;
    }

    {
        unsigned char final_buf[16];
        if (EVP_DecryptFinal_ex(gcm_ctx, final_buf, &out_len) <= 0) {
            logOpenSSLError("decrypt: GCM authentication failed (file corrupted, tampered, or wrong key)");
            goto cleanup;
        }
    }

    plaintext.resize((size_t)total_len);

    result = [NSData dataWithBytes:plaintext.data() length:plaintext.size()];

    OPENSSL_cleanse(aes_key, sizeof(aes_key));

cleanup:
    if (gcm_ctx) EVP_CIPHER_CTX_free(gcm_ctx);
    if (rsa_ctx) EVP_PKEY_CTX_free(rsa_ctx);
    if (privKey) EVP_PKEY_free(privKey);
    if (keyBio) BIO_free(keyBio);
    if (is.is_open()) is.close();

    return result;
}

@end
