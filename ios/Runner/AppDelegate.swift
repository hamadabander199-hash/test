import UIKit
import Flutter
import CryptoKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate {

  var flutterController: FlutterViewController?

  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    self.window = UIWindow(frame: UIScreen.main.bounds)
    let controller = FlutterViewController()
    self.flutterController = controller
    self.window?.rootViewController = controller
    self.window?.makeKeyAndVisible()

    GeneratedPluginRegistrant.register(with: self)

    // بيتحكم في منع screenshot/screen recording وقت فتح شاشة الخزنة -
    // نفس منطق FLAG_SECURE بتاع الأندرويد بالظبط (MainActivity.kt)، هنا
    // بنستخدم UIScreen.capturedDidChangeNotification + secure overlay
    // لأن iOS معندوش FLAG_SECURE مباشر ومفيش API يمنع screenshot فعليًا،
    // لكن ده بيمنع الـ screen recording (isCaptured) اللي هو الأهم.
    let securityChannel = FlutterMethodChannel(
      name: "camzone/security",
      binaryMessenger: controller.binaryMessenger
    )

    securityChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "enableSecureFlag":
        DispatchQueue.main.async {
          self?.enableSecureWindow()
        }
        result(true)

      case "disableSecureFlag":
        DispatchQueue.main.async {
          self?.disableSecureWindow()
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let cryptoChannel = FlutterMethodChannel(
      name: "camzone/encryption",
      binaryMessenger: controller.binaryMessenger
    )

    cryptoChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in

      guard let self = self else { return }

      switch call.method {

      case "encryptFileNative":

        if let args = call.arguments as? [String: Any],
        let input = args["inputPath"] as? String,
        let output = args["outputPath"] as? String,
        let pubKey = args["publicKeyPath"] as? String {

          print("🔹 INPUT PATH:", input)
          print("🔹 OUTPUT PATH:", output)
          print("🔹 PUBLIC KEY PATH:", pubKey)

          DispatchQueue.global(qos: .userInitiated).async {

            do {

              try self.encryptFile(
                inputPath: input,
                outputPath: output,
                publicKeyPath: pubKey
              )

              print("✅ Encryption success")

              DispatchQueue.main.async {
                result(true)
              }

            } catch {

              print("❌ Encryption error:", error.localizedDescription)

              DispatchQueue.main.async {
                result(
                  FlutterError(
                    code: "ENCRYPTION_ERROR",
                    message: "Encryption failed",
                    details: error.localizedDescription
                  )
                )
              }
            }
          }

        } else {

          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "Invalid arguments passed",
              details: nil
            )
          )
        }

      // --- Streaming / real-time video encryption (زي MainActivity.kt بالظبط) ---

      case "startStreamEncryption":

        if let args = call.arguments as? [String: Any],
        let output = args["outputPath"] as? String,
        let pubKey = args["publicKeyPath"] as? String {

          DispatchQueue.global(qos: .userInitiated).async {
            let handle = CryptoNative.startStreamEncryption(withOutputPath: output, publicKeyPath: pubKey)
            DispatchQueue.main.async {
              if handle == 0 {
                result(FlutterError(code: "STREAM_START_FAILED", message: "Native stream init failed", details: nil))
              } else {
                result(handle)
              }
            }
          }

        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing stream-start arguments", details: nil))
        }

      case "feedStreamEncryption":

        if let args = call.arguments as? [String: Any],
        let handleNum = args["handle"] as? NSNumber,
        let dataArg = args["data"] as? FlutterStandardTypedData {

          let handle = handleNum.int64Value
          let bytes = dataArg.data

          DispatchQueue.global(qos: .userInitiated).async {
            let ok = CryptoNative.feedStreamEncryption(withHandle: handle, data: bytes)
            DispatchQueue.main.async {
              result(ok)
            }
          }

        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing stream-feed arguments", details: nil))
        }

      case "finishStreamEncryption":

        if let args = call.arguments as? [String: Any],
        let handleNum = args["handle"] as? NSNumber {

          let handle = handleNum.int64Value

          DispatchQueue.global(qos: .userInitiated).async {
            let ok = CryptoNative.finishStreamEncryption(withHandle: handle)
            DispatchQueue.main.async {
              result(ok)
            }
          }

        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing handle", details: nil))
        }

      case "abortStreamEncryption":

        if let args = call.arguments as? [String: Any],
        let handleNum = args["handle"] as? NSNumber {

          let handle = handleNum.int64Value
          DispatchQueue.global(qos: .userInitiated).async {
            CryptoNative.abortStreamEncryption(withHandle: handle)
            DispatchQueue.main.async {
              result(nil)
            }
          }

        } else {
          result(nil)
        }

      // --- فحص السلامة بعد التسجيل (structural check بس، زي الأندرويد) ---

      case "verifyEncryptedVideo":

        if let args = call.arguments as? [String: Any],
        let path = args["path"] as? String {

          DispatchQueue.global(qos: .userInitiated).async {
            let valid = CryptoNative.verifyEncryptedFile(atPath: path)
            DispatchQueue.main.async {
              result(valid)
            }
          }

        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing path", details: nil))
        }

      // --- فك التشفير (الجهاز عنده مفتاح RSA الخاص) ---

      case "decryptFileToBytes":

        if let args = call.arguments as? [String: Any],
        let input = args["inputPath"] as? String,
        let privateKeyPem = args["privateKeyPem"] as? String {

          DispatchQueue.global(qos: .userInitiated).async {
            let plaintext = CryptoNative.decryptFileToBytes(atPath: input, privateKeyPem: privateKeyPem)
            DispatchQueue.main.async {
              if let plaintext = plaintext {
                result(FlutterStandardTypedData(bytes: plaintext))
              } else {
                result(
                  FlutterError(
                    code: "DECRYPT_FAILED",
                    message: "Decryption failed - file may be corrupted, tampered, or the wrong private key was used",
                    details: nil
                  )
                )
              }
            }
          }

        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing decryption arguments", details: nil))
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Secure window (منع screen recording وقت فتح الخزنة)
  // نفس فكرة FLAG_SECURE بتاع الأندرويد، بس iOS مفيهوش API يمنع
  // screenshot مباشرة. اللي بيتعمل هنا: أي وقت الشاشة بقت "مسجَّلة"
  // (isCaptured == true عن طريق screen recording أو AirPlay/mirroring)
  // إحنا بنغطي الشاشة بطبقة سودا فورًا لحد ما التسجيل يقف.
  private var secureOverlay: UIView?
  private var secureObserver: NSObjectProtocol?
  private var secureFlagEnabled = false

  func enableSecureWindow() {
    secureFlagEnabled = true
    updateSecureOverlay()

    if secureObserver == nil {
      secureObserver = NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.updateSecureOverlay()
      }
    }
  }

  func disableSecureWindow() {
    secureFlagEnabled = false
    if let observer = secureObserver {
      NotificationCenter.default.removeObserver(observer)
      secureObserver = nil
    }
    secureOverlay?.removeFromSuperview()
    secureOverlay = nil
  }

  private func updateSecureOverlay() {
    guard secureFlagEnabled, let window = self.window else { return }

    if UIScreen.main.isCaptured {
      if secureOverlay == nil {
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .black
        overlay.tag = 998877
        window.addSubview(overlay)
        secureOverlay = overlay
      }
    } else {
      secureOverlay?.removeFromSuperview()
      secureOverlay = nil
    }
  }

  // MARK: - Load RSA Public Key
  func loadPublicKey(from path: String) throws -> SecKey {

    let keyString = try String(contentsOfFile: path)

    let cleanedKey = keyString
    .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
    .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
    .replacingOccurrences(of: "\r", with: "")
    .replacingOccurrences(of: "\n", with: "")

    guard let keyData = Data(base64Encoded: cleanedKey) else {
      throw NSError(
        domain: "Encryption",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "Invalid Base64 in public key"]
      )
    }

    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
      kSecAttrKeySizeInBits as String: 2048
    ]

    guard let key = SecKeyCreateWithData(
      keyData as CFData,
      attributes as CFDictionary,
      nil
    ) else {
      throw NSError(
        domain: "Encryption",
        code: 11,
        userInfo: [NSLocalizedDescriptionKey: "SecKeyCreateWithData failed"]
      )
    }

    return key
  }

  // MARK: - Encryption function
  func encryptFile(
  inputPath: String,
  outputPath: String,
  publicKeyPath: String
  ) throws {

    let fileManager = FileManager.default

    guard fileManager.fileExists(atPath: inputPath) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Input file not found"])
    }

    guard fileManager.fileExists(atPath: publicKeyPath) else {
      throw NSError(domain: "EncryptError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Public key file not found"])
    }

    let inputFile = URL(fileURLWithPath: inputPath)
    let outputFile = URL(fileURLWithPath: outputPath)

    let fileData = try Data(contentsOf: inputFile)

    // تحميل المفتاح
    let pubKey = try loadPublicKey(from: publicKeyPath)

    // إنشاء AES key
    let aesKey = SymmetricKey(size: .bits256)

    // IV
    let iv = AES.GCM.Nonce()

    // تحويل AES key لبيانات
    let aesKeyData = aesKey.withUnsafeBytes { Data($0) }

    // تشفير AES key بـ RSA
    var error: Unmanaged<CFError>?

    guard let encAESKey = SecKeyCreateEncryptedData(
      pubKey,
      .rsaEncryptionOAEPSHA256,
      aesKeyData as CFData,
      &error
    ) else {

      throw NSError(
        domain: "EncryptError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: error?.takeRetainedValue().localizedDescription ?? "RSA encryption failed"]
      )
    }

    let encryptedAESKey = encAESKey as Data

    // تشفير الملف بـ AES
    let sealedBox = try AES.GCM.seal(fileData, using: aesKey, nonce: iv)

    // كتابة الملف
    let writer = OutputStream(url: outputFile, append: false)!
    writer.open()
    defer { writer.close() }

    // Header
    writer.write([UInt8]("ENCv1".utf8), maxLength: 5)

    // طول المفتاح
    let keyLen = UInt16(encryptedAESKey.count)
    let keyLenData = Data([UInt8(keyLen >> 8), UInt8(keyLen & 0xFF)])
    writer.write([UInt8](keyLenData), maxLength: 2)

    // AES key encrypted
    writer.write([UInt8](encryptedAESKey), maxLength: encryptedAESKey.count)

    // IV
    let ivData = iv.withUnsafeBytes { Data($0) }
    writer.write([UInt8](ivData), maxLength: ivData.count)

    // Ciphertext
    writer.write([UInt8](sealedBox.ciphertext), maxLength: sealedBox.ciphertext.count)

    // Tag
    writer.write([UInt8](sealedBox.tag), maxLength: sealedBox.tag.count)

    print("✅ Encryption finished")
  }
}