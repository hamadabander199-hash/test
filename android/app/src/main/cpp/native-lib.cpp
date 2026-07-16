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

// ---------------------------------------------------------
// 1. دالة التشفير (Encryption)
// ---------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_bander_camzone_MainActivity_encryptFileNative(
        JNIEnv *env, jobject thiz, jstring input_path, jstring output_path, jstring public_key_path) {

    const char *in_path = env->GetStringUTFChars(input_path, nullptr);
    const char *out_path = env->GetStringUTFChars(output_path, nullptr);
    const char *pub_path = env->GetStringUTFChars(public_key_path, nullptr);

    bool success = false;
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    unsigned char aes_key[32];
    unsigned char iv[12];
    RAND_bytes(aes_key, 32);
    RAND_bytes(iv, 12);

    FILE* kf = fopen(pub_path, "rb");
    if (!kf) return false;
    EVP_PKEY* pubKey = PEM_read_PUBKEY(kf, NULL, NULL, NULL);
    fclose(kf);
    if (!pubKey) return false;

    // تشفير مفتاح AES
    unsigned char enc_aes_key[512];
    size_t enc_aes_key_len = 0;
    EVP_PKEY_CTX *rsa_ctx = EVP_PKEY_CTX_new(pubKey, NULL);

    if (EVP_PKEY_encrypt_init(rsa_ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_encrypt(rsa_ctx, enc_aes_key, &enc_aes_key_len, aes_key, 32) <= 0) {
        logOpenSSLError("RSA Encrypt Init/Exec Failed");
        return false;
    }

    std::ifstream is(in_path, std::ios::binary);
    std::ofstream os(out_path, std::ios::binary);

    os.write("ENCv1", 5);
    os.put((enc_aes_key_len >> 8) & 0xFF);
    os.put(enc_aes_key_len & 0xFF);
    os.write((char*)enc_aes_key, enc_aes_key_len);
    os.write((char*)iv, 12);

    EVP_CIPHER_CTX *gcm_ctx = EVP_CIPHER_CTX_new();
    EVP_EncryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv);

    unsigned char in_buf[16384];
    unsigned char out_buf[16384 + 16];
    int out_len;
    while (is.read((char*)in_buf, sizeof(in_buf)) || is.gcount() > 0) {
        EVP_EncryptUpdate(gcm_ctx, out_buf, &out_len, in_buf, (int)is.gcount());
        os.write((char*)out_buf, out_len);
    }
    EVP_EncryptFinal_ex(gcm_ctx, out_buf, &out_len);
    os.write((char*)out_buf, out_len);

    unsigned char tag[16];
    EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
    os.write((char*)tag, 16);

    success = true;
    EVP_CIPHER_CTX_free(gcm_ctx); EVP_PKEY_CTX_free(rsa_ctx); EVP_PKEY_free(pubKey);
    is.close(); os.close();
    env->ReleaseStringUTFChars(input_path, in_path);
    env->ReleaseStringUTFChars(output_path, out_path);
    env->ReleaseStringUTFChars(public_key_path, pub_path);
    return success;
}

// ---------------------------------------------------------
// 2. دالة فك التشفير (Decryption) - مُعدلة لضبط الـ Bad Length
// ---------------------------------------------------------
extern "C" JNIEXPORT jboolean JNICALL
Java_com_bander_camzone_MainActivity_decryptFileNative(
        JNIEnv *env, jobject thiz, jstring input_path, jstring output_path, jstring key_path) {

    const char *in_path = env->GetStringUTFChars(input_path, nullptr);
    const char *out_path = env->GetStringUTFChars(output_path, nullptr);
    const char *k_path = env->GetStringUTFChars(key_path, nullptr);

    bool success = false;
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    std::ifstream is(in_path, std::ios::binary);
    std::ofstream os(out_path, std::ios::binary);
    if (!is.is_open() || !os.is_open()) return false;

    char header[5];
    is.read(header, 5);
    if (std::string(header, 5) != "ENCv1") return false;

    unsigned char len_bytes[2];
    is.read((char*)len_bytes, 2);
    unsigned short enc_key_len = (len_bytes[0] << 8) | len_bytes[1];

    std::vector<unsigned char> enc_key(enc_key_len);
    is.read((char*)enc_key.data(), enc_key_len);
    unsigned char iv[12];
    is.read((char*)iv, 12);

    FILE* kf = fopen(k_path, "rb");
    if (!kf) return false;
    EVP_PKEY* privKey = PEM_read_PrivateKey(kf, NULL, NULL, NULL);
    fclose(kf);
    if (!privKey) return false;

    // فك تشفير مفتاح AES - هنا التعديل الحرج
    unsigned char aes_key[256];
    size_t aes_key_out_len = sizeof(aes_key);
    EVP_PKEY_CTX *rsa_ctx = EVP_PKEY_CTX_new(privKey, NULL);

    if (EVP_PKEY_decrypt_init(rsa_ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0) { // توحيد الـ SHA256
        logOpenSSLError("RSA Decrypt Init Params Failed");
        return false;
    }

    if (EVP_PKEY_decrypt(rsa_ctx, aes_key, &aes_key_out_len, enc_key.data(), enc_key_len) <= 0) {
        logOpenSSLError("RSA Decryption Failed (Possible Bad Length)");
        return false;
    }

    // فك تشفير البيانات AES-GCM
    auto current_pos = is.tellg();
    is.seekg(0, std::ios::end);
    long long ciphertext_len = (long long)is.tellg() - current_pos - 16;
    is.seekg(current_pos, std::ios::beg);

    EVP_CIPHER_CTX *gcm_ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, iv);

    unsigned char in_buf[16384];
    unsigned char out_buf[16384 + 16];
    int out_len;
    long long bytes_read = 0;
    while (bytes_read < ciphertext_len) {
        long long to_read = std::min((long long)sizeof(in_buf), ciphertext_len - bytes_read);
        is.read((char*)in_buf, to_read);
        EVP_DecryptUpdate(gcm_ctx, out_buf, &out_len, in_buf, (int)to_read);
        os.write((char*)out_buf, out_len);
        bytes_read += to_read;
    }

    unsigned char tag[16];
    is.read((char*)tag, 16);
    EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_SET_TAG, 16, tag);

    if (EVP_DecryptFinal_ex(gcm_ctx, out_buf, &out_len) > 0) {
        os.write((char*)out_buf, out_len);
        success = true;
    }

    EVP_CIPHER_CTX_free(gcm_ctx); EVP_PKEY_CTX_free(rsa_ctx); EVP_PKEY_free(privKey);
    is.close(); os.close();
    env->ReleaseStringUTFChars(input_path, in_path);
    env->ReleaseStringUTFChars(output_path, out_path);
    env->ReleaseStringUTFChars(key_path, k_path);
    return success;
}