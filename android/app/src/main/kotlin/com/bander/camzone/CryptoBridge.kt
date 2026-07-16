package com.bander.camzone

object CryptoBridge {

    init {
        System.loadLibrary("native-lib")
    }

    // One-shot encryption (kept for photos / already-completed files).
    external fun encryptFileNative(
        inputPath: String,
        outputPath: String,
        publicKeyPath: String
    ): Boolean

    // --- Streaming / real-time encryption (used for video while recording) ---

    /** Starts a streaming AES-GCM+RSA session, writes the header, returns a handle (0 = failure). */
    external fun startStreamEncryptionNative(
        outputPath: String,
        publicKeyPath: String
    ): Long

    /** Feeds newly-available plaintext bytes into the running session. */
    external fun feedStreamEncryptionNative(
        handle: Long,
        data: ByteArray
    ): Boolean

    /** Finalizes the session: writes the GCM tag and closes the output file. */
    external fun finishStreamEncryptionNative(
        handle: Long
    ): Boolean

    /** Cleans up a session that was cancelled/aborted mid-recording. */
    external fun abortStreamEncryptionNative(
        handle: Long
    )

    /**
     * Structural integrity check for an already-encrypted file (photo or
     * video). This does NOT decrypt the content (the device only holds the
     * RSA public key, never the private key, so full cryptographic
     * verification of the GCM tag is intentionally impossible on-device).
     * It validates the "ENCv1" header, the wrapped-AES-key length field,
     * and that the file is large enough to actually contain an IV + a
     * trailing 16-byte GCM tag plus real ciphertext — which is exactly
     * what catches a truncated/corrupted file from an interrupted write.
     */
    external fun verifyEncryptedFileNative(
        path: String
    ): Boolean

    // --- Decryption (device now holds the RSA private key, imported by the
    // user via the Settings screen and stored in secure storage) ---

    /**
     * Decrypts a whole ENCv1 file (photo, or a small video) fully in memory
     * and returns the plaintext bytes directly - nothing is ever written
     * back to disk. Verifies the AES-GCM authentication tag; returns null
     * if the file is corrupted/tampered OR the wrong private key was used.
     */
    external fun decryptFileToBytesNative(
        inputPath: String,
        privateKeyPem: String
    ): ByteArray?
}