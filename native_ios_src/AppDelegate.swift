import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      fatalError("rootViewController is not FlutterViewController")
    }

    // نفس اسم القناة المستخدم في Dart: NativeCryptoService -> _iosChannel
    let cryptoChannel = FlutterMethodChannel(
      name: "my_crypto_native",
      binaryMessenger: controller.binaryMessenger
    )

    cryptoChannel.setMethodCallHandler { (call, result) in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "BAD_ARGS", message: "Missing arguments", details: nil))
        return
      }

      switch call.method {
      case "encryptFile":
        guard let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let publicKeyPath = args["publicKeyPath"] as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "Missing encrypt arguments", details: nil))
          return
        }
        // العملية دي ممكن تاخد وقت لملفات كبيرة، فبنشغلها على thread تاني عشان
        // منقفلش الـ UI thread، وبنرجع النتيجة على main thread زي ما Flutter محتاج.
        DispatchQueue.global(qos: .userInitiated).async {
          var errorMsg: NSString?
          let success = CryptoEngine.encryptFile(
            atPath: inputPath,
            toPath: outputPath,
            publicKeyPath: publicKeyPath,
            error: &errorMsg
          )
          DispatchQueue.main.async {
            if success {
              result(true)
            } else {
              result(FlutterError(code: "ENCRYPT_FAILED", message: (errorMsg as String?) ?? "Unknown error", details: nil))
            }
          }
        }

      case "decryptFile":
        guard let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String,
              let privateKeyPath = args["privateKeyPath"] as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "Missing decrypt arguments", details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          var errorMsg: NSString?
          let success = CryptoEngine.decryptFile(
            atPath: inputPath,
            toPath: outputPath,
            privateKeyPath: privateKeyPath,
            error: &errorMsg
          )
          DispatchQueue.main.async {
            if success {
              result(true)
            } else {
              result(FlutterError(code: "DECRYPT_FAILED", message: (errorMsg as String?) ?? "Unknown error", details: nil))
            }
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
