package com.example.attendance_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.example.attendance_app/keystore"

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
                        val signature = KeystoreHelper.signData(data)
                        result.success(signature)
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