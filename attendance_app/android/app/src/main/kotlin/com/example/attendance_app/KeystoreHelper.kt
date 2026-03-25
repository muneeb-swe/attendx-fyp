package com.example.attendance_app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import android.util.Base64
import java.security.spec.RSAKeyGenParameterSpec
import java.math.BigInteger

object KeystoreHelper {

    private const val KEY_ALIAS = "attendance_key"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

    // Generate RSA key pair inside Android Keystore
    fun generateKeyPair(): String {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)

        // Delete existing key if any
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }

        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            KEYSTORE_PROVIDER
        )

        val parameterSpec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setKeySize(2048)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationValidityDurationSeconds(-1)
            .build()

        keyPairGenerator.initialize(parameterSpec)
        val keyPair = keyPairGenerator.generateKeyPair()

        // Return public key as Base64
        val publicKeyBytes = keyPair.public.encoded
        return Base64.encodeToString(publicKeyBytes, Base64.NO_WRAP)
    }

    // Get existing public key
    fun getPublicKey(): String? {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)

        if (!keyStore.containsAlias(KEY_ALIAS)) return null

        val publicKey = keyStore.getCertificate(KEY_ALIAS)?.publicKey
            ?: return null

        return Base64.encodeToString(publicKey.encoded, Base64.NO_WRAP)
    }

    // Check if key exists
    fun hasKey(): Boolean {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        return keyStore.containsAlias(KEY_ALIAS)
    }

    // Sign data using private key stored in Keystore
    fun signData(data: String): String {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)

        val privateKey = keyStore.getKey(KEY_ALIAS, null)
            ?: throw Exception("No key found. Enroll device first.")

        val signature = Signature.getInstance("SHA256withRSA")
        signature.initSign(privateKey as java.security.PrivateKey)
        signature.update(data.toByteArray(Charsets.UTF_8))

        val signatureBytes = signature.sign()
        return Base64.encodeToString(signatureBytes, Base64.NO_WRAP)
    }

    // Delete key (for re-enrollment)
    fun deleteKey() {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }
}