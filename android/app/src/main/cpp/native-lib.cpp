#include <jni.h>
#include <string>
#include <vector>
#include <fstream>
#include <android/log.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/err.h>
#include <openssl/rand.h>

#define LOG_TAG "CryptoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

void logOpenSSLError(const char *msg) {
    char err_buf[256];
    unsigned long err;

    LOGE("--- Error at: %s ---", msg);

    while ((err = ERR_get_error()) != 0) {
        ERR_error_string_n(err, err_buf, sizeof(err_buf));
        LOGE("OpenSSL Error: %s", err_buf);
    }
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_bander_camzone_CryptoBridge_encryptFileNative(
        JNIEnv *env,
        jobject thiz,
        jstring input_path,
        jstring output_path,
        jstring public_key_path) {

    const char *in_path = env->GetStringUTFChars(input_path, nullptr);
    const char *out_path = env->GetStringUTFChars(output_path, nullptr);
    const char *pub_path = env->GetStringUTFChars(public_key_path, nullptr);

    bool success = false;

    // تهيئة OpenSSL
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    // تعريف كل المتغيرات في البداية
    unsigned char aes_key[32];
    unsigned char iv[12];
    FILE* kf = nullptr;
    EVP_PKEY* pubKey = nullptr;
    EVP_PKEY_CTX* rsa_ctx = nullptr;
    EVP_CIPHER_CTX* gcm_ctx = nullptr;
    std::ifstream is;
    std::ofstream os;
    unsigned char enc_aes_key[512];
    size_t enc_aes_key_len = sizeof(enc_aes_key);

    // توليد AES key و IV
    if (!RAND_bytes(aes_key, sizeof(aes_key)) ||
        !RAND_bytes(iv, sizeof(iv))) {
        logOpenSSLError("Random generation failed");
        goto cleanup;
    }

    // قراءة المفتاح العام
    kf = fopen(pub_path, "rb");
    if (!kf) {
        LOGE("Public key file not found");
        goto cleanup;
    }

    pubKey = PEM_read_PUBKEY(kf, NULL, NULL, NULL);
    fclose(kf);
    kf = nullptr;

    if (!pubKey) {
        logOpenSSLError("Failed to read public key");
        goto cleanup;
    }

    // تشفير AES key بالمفتاح العام
    rsa_ctx = EVP_PKEY_CTX_new(pubKey, NULL);
    if (!rsa_ctx ||
        EVP_PKEY_encrypt_init(rsa_ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_encrypt(rsa_ctx, enc_aes_key, &enc_aes_key_len, aes_key, 32) <= 0) {

        logOpenSSLError("RSA encryption failed");
        goto cleanup;
    }

    // فتح الملفات
    is.open(in_path, std::ios::binary);
    os.open(out_path, std::ios::binary);

    if (!is.is_open() || !os.is_open()) {
        LOGE("File open error");
        goto cleanup;
    }

    // كتابة الهيدر
    os.write("ENCv1", 5);
    os.put((enc_aes_key_len >> 8) & 0xFF);
    os.put(enc_aes_key_len & 0xFF);
    os.write((char*)enc_aes_key, enc_aes_key_len);
    os.write((char*)iv, 12);

    // تشفير البيانات
    gcm_ctx = EVP_CIPHER_CTX_new();
    if (!gcm_ctx || EVP_EncryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv) != 1) {
        logOpenSSLError("AES init failed");
        goto cleanup;
    }

    unsigned char in_buf[16384];
    unsigned char out_buf[16384 + 16];
    int out_len;

    while (is.read((char*)in_buf, sizeof(in_buf)) || is.gcount() > 0) {
        if (!EVP_EncryptUpdate(gcm_ctx, out_buf, &out_len, in_buf, (int)is.gcount())) {
            logOpenSSLError("AES update failed");
            goto cleanup;
        }
        os.write((char*)out_buf, out_len);
    }

    if (!EVP_EncryptFinal_ex(gcm_ctx, out_buf, &out_len)) {
        logOpenSSLError("AES final failed");
        goto cleanup;
    }
    os.write((char*)out_buf, out_len);

    // كتابة الـ GCM tag
    unsigned char tag[16];
    EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
    os.write((char*)tag, 16);

    success = true;

    cleanup:
    if (gcm_ctx) EVP_CIPHER_CTX_free(gcm_ctx);
    if (rsa_ctx) EVP_PKEY_CTX_free(rsa_ctx);
    if (pubKey) EVP_PKEY_free(pubKey);
    if (kf) fclose(kf);
    if (is.is_open()) is.close();
    if (os.is_open()) os.close();

    env->ReleaseStringUTFChars(input_path, in_path);
    env->ReleaseStringUTFChars(output_path, out_path);
    env->ReleaseStringUTFChars(public_key_path, pub_path);

    return success;
}
// ============================================================================
// STREAMING / REAL-TIME ENCRYPTION API
// Add this block to your existing native-lib.cpp (below the existing
// encryptFileNative function). It keeps encryptFileNative as-is for
// one-shot use (photos, small files) and adds a handle-based streaming
// API for video, so encryption happens incrementally as bytes arrive
// instead of as one big pass at the end.
//
// Flow:
//   1) startStreamEncryptionNative(outputPath, publicKeyPath) -> handle
//      Generates AES key/IV, wraps AES key with RSA public key, writes
//      the header to outputPath, and keeps the AES-GCM context open.
//   2) feedStreamEncryptionNative(handle, data) -> called repeatedly with
//      newly-available plaintext bytes as the video is being recorded.
//   3) finishStreamEncryptionNative(handle) -> finalizes GCM, writes the
//      tag, closes the file, frees the context.
// ============================================================================

struct StreamEncCtx {
    EVP_CIPHER_CTX* gcm_ctx;
    std::ofstream* os;
};

extern "C"
JNIEXPORT jlong JNICALL
Java_com_bander_camzone_CryptoBridge_startStreamEncryptionNative(
        JNIEnv *env,
        jobject thiz,
        jstring output_path,
        jstring public_key_path) {

    const char *out_path = env->GetStringUTFChars(output_path, nullptr);
    const char *pub_path = env->GetStringUTFChars(public_key_path, nullptr);

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    unsigned char aes_key[32];
    unsigned char iv[12];
    FILE* kf = nullptr;
    EVP_PKEY* pubKey = nullptr;
    EVP_PKEY_CTX* rsa_ctx = nullptr;
    EVP_CIPHER_CTX* gcm_ctx = nullptr;
    std::ofstream* os = nullptr;
    unsigned char enc_aes_key[512];
    size_t enc_aes_key_len = sizeof(enc_aes_key);
    jlong result = 0;

    if (!RAND_bytes(aes_key, sizeof(aes_key)) ||
        !RAND_bytes(iv, sizeof(iv))) {
        logOpenSSLError("Random generation failed (stream)");
        goto cleanup;
    }

    kf = fopen(pub_path, "rb");
    if (!kf) {
        LOGE("Public key file not found (stream)");
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
        LOGE("Output file open error (stream)");
        goto cleanup;
    }

    // Same header format as encryptFileNative, so both output types are
    // interchangeable on the decrypt side.
    os->write("ENCv1", 5);
    os->put((enc_aes_key_len >> 8) & 0xFF);
    os->put(enc_aes_key_len & 0xFF);
    os->write((char*)enc_aes_key, enc_aes_key_len);
    os->write((char*)iv, 12);

    gcm_ctx = EVP_CIPHER_CTX_new();
    if (!gcm_ctx || EVP_EncryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv) != 1) {
        logOpenSSLError("AES init failed (stream)");
        goto cleanup;
    }

    {
        StreamEncCtx* ctx = new StreamEncCtx();
        ctx->gcm_ctx = gcm_ctx;
        ctx->os = os;
        result = reinterpret_cast<jlong>(ctx);
        // ownership transferred to ctx, don't free below
        gcm_ctx = nullptr;
        os = nullptr;
    }

    cleanup:
    if (rsa_ctx) EVP_PKEY_CTX_free(rsa_ctx);
    if (pubKey) EVP_PKEY_free(pubKey);
    if (kf) fclose(kf);
    if (gcm_ctx) EVP_CIPHER_CTX_free(gcm_ctx);
    if (os) { os->close(); delete os; }

    env->ReleaseStringUTFChars(output_path, out_path);
    env->ReleaseStringUTFChars(public_key_path, pub_path);

    return result;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_bander_camzone_CryptoBridge_feedStreamEncryptionNative(
        JNIEnv *env,
        jobject thiz,
        jlong handle,
        jbyteArray data) {

    if (handle == 0) return JNI_FALSE;
    StreamEncCtx* ctx = reinterpret_cast<StreamEncCtx*>(handle);

    jsize len = env->GetArrayLength(data);
    if (len <= 0) return JNI_TRUE;

    jbyte* buf = env->GetByteArrayElements(data, nullptr);
    if (!buf) return JNI_FALSE;

    bool ok = true;
    unsigned char out_buf[65536 + 16];
    jsize remaining = len;
    jsize offset = 0;

    while (remaining > 0) {
        int chunk = remaining > 65536 ? 65536 : (int)remaining;
        int out_len = 0;
        if (!EVP_EncryptUpdate(ctx->gcm_ctx, out_buf, &out_len,
                               (unsigned char*)(buf + offset), chunk)) {
            logOpenSSLError("Stream AES update failed");
            ok = false;
            break;
        }
        ctx->os->write((char*)out_buf, out_len);
        offset += chunk;
        remaining -= chunk;
    }

    env->ReleaseByteArrayElements(data, buf, JNI_ABORT);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_bander_camzone_CryptoBridge_finishStreamEncryptionNative(
        JNIEnv *env,
        jobject thiz,
        jlong handle) {

    if (handle == 0) return JNI_FALSE;
    StreamEncCtx* ctx = reinterpret_cast<StreamEncCtx*>(handle);

    bool ok = true;
    unsigned char out_buf[32];
    int out_len = 0;

    if (!EVP_EncryptFinal_ex(ctx->gcm_ctx, out_buf, &out_len)) {
        logOpenSSLError("Stream AES final failed");
        ok = false;
    } else {
        ctx->os->write((char*)out_buf, out_len);
        unsigned char tag[16];
        EVP_CIPHER_CTX_ctrl(ctx->gcm_ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
        ctx->os->write((char*)tag, 16);
    }

    ctx->os->flush();
    ctx->os->close();

    EVP_CIPHER_CTX_free(ctx->gcm_ctx);
    delete ctx->os;
    delete ctx;

    return ok ? JNI_TRUE : JNI_FALSE;
}

// Optional: call this if recording is cancelled/aborted so we don't leak
// the context and leave a half-written file on disk.
extern "C"
JNIEXPORT void JNICALL
Java_com_bander_camzone_CryptoBridge_abortStreamEncryptionNative(
        JNIEnv *env,
jobject thiz,
        jlong handle) {

if (handle == 0) return;
StreamEncCtx* ctx = reinterpret_cast<StreamEncCtx*>(handle);
if (ctx->gcm_ctx) EVP_CIPHER_CTX_free(ctx->gcm_ctx);
if (ctx->os) { ctx->os->close(); delete ctx->os; }
delete ctx;
}
// ============================================================================
// STRUCTURAL INTEGRITY CHECK (post-recording verification)
// Add this block to your existing native-lib.cpp (below everything else).
//
// IMPORTANT: This does NOT decrypt the file and does NOT validate the GCM
// authentication tag cryptographically. That would require the AES key,
// which is only recoverable with the RSA PRIVATE key - and the device
// intentionally only ever holds the PUBLIC key. Real tamper-proof
// verification of the tag has to happen wherever the private key lives
// (your backend), after upload.
//
// What this DOES catch, reliably, on-device: a file that got truncated or
// left half-written - e.g. the app was killed mid-recording, storage ran
// out mid-write, or the streaming encryptor's finish() never got to run.
// That's the realistic failure mode for the "flush encrypted video
// mid-stream" flow, and this check is what backs the automatic
// re-encrypt-from-cache retry on the Dart side.
// ============================================================================

#include <cstring>

extern "C"
JNIEXPORT jboolean JNICALL
        Java_com_bander_camzone_CryptoBridge_verifyEncryptedFileNative(
        JNIEnv *env,
        jobject thiz,
jstring path) {

const char *file_path = env->GetStringUTFChars(path, nullptr);
bool valid = false;

std::ifstream is(file_path, std::ios::binary);
if (!is.is_open()) {
LOGE("verify: cannot open file %s", file_path);
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

is.seekg(0, std::ios::end);
std::streamoff totalSize = is.tellg();
is.seekg(0, std::ios::beg);

// أقل حجم ممكن منطقيًا: هيدر "ENCv1" (5) + حقل طول المفتاح (2) + IV (12)
// + GCM tag في الآخر (16). أي ملف أصغر من كده يبقى ناقص أكيد.
const std::streamoff minPossibleSize = 5 + 2 + 12 + 16;
if (totalSize < minPossibleSize) {
LOGE("verify: file too small (%lld bytes)", (long long) totalSize);
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

char magic[5];
is.read(magic, 5);
if (is.gcount() != 5 || std::memcmp(magic, "ENCv1", 5) != 0) {
LOGE("verify: bad or missing ENCv1 header");
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

unsigned char lenBytes[2];
is.read((char*) lenBytes, 2);
if (is.gcount() != 2) {
LOGE("verify: truncated key-length field");
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}
int encKeyLen = (lenBytes[0] << 8) | lenBytes[1];

// طول مفتاح RSA المشفر (OAEP) لازم يكون منطقي - عادة 256 بايت لمفتاح
// 2048-bit أو 512 بايت لمفتاح 4096-bit. أي رقم برا النطاق ده معناه
// الهيدر نفسه تالف.
if (encKeyLen <= 0 || encKeyLen > 512) {
LOGE("verify: implausible encrypted-key length %d", encKeyLen);
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

const std::streamoff expectedMinWithKey = 5 + 2 + encKeyLen + 12 + 16;
if (totalSize < expectedMinWithKey) {
LOGE("verify: file smaller than header+IV+tag implies (need >= %lld, got %lld)",
     (long long) expectedMinWithKey, (long long) totalSize);
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

// فيه بيانات فيديو فعلية بعد الهيدر (مش بس هيدر + tag فاضي بلا محتوى)
std::streamoff cipherTextSize = totalSize - expectedMinWithKey;
if (cipherTextSize <= 0) {
LOGE("verify: no actual ciphertext payload found");
is.close();
env->ReleaseStringUTFChars(path, file_path);
return JNI_FALSE;
}

valid = true;

is.close();
env->ReleaseStringUTFChars(path, file_path);
return valid ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// DECRYPTION (device now holds the RSA private key)
//
// Full-file, in-memory decrypt. Used for photos (and could be used for a
// small already-fully-downloaded video). The private key is passed in as a
// PEM *string* (parsed from a memory BIO, never written to disk), read out
// of secure storage on the Dart/Kotlin side right before this call and
// zeroed out of native memory (OPENSSL_cleanse) right after use.
//
// The AES-GCM authentication tag IS verified here (unlike the on-device
// structural check in verifyEncryptedFileNative) - this function returns
// null if the tag doesn't match, which means either file corruption/
// tampering, or the wrong private key.
// ============================================================================

extern "C"
JNIEXPORT jbyteArray JNICALL
        Java_com_bander_camzone_CryptoBridge_decryptFileToBytesNative(
        JNIEnv *env,
        jobject thiz,
jstring input_path,
        jstring private_key_pem) {

const char *in_path = env->GetStringUTFChars(input_path, nullptr);
const char *priv_pem = env->GetStringUTFChars(private_key_pem, nullptr);

jbyteArray result = nullptr;

OpenSSL_add_all_algorithms();
ERR_load_crypto_strings();

// كل المتغيرات غير البسيطة معرّفة فوق قبل أي goto (زي باقي الكود).
BIO* keyBio = nullptr;
EVP_PKEY* privKey = nullptr;
EVP_PKEY_CTX* rsa_ctx = nullptr;
EVP_CIPHER_CTX* gcm_ctx = nullptr;
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
LOGE("decrypt: cannot open input file");
goto cleanup;
}

is.read((char*)header, 5);
if (is.gcount() != 5 || memcmp(header, "ENCv1", 5) != 0) {
LOGE("decrypt: bad or missing ENCv1 header");
goto cleanup;
}

is.read((char*)lenBytes, 2);
if (is.gcount() != 2) { LOGE("decrypt: truncated key-length field"); goto cleanup; }
encKeyLen = (lenBytes[0] << 8) | lenBytes[1];
if (encKeyLen <= 0 || encKeyLen > 512) {
LOGE("decrypt: implausible wrapped-key length %d", encKeyLen);
goto cleanup;
}

encAesKey.resize(encKeyLen);
is.read((char*)encAesKey.data(), encKeyLen);
if (is.gcount() != encKeyLen) { LOGE("decrypt: truncated wrapped key"); goto cleanup; }

is.read((char*)iv, 12);
if (is.gcount() != 12) { LOGE("decrypt: truncated iv"); goto cleanup; }

// قراءة المفتاح الخاص من الذاكرة (نص PEM) - مفيش أي كتابة على القرص أبدًا.
keyBio = BIO_new_mem_buf(priv_pem, -1);
if (!keyBio) { LOGE("decrypt: BIO alloc failed"); goto cleanup; }

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
LOGE("decrypt: unexpected unwrapped AES key length %zu", aes_key_len);
goto cleanup;
}

ciphertextStart = is.tellg();
is.seekg(0, std::ios::end);
cipherLen = (std::streamoff)is.tellg() - (std::streamoff)ciphertextStart - 16;
if (cipherLen < 0) { LOGE("decrypt: file smaller than header+tag implies"); goto cleanup; }
is.seekg(ciphertextStart);

ciphertext.resize(cipherLen);
if (cipherLen > 0) {
is.read((char*)ciphertext.data(), cipherLen);
if (is.gcount() != cipherLen) { LOGE("decrypt: truncated ciphertext"); goto cleanup; }
}

is.read((char*)tag, 16);
if (is.gcount() != 16) { LOGE("decrypt: truncated GCM tag"); goto cleanup; }

gcm_ctx = EVP_CIPHER_CTX_new();
if (!gcm_ctx || EVP_DecryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv) != 1) {
logOpenSSLError("decrypt: AES-GCM init failed");
goto cleanup;
}

plaintext.resize((size_t) cipherLen);
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

plaintext.resize((size_t) total_len);

result = env->NewByteArray((jsize) plaintext.size());
if (result) {
env->SetByteArrayRegion(result, 0, (jsize) plaintext.size(), (jbyte*) plaintext.data());
}

OPENSSL_cleanse(aes_key, sizeof(aes_key));

cleanup:
if (gcm_ctx) EVP_CIPHER_CTX_free(gcm_ctx);
if (rsa_ctx) EVP_PKEY_CTX_free(rsa_ctx);
if (privKey) EVP_PKEY_free(privKey);
if (keyBio) BIO_free(keyBio);
if (is.is_open()) is.close();

env->ReleaseStringUTFChars(input_path, in_path);
env->ReleaseStringUTFChars(private_key_pem, priv_pem);

return result;
}