// CryptoEngine.mm
// بورت مباشر لمنطق native-lib.cpp (Android JNI) - بدون أي تغيير في صيغة الملفات
// ENCv1 (قديم) و ENCv2 (المُقسّمة/Chunked) - نفس الـ MAGIC ونفس بناء الـ nonce
// فبيقدر يفك تشفير ملفات اتشفرت على Android والعكس صحيح.

#import "CryptoEngine.h"
#import <openssl/evp.h>
#import <openssl/pem.h>
#import <openssl/rsa.h>
#import <openssl/err.h>
#import <openssl/rand.h>

#include <fstream>
#include <vector>
#include <cstring>
#include <algorithm>

static const char MAGIC_V2[5] = {'E','N','C','v','2'};
static const char MAGIC_V1[5] = {'E','N','C','v','1'};
static const uint32_t DEFAULT_CHUNK_SIZE = 1 * 1024 * 1024; // 1MB
static const int TAG_LEN = 16;
static const int GCM_IV_LEN = 12;

static NSString *lastOpenSSLError() {
    unsigned long err;
    char err_buf[256];
    NSMutableString *msg = [NSMutableString string];
    while ((err = ERR_get_error()) != 0) {
        ERR_error_string_n(err, err_buf, sizeof(err_buf));
        [msg appendFormat:@"%s; ", err_buf];
    }
    return msg.length ? msg : @"Unknown OpenSSL error";
}

static void buildChunkNonce(const unsigned char *baseIv8, uint32_t chunkIndex, unsigned char *outIv12) {
    memcpy(outIv12, baseIv8, 8);
    outIv12[8]  = (unsigned char)((chunkIndex >> 24) & 0xFF);
    outIv12[9]  = (unsigned char)((chunkIndex >> 16) & 0xFF);
    outIv12[10] = (unsigned char)((chunkIndex >> 8) & 0xFF);
    outIv12[11] = (unsigned char)(chunkIndex & 0xFF);
}

@implementation CryptoEngine

#pragma mark - Encrypt (ENCv2 chunked)

+ (BOOL)encryptFileAtPath:(NSString *)inputPath
                    toPath:(NSString *)outputPath
             publicKeyPath:(NSString *)publicKeyPath
                     error:(NSString **)errorOut {

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    bool success = false;
    NSString *errMsg = nil;

    do {
        unsigned char aes_key[32];
        unsigned char base_iv[8];
        RAND_bytes(aes_key, 32);
        RAND_bytes(base_iv, 8);

        FILE *kf = fopen(publicKeyPath.UTF8String, "rb");
        if (!kf) { errMsg = @"Cannot open public key"; break; }
        EVP_PKEY *pubKey = PEM_read_PUBKEY(kf, NULL, NULL, NULL);
        fclose(kf);
        if (!pubKey) { errMsg = [@"Failed to parse public key: " stringByAppendingString:lastOpenSSLError()]; break; }

        unsigned char enc_aes_key[512];
        size_t enc_aes_key_len = 0;
        EVP_PKEY_CTX *rsa_ctx = EVP_PKEY_CTX_new(pubKey, NULL);

        if (EVP_PKEY_encrypt_init(rsa_ctx) <= 0 ||
            EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) <= 0 ||
            EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) <= 0 ||
            EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) <= 0 ||
            EVP_PKEY_encrypt(rsa_ctx, enc_aes_key, &enc_aes_key_len, aes_key, 32) <= 0) {
            errMsg = [@"RSA Encrypt Failed: " stringByAppendingString:lastOpenSSLError()];
            EVP_PKEY_CTX_free(rsa_ctx);
            EVP_PKEY_free(pubKey);
            break;
        }

        std::ifstream is(inputPath.UTF8String, std::ios::binary);
        std::ofstream os(outputPath.UTF8String, std::ios::binary);
        if (!is.is_open() || !os.is_open()) {
            errMsg = @"Cannot open input/output file";
            EVP_PKEY_CTX_free(rsa_ctx);
            EVP_PKEY_free(pubKey);
            break;
        }

        is.seekg(0, std::ios::end);
        uint64_t total_size = (uint64_t) is.tellg();
        is.seekg(0, std::ios::beg);

        uint32_t chunk_size = DEFAULT_CHUNK_SIZE;

        os.write(MAGIC_V2, 5);
        os.put((char)((enc_aes_key_len >> 8) & 0xFF));
        os.put((char)(enc_aes_key_len & 0xFF));
        os.write((char *)enc_aes_key, (long)enc_aes_key_len);
        os.write((char *)base_iv, 8);
        for (int i = 3; i >= 0; i--) os.put((char)((chunk_size >> (i * 8)) & 0xFF));
        for (int i = 7; i >= 0; i--) os.put((char)((total_size >> (i * 8)) & 0xFF));

        std::vector<unsigned char> plain_buf(chunk_size);
        std::vector<unsigned char> cipher_buf(chunk_size + 16);
        uint32_t chunk_index = 0;
        bool chunkFailed = false;

        while (is.read((char *)plain_buf.data(), chunk_size) || is.gcount() > 0) {
            int read_len = (int)is.gcount();

            unsigned char nonce[GCM_IV_LEN];
            buildChunkNonce(base_iv, chunk_index, nonce);

            EVP_CIPHER_CTX *gcm_ctx = EVP_CIPHER_CTX_new();
            EVP_EncryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, nonce);

            int out_len = 0, total_out = 0;
            if (EVP_EncryptUpdate(gcm_ctx, cipher_buf.data(), &out_len, plain_buf.data(), read_len) <= 0) {
                chunkFailed = true;
                EVP_CIPHER_CTX_free(gcm_ctx);
                break;
            }
            total_out += out_len;
            if (EVP_EncryptFinal_ex(gcm_ctx, cipher_buf.data() + total_out, &out_len) <= 0) {
                chunkFailed = true;
                EVP_CIPHER_CTX_free(gcm_ctx);
                break;
            }
            total_out += out_len;

            unsigned char tag[TAG_LEN];
            EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_GET_TAG, TAG_LEN, tag);
            EVP_CIPHER_CTX_free(gcm_ctx);

            os.write((char *)cipher_buf.data(), total_out);
            os.write((char *)tag, TAG_LEN);

            chunk_index++;
        }

        EVP_PKEY_CTX_free(rsa_ctx);
        EVP_PKEY_free(pubKey);
        is.close();
        os.close();

        if (chunkFailed) errMsg = @"AES-GCM chunk encryption failed";
        success = !chunkFailed;
    } while (false);

    if (errorOut) *errorOut = errMsg;
    return success ? YES : NO;
}

#pragma mark - Decrypt (supports ENCv1 legacy + ENCv2 chunked)

static bool decryptV1Full(std::ifstream &is, std::ofstream &os, const char *k_path, NSString **errMsg) {
    unsigned char len_bytes[2];
    is.read((char *)len_bytes, 2);
    unsigned short enc_key_len = (len_bytes[0] << 8) | len_bytes[1];

    std::vector<unsigned char> enc_key(enc_key_len);
    is.read((char *)enc_key.data(), enc_key_len);
    unsigned char iv[12];
    is.read((char *)iv, 12);

    FILE *kf = fopen(k_path, "rb");
    if (!kf) { *errMsg = @"Cannot open private key"; return false; }
    EVP_PKEY *privKey = PEM_read_PrivateKey(kf, NULL, NULL, NULL);
    fclose(kf);
    if (!privKey) { *errMsg = @"Failed to parse private key"; return false; }

    unsigned char aes_key[256];
    size_t aes_key_out_len = sizeof(aes_key);
    EVP_PKEY_CTX *rsa_ctx = EVP_PKEY_CTX_new(privKey, NULL);

    bool ok = false;
    if (EVP_PKEY_decrypt_init(rsa_ctx) > 0 &&
        EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) > 0 &&
        EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) > 0 &&
        EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) > 0 &&
        EVP_PKEY_decrypt(rsa_ctx, aes_key, &aes_key_out_len, enc_key.data(), enc_key_len) > 0) {

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
            is.read((char *)in_buf, to_read);
            EVP_DecryptUpdate(gcm_ctx, out_buf, &out_len, in_buf, (int)to_read);
            os.write((char *)out_buf, out_len);
            bytes_read += to_read;
        }

        unsigned char tag[16];
        is.read((char *)tag, 16);
        EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_SET_TAG, 16, tag);
        ok = EVP_DecryptFinal_ex(gcm_ctx, out_buf, &out_len) > 0;
        if (ok) os.write((char *)out_buf, out_len);
        else *errMsg = @"AES-GCM tag verification failed (ENCv1)";
        EVP_CIPHER_CTX_free(gcm_ctx);
    } else {
        *errMsg = @"RSA decryption failed (ENCv1)";
    }

    EVP_PKEY_CTX_free(rsa_ctx);
    EVP_PKEY_free(privKey);
    return ok;
}

+ (BOOL)decryptFileAtPath:(NSString *)inputPath
                    toPath:(NSString *)outputPath
            privateKeyPath:(NSString *)privateKeyPath
                     error:(NSString **)errorOut {

    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();

    bool success = false;
    NSString *errMsg = nil;

    std::ifstream is(inputPath.UTF8String, std::ios::binary);
    std::ofstream os(outputPath.UTF8String, std::ios::binary);

    if (is.is_open() && os.is_open()) {
        char header[5];
        is.read(header, 5);

        if (memcmp(header, MAGIC_V1, 5) == 0) {
            success = decryptV1Full(is, os, privateKeyPath.UTF8String, &errMsg);

        } else if (memcmp(header, MAGIC_V2, 5) == 0) {
            unsigned char len_bytes[2];
            is.read((char *)len_bytes, 2);
            unsigned short enc_key_len = (len_bytes[0] << 8) | len_bytes[1];
            std::vector<unsigned char> enc_key(enc_key_len);
            is.read((char *)enc_key.data(), enc_key_len);
            unsigned char base_iv[8];
            is.read((char *)base_iv, 8);
            unsigned char cs_bytes[4];
            is.read((char *)cs_bytes, 4);
            uint32_t chunk_size = ((uint32_t)cs_bytes[0] << 24) | ((uint32_t)cs_bytes[1] << 16) |
                                   ((uint32_t)cs_bytes[2] << 8) | cs_bytes[3];
            unsigned char ts_bytes[8];
            is.read((char *)ts_bytes, 8);
            uint64_t total_size = 0;
            for (int i = 0; i < 8; i++) total_size = (total_size << 8) | ts_bytes[i];

            FILE *kf = fopen(privateKeyPath.UTF8String, "rb");
            EVP_PKEY *privKey = kf ? PEM_read_PrivateKey(kf, NULL, NULL, NULL) : nullptr;
            if (kf) fclose(kf);

            if (!privKey) {
                errMsg = @"Cannot open/parse private key";
            } else {
                unsigned char aes_key[256];
                size_t aes_key_out_len = sizeof(aes_key);
                EVP_PKEY_CTX *rsa_ctx = EVP_PKEY_CTX_new(privKey, NULL);
                if (EVP_PKEY_decrypt_init(rsa_ctx) > 0 &&
                    EVP_PKEY_CTX_set_rsa_padding(rsa_ctx, RSA_PKCS1_OAEP_PADDING) > 0 &&
                    EVP_PKEY_CTX_set_rsa_oaep_md(rsa_ctx, EVP_sha256()) > 0 &&
                    EVP_PKEY_CTX_set_rsa_mgf1_md(rsa_ctx, EVP_sha256()) > 0 &&
                    EVP_PKEY_decrypt(rsa_ctx, aes_key, &aes_key_out_len, enc_key.data(), enc_key_len) > 0) {

                    std::vector<unsigned char> cipher_buf(chunk_size);
                    std::vector<unsigned char> plain_buf(chunk_size);
                    uint64_t remaining = total_size;
                    uint32_t chunk_index = 0;
                    bool ok = true;
                    while (remaining > 0 && ok) {
                        uint32_t this_chunk = (uint32_t)std::min((uint64_t)chunk_size, remaining);
                        is.read((char *)cipher_buf.data(), this_chunk);
                        unsigned char tag[TAG_LEN];
                        is.read((char *)tag, TAG_LEN);

                        unsigned char nonce[GCM_IV_LEN];
                        buildChunkNonce(base_iv, chunk_index, nonce);

                        EVP_CIPHER_CTX *gcm_ctx = EVP_CIPHER_CTX_new();
                        EVP_DecryptInit_ex(gcm_ctx, EVP_aes_256_gcm(), NULL, aes_key, nonce);
                        int out_len = 0, total_out = 0;
                        EVP_DecryptUpdate(gcm_ctx, plain_buf.data(), &out_len, cipher_buf.data(), (int)this_chunk);
                        total_out += out_len;
                        EVP_CIPHER_CTX_ctrl(gcm_ctx, EVP_CTRL_GCM_SET_TAG, TAG_LEN, tag);
                        if (EVP_DecryptFinal_ex(gcm_ctx, plain_buf.data() + total_out, &out_len) <= 0) {
                            ok = false;
                        } else {
                            total_out += out_len;
                            os.write((char *)plain_buf.data(), total_out);
                        }
                        EVP_CIPHER_CTX_free(gcm_ctx);

                        remaining -= this_chunk;
                        chunk_index++;
                    }
                    success = ok;
                    if (!ok) errMsg = @"AES-GCM chunk verification failed (ENCv2)";
                } else {
                    errMsg = [@"RSA decryption failed (ENCv2): " stringByAppendingString:lastOpenSSLError()];
                }
                EVP_PKEY_CTX_free(rsa_ctx);
                EVP_PKEY_free(privKey);
            }
        } else {
            errMsg = @"Unknown file format header";
        }
    } else {
        errMsg = @"Cannot open input/output file";
    }

    is.close();
    os.close();

    if (errorOut) *errorOut = errMsg;
    return success ? YES : NO;
}

@end
