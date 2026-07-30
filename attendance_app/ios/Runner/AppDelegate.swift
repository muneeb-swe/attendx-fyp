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

            // MARK: - generateKeyPair
            case "generateKeyPair":
                do {
                    let publicKey = try KeychainHelper.generateKeyPair()
                    result(publicKey)
                } catch {
                    result(FlutterError(
                        code: "KEYGEN_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }

            // MARK: - getPublicKey
            case "getPublicKey":
                do {
                    let publicKey = try KeychainHelper.getPublicKey()
                    result(publicKey)
                } catch {
                    result(FlutterError(
                        code: "GETKEY_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }

            // MARK: - hasKey
            case "hasKey":
                result(KeychainHelper.hasKey())

            // MARK: - signData
            // iOS equivalent of Android BiometricPrompt + CryptoObject
            // Biometric prompt is shown by LAContext inside KeychainHelper.signData()
            // Flutter does not manage biometric UI — it simply awaits the result
            // The OS handles the prompt automatically when signing is attempted
            case "signData":
                guard let args = call.arguments as? [String: Any],
                      let data = args["data"] as? String else {
                    result(FlutterError(
                        code: "SIGN_ERROR",
                        message: "No data provided",
                        details: nil
                    ))
                    return
                }

                KeychainHelper.signData(data) { signResult in
                    DispatchQueue.main.async {
                        switch signResult {
                        case .success(let signature):
                            result(signature)
                        case .failure(let error):
                            result(FlutterError(
                                code: "SIGN_ERROR",
                                message: error.localizedDescription,
                                details: nil
                            ))
                        }
                    }
                }

            // MARK: - deleteKey
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