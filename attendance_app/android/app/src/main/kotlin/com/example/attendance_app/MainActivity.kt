package com.example.attendance_app

import android.os.Handler
import android.os.Looper
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.Signature

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.example.attendance_app/keystore"
    private var pendingSignature: Signature? = null
    private var pendingData: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "generateKeyPair" -> {
                    try {
                        val publicKey = KeystoreHelper.generateKeyPair()
                        result.success(publicKey)
                    } catch (e: Exception) {
                        result.error("KEYGEN_ERROR", e.message, null)
                    }
                }

                "getPublicKey" -> {
                    try {
                        val publicKey = KeystoreHelper.getPublicKey()
                        result.success(publicKey)
                    } catch (e: Exception) {
                        result.error("GETKEY_ERROR", e.message, null)
                    }
                }

                "hasKey" -> {
                    try {
                        val has = KeystoreHelper.hasKey()
                        result.success(has)
                    } catch (e: Exception) {
                        result.error("HASKEY_ERROR", e.message, null)
                    }
                }

                "signData" -> {
                    try {
                        val data = call.argument<String>("data")
                            ?: return@setMethodCallHandler result.error(
                                "SIGN_ERROR", "No data provided", null
                            )

                        // Initialize signature with private key
                        val signature = KeystoreHelper.initSignature()

                        // Store pending state
                        pendingSignature = signature
                        pendingData = data
                        pendingResult = result

                        // Show biometric prompt with CryptoObject
                        val executor = ContextCompat.getMainExecutor(this)
                        val biometricPrompt = BiometricPrompt(
                            this,
                            executor,
                            object : BiometricPrompt.AuthenticationCallback() {
                                override fun onAuthenticationSucceeded(
                                    authResult: BiometricPrompt.AuthenticationResult
                                ) {
                                    try {
                                        // Get authenticated signature from CryptoObject
                                        val authenticatedSignature =
                                            authResult.cryptoObject?.signature
                                                ?: throw Exception("No signature in CryptoObject")

                                        val signedData = KeystoreHelper.signWithSignature(
                                            authenticatedSignature,
                                            pendingData!!
                                        )
                                        Handler(Looper.getMainLooper()).post {
                                            pendingResult?.success(signedData)
                                            pendingResult = null
                                            pendingSignature = null
                                            pendingData = null
                                        }
                                    } catch (e: Exception) {
                                        Handler(Looper.getMainLooper()).post {
                                            pendingResult?.error("SIGN_ERROR", e.message, null)
                                            pendingResult = null
                                            pendingSignature = null
                                            pendingData = null
                                        }
                                    }
                                }

                                override fun onAuthenticationError(
                                    errorCode: Int,
                                    errString: CharSequence
                                ) {
                                    Handler(Looper.getMainLooper()).post {
                                        pendingResult?.error(
                                            "BIOMETRIC_ERROR",
                                            errString.toString(),
                                            null
                                        )
                                        pendingResult = null
                                        pendingSignature = null
                                        pendingData = null
                                    }
                                }

                                override fun onAuthenticationFailed() {
                                    // Biometric not recognized — prompt stays open
                                    // user can try again
                                }
                            }
                        )

                        val promptInfo = BiometricPrompt.PromptInfo.Builder()
                            .setTitle("Verify Identity")
                            .setSubtitle("Authenticate to mark attendance")
                            .setNegativeButtonText("Cancel")
                            .setAllowedAuthenticators(
                                androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
                            )
                            .build()

                        biometricPrompt.authenticate(
                            promptInfo,
                            BiometricPrompt.CryptoObject(signature)
                        )

                    } catch (e: Exception) {
                        result.error("SIGN_ERROR", e.message, null)
                    }
                }

                "deleteKey" -> {
                    try {
                        KeystoreHelper.deleteKey()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DELETE_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}