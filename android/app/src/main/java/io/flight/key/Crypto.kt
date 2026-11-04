package io.flight.key

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECPoint

/**
 * 密钥全部长在 Android Keystore 里：私钥进了芯片的 TEE，连本 App 都导不出来。
 * 只能导出公钥。签名输出是标准 DER，正好被 Mac 端 openssl dgst -verify 直接验。
 */
object Crypto {
    private const val ALIAS = "flight"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    fun hasKey(): Boolean {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        return ks.containsAlias(ALIAS)
    }

    /** 在 Keystore 里生成 ECDSA P-256 密钥对 */
    fun generateKey() {
        val kpg = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE
        )
        kpg.initialize(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
            )
                .setDigests(KeyProperties.DIGEST_SHA256)
                .build()
        )
        kpg.generateKeyPair()
    }

    /** 导出公钥为 PEM（纯 SubjectPublicKeyInfo，不含证书壳，Mac 端直接可用） */
    fun exportPublicKeyPem(): String {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cert = ks.getCertificate(ALIAS)
            ?: throw IllegalStateException("密钥不存在，先生成")
        val b64 = Base64.encodeToString(cert.publicKey.encoded, Base64.DEFAULT)
        return "-----BEGIN PUBLIC KEY-----\n$b64-----END PUBLIC KEY-----\n"
    }

    /**
     * 公钥指纹（对 SubjectPublicKeyInfo 做 SHA-256 再 hex），
     * 用来肉眼比对 Mac 端安装的公钥是不是同一把。
     */
    fun publicKeyFingerprint(): String {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cert = ks.getCertificate(ALIAS) ?: return "(未生成)"
        val md = java.security.MessageDigest.getInstance("SHA-256")
        val bytes = md.digest(cert.publicKey.encoded)
        return bytes.take(8).joinToString(" ") { "%02x".format(it) }
    }

    /** 用 Keystore 私钥签名，返回 base64(DER) —— 直接粘进 Mac 的 flight-install */
    fun sign(challenge: String): String {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val entry = ks.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
        val sig = Signature.getInstance("SHA256withECDSA")
        sig.initSign(entry.privateKey)
        sig.update(challenge.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sig.sign(), Base64.NO_WRAP)
    }
}
