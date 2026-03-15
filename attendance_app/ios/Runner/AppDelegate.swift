import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller = window?.rootViewController as! FlutterViewController
    let keystoreChannel = FlutterMethodChannel(
      name: "com.example.attendance_app/keystore",
      binaryMessenger: controller.binaryMessenger
    )
    
    keystoreChannel.setMethodCallHandler { (call, result) in
      switch call.method {
        
      case "generateKeyPair":
        do {
          let publicKey = try KeychainHelper.generateKeyPair()
          result(publicKey)
        } catch {
          result(FlutterError(code: "KEYGEN_ERROR", message: error.localizedDescription, details: nil))
        }
        
      case "getPublicKey":
        do {
          let publicKey = try KeychainHelper.getPublicKey()
          result(publicKey)
        } catch {
          result(FlutterError(code: "GETKEY_ERROR", message: error.localizedDescription, details: nil))
        }
        
      case "hasKey":
        result(KeychainHelper.hasKey())
        
      case "signData":
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? String else {
          result(FlutterError(code: "SIGN_ERROR", message: "No data provided", details: nil))
          return
        }
        do {
          let signature = try KeychainHelper.signData(data)
          result(signature)
        } catch {
          result(FlutterError(code: "SIGN_ERROR", message: error.localizedDescription, details: nil))
        }
        
      case "deleteKey":
        KeychainHelper.deleteKey()
        result(true)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}