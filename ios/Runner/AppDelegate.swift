import UIKit
import Flutter
import CryptoKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let cryptoChannel = FlutterMethodChannel(name: "my_crypto_native",
        binaryMessenger: controller.binaryMessenger)

      cryptoChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }

        switch call.method {
        case "encryptFile":
          if let args = call.arguments as? [String: Any],
          let input = args["inputPath"] as? String,
          let output = args["outputPath"] as? String,
          let pubKey = args["publicKeyPath"] as? String {
            do {
              try self.encryptFile(inputPath: input, outputPath: output, publicKeyPath: pubKey)
              result(true)
            } catch {
              result(false)
            }
          } else {
            result(false)
          }

        case "decryptFile":
          if let args = call.arguments as? [String: Any],
          let input = args["inputPath"] as? String,
          let output = args["outputPath"] as? String,
          let privKey = args["privateKeyPath"] as? String {
            do {
              try self.decryptFile(inputPath: input, outputPath: output, privateKeyPath: privKey)
              result(true)
            } catch {
              result(false)
            }
          } else {
            result(false)
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Encrypt File (whole file at once)
  func encryptFile(inputPath: String, outputPath: String, publicKeyPath: String) throws {
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: inputPath) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Input file not found"])
    }
    guard fileManager.fileExists(atPath: publicKeyPath) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Public key file not found"])
    }

    let inputFile = URL(fileURLWithPath: inputPath)
    let outputFile = URL(fileURLWithPath: outputPath)
    let pubKeyData = try Data(contentsOf: URL(fileURLWithPath: publicKeyPath))
    let pubKey = try loadPublicKey(fromPEM: pubKeyData)

    let fileData = try Data(contentsOf: inputFile)
    let aesKey = SymmetricKey(size: .bits256)
    let iv = AES.GCM.Nonce()

    // Encrypt AES key with RSA
    let aesKeyData = aesKey.withUnsafeBytes { Data($0) }
    var error: Unmanaged<CFError>?
    guard let encAESKey = SecKeyCreateEncryptedData(pubKey, .rsaEncryptionOAEPSHA256, aesKeyData as CFData, &error) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: error?.takeRetainedValue().localizedDescription ?? "RSA encryption failed"])
    }

    let keyBytes = encAESKey as Data
    let keyLen = UInt16(keyBytes.count)
    let keyLenData = Data([UInt8(keyLen >> 8), UInt8(keyLen & 0xFF)])

    // AES-GCM encryption
    let sealedBox = try AES.GCM.seal(fileData, using: aesKey, nonce: iv)

    // Write to output file
    guard let writer = OutputStream(url: outputFile, append: false) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot open output stream"])
    }
    writer.open()
    defer { writer.close() }

    func writeChunk(_ bytes: [UInt8]) throws {
      var offset = 0
      while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBufferPointer { ptr -> Int in
          writer.write(ptr.baseAddress!, maxLength: bytes.count - offset)
        }
        if written <= 0 {
          throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Write failed: \(writer.streamError?.localizedDescription ?? "unknown")"])
        }
        offset += written
      }
    }

    // Header
    try writeChunk([UInt8]("ENCv1".utf8))
    // AES key length
    try writeChunk([UInt8](keyLenData))
    // Encrypted AES key
    try writeChunk([UInt8](keyBytes))
    // IV
    let ivData = iv.withUnsafeBytes { Data($0) }
    try writeChunk([UInt8](ivData))
    // Ciphertext
    try writeChunk([UInt8](sealedBox.ciphertext))
    // Tag
    try writeChunk([UInt8](sealedBox.tag))
  }

  // MARK: - Decrypt File
  func decryptFile(inputPath: String, outputPath: String, privateKeyPath: String) throws {
    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: inputPath) else {
      throw NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encrypted file not found"])
    }
    guard fileManager.fileExists(atPath: privateKeyPath) else {
      throw NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Private key file not found"])
    }

    let inputFile = URL(fileURLWithPath: inputPath)
    let privKeyData = try Data(contentsOf: URL(fileURLWithPath: privateKeyPath))
    let privKey = try loadPrivateKey(fromPEM: privKeyData)

    let fileData = try Data(contentsOf: inputFile)
    guard fileData.count >= 5 + 2 + 12 + 16 else {
      throw NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "File too small / corrupted"])
    }
    var cursor = 0

    // 1️⃣ Header
    let header = String(data: fileData[cursor..<cursor+5], encoding: .utf8)!
    guard header == "ENCv1" else { throw NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid file header"]) }
    cursor += 5

    // 2️⃣ Encrypted AES key length
    let encKeyLen = UInt16(fileData[cursor]) << 8 | UInt16(fileData[cursor+1])
    cursor += 2

    // 3️⃣ Encrypted AES key
    let encAESKeyData = fileData[cursor..<cursor+Int(encKeyLen)]
    cursor += Int(encKeyLen)

    // 4️⃣ IV
    let ivData = fileData[cursor..<cursor+12]
    cursor += 12
    let iv = try AES.GCM.Nonce(data: ivData)

    // 5️⃣ Decrypt AES key
    var error: Unmanaged<CFError>?
    guard let aesKeyData = SecKeyCreateDecryptedData(privKey, .rsaEncryptionOAEPSHA256, encAESKeyData as CFData, &error) as Data? else {
      throw NSError(domain: "DecryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: error?.takeRetainedValue().localizedDescription ?? "RSA decryption failed"])
    }
    let aesKey = SymmetricKey(data: aesKeyData)

    // 6️⃣ Ciphertext + Tag
    let ciphertext = fileData[cursor..<fileData.count-16]
    let tag = fileData[fileData.count-16..<fileData.count]
    let sealedBox = try AES.GCM.SealedBox(nonce: iv, ciphertext: ciphertext, tag: tag)

    // Decrypt
    let decrypted = try AES.GCM.open(sealedBox, using: aesKey)
    try decrypted.write(to: URL(fileURLWithPath: outputPath))
  }

  // MARK: - Load Keys

  func loadPublicKey(fromPEM pemData: Data) throws -> SecKey {
    guard let pemString = String(data: pemData, encoding: .utf8) else {
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PEM data"])
    }

    let base64String = pemString
    .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
    .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
    .replacingOccurrences(of: "\n", with: "")
    .replacingOccurrences(of: "\r", with: "")
    .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let derData = Data(base64Encoded: base64String) else {
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot decode base64"])
    }

    // مش بنحدد kSecAttrKeySizeInBits — بنسيب iOS يستنتجها من البيانات
    // نفسها بدل ما نخمّن 2048 وممكن يكون المفتاح 3072/4096.
    let options: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPublic
    ]
    var createError: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(derData as CFData, options as CFDictionary, &createError) else {
      let msg = createError?.takeRetainedValue().localizedDescription ?? "Cannot load public key"
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
    return secKey
  }

  // MARK: - كشف وفك غلاف PKCS#8 (لو موجود) للوصول لمفتاح RSA الخام (PKCS#1)
  //
  // PKCS#1 (RSA PRIVATE KEY):  SEQUENCE { version INTEGER, n INTEGER, e INTEGER, ... }
  // PKCS#8 (PRIVATE KEY):      SEQUENCE { version INTEGER, AlgorithmIdentifier SEQUENCE, OCTET STRING { <PKCS#1 هنا> } }
  //
  // الفرق: بعد الـ version INTEGER، لو جه SEQUENCE تانية معناها PKCS#8،
  // ولو جه INTEGER تانية (وهو الـ modulus) معناها PKCS#1 أصلاً.
  private func stripPKCS8WrapperIfNeeded(_ der: Data) -> Data {

    func readLength(_ data: Data, _ index: inout Int) -> Int? {
      guard index < data.count else { return nil }
      let first = data[index]
      index += 1
      if first & 0x80 == 0 {
        return Int(first)
      }
      let numBytes = Int(first & 0x7F)
      guard numBytes > 0, numBytes <= 4, index + numBytes <= data.count else { return nil }
      var length = 0
      for _ in 0..<numBytes {
        length = (length << 8) | Int(data[index])
        index += 1
      }
      return length
    }

    var index = 0
    // لازم يبدأ بـ SEQUENCE (0x30)
    guard der.count > 4, der[index] == 0x30 else { return der }
    index += 1
    guard readLength(der, &index) != nil else { return der }

    // الـ version INTEGER
    guard index < der.count, der[index] == 0x02 else { return der }
    index += 1
    guard let versionLen = readLength(der, &index), index + versionLen <= der.count else { return der }
    index += versionLen

    guard index < der.count else { return der }
    let nextTag = der[index]

    if nextTag == 0x02 {
      // ده PKCS#1 أصلاً (modulus INTEGER مباشرة) — ملوش داعي لأي فك
      return der
    }

    if nextTag == 0x30 {
      // ده PKCS#8 — نتخطى الـ AlgorithmIdentifier SEQUENCE بالكامل
      index += 1
      guard let algLen = readLength(der, &index), index + algLen <= der.count else { return der }
      index += algLen

      // اللي بعده لازم يكون OCTET STRING (0x04) وجواه الـ PKCS#1 الحقيقي
      guard index < der.count, der[index] == 0x04 else { return der }
      index += 1
      guard let octetLen = readLength(der, &index), index + octetLen <= der.count else { return der }

      return der.subdata(in: index..<(index + octetLen))
    }

    // شكل غير متوقع — رجّع البيانات زي ما هي وسيب SecKeyCreateWithData يحاول
    // (وممكن يفشل بـ error واضح بدل ما نفترض حاجة غلط)
    return der
  }

  func loadPrivateKey(fromPEM pemData: Data) throws -> SecKey {
    guard var pemString = String(data: pemData, encoding: .utf8) else {
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PEM data"])
    }

    let headers = ["-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----",
                   "-----BEGIN RSA PRIVATE KEY-----", "-----END RSA PRIVATE KEY-----"]
    for header in headers { pemString = pemString.replacingOccurrences(of: header, with: "") }
    pemString = pemString.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

    guard let keyData = Data(base64Encoded: pemString) else {
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot decode base64"])
    }

    // 🔑 الإصلاح الأساسي: بنكتشف ونفك غلاف PKCS#8 تلقائيًا لو المفتاح
    // مكتوب بصيغة "-----BEGIN PRIVATE KEY-----" (بدل ما نفترض PKCS#1 دايمًا).
    let pkcs1Data = stripPKCS8WrapperIfNeeded(keyData)

    // 🔑 إصلاح تاني: مش بنخمّن حجم المفتاح (2048/1024)، بنسيب iOS
    // يستنتجه من البيانات نفسها — بيشتغل صح مع أي حجم مفتاح.
    let options: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
    ]

    var createError: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(pkcs1Data as CFData, options as CFDictionary, &createError) else {
      let msg = createError?.takeRetainedValue().localizedDescription ?? "Cannot load private key"
      throw NSError(domain: "KeyError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
    return secKey
  }
}