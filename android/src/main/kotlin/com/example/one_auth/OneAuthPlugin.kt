package com.example.one_auth

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x500.X500NameBuilder
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x509.AlgorithmIdentifier
import org.bouncycastle.asn1.x9.X9ObjectIdentifiers
import org.bouncycastle.openssl.jcajce.JcaPEMWriter
import org.bouncycastle.operator.ContentSigner
import org.bouncycastle.pkcs.PKCS10CertificationRequest
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder
import java.io.OutputStream
import java.io.StringWriter
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.NoSuchAlgorithmException
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/** OneAuthPlugin */
class OneAuthPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private val CHANNEL_NAME = "com.example.one_auth/crypto"
  private val ANDROID_KEYSTORE = "AndroidKeyStore"
  private val KEY_ALIAS = "one_auth_key"

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "generateCsrAndAttestation" -> {
        val challenge = call.argument<String>("challenge") ?: "default_challenge"
        val identity = call.argument<String>("identity") ?: "OneAuth Device"
        val bankId = call.argument<String>("bankId") ?: "OneAuth"
        val deviceUuid = call.argument<String>("deviceUuid") ?: "unknown_device"
        try {
          val data = generateCsrAndAttestation(challenge, identity, bankId, deviceUuid)
          result.success(data)
        } catch (e: Exception) {
          result.error("CRYPTO_ERROR", e.message, e.stackTraceToString())
        }
      }
      "signTransactionHash" -> {
        val txnHash = if (call.arguments is String) call.arguments as String else ""
        try {
          val signature = signTransactionHash(txnHash)
          result.success(signature)
        } catch (e: Exception) {
          result.error("SIGN_ERROR", e.message, null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun generateCsrAndAttestation(challenge: String, identity: String, bankId: String, deviceUuid: String): Map<String, Any> {
    Log.d("OneAuthPlugin", "Generating CSR for identity: $identity, bankId: $bankId, deviceUuid: $deviceUuid")
    val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
    keyStore.load(null)

    if (keyStore.containsAlias(KEY_ALIAS)) {
      keyStore.deleteEntry(KEY_ALIAS)
    }

    val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, ANDROID_KEYSTORE)
    val spec = KeyGenParameterSpec.Builder(
      KEY_ALIAS,
      KeyProperties.PURPOSE_SIGN
    )
      .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
      .setDigests(KeyProperties.DIGEST_SHA256)
      .setAttestationChallenge(Base64.decode(challenge, Base64.NO_WRAP))
      .build()

    kpg.initialize(spec)
    val keyPair = kpg.generateKeyPair()

    val certificates = keyStore.getCertificateChain(KEY_ALIAS)
    val certChainBase64 = certificates.map { cert ->
      Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
    }

    val privateKey = keyPair.private
    val publicKey = keyPair.public

    val subject: X500Name = X500NameBuilder(BCStyle.INSTANCE)
      .addRDN(BCStyle.CN, identity)
      .addRDN(BCStyle.OU, bankId)
      .addRDN(BCStyle.UID, deviceUuid)
      .build()

    val csrBuilder = JcaPKCS10CertificationRequestBuilder(subject, publicKey)
    val signer = AndroidKeystoreContentSigner("SHA256withECDSA", privateKey)
    val csr: PKCS10CertificationRequest = csrBuilder.build(signer)

    val sw = StringWriter()
    val pemWriter = JcaPEMWriter(sw)
    try {
      pemWriter.writeObject(csr)
      pemWriter.flush()
    } finally {
      pemWriter.close()
    }

    val csrPem = sw.toString()

    return mapOf(
      "csrPem" to csrPem,
      "attestationCertificateChain" to certChainBase64
    )
  }

  private fun signTransactionHash(txnHash: String): String {
    val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
    keyStore.load(null)
    val privateKey = keyStore.getKey(KEY_ALIAS, null) as? PrivateKey
      ?: throw IllegalStateException("No private key found for alias $KEY_ALIAS - device is not enrolled")

    val signature = Signature.getInstance("SHA256withECDSA")
    signature.initSign(privateKey)
    signature.update(txnHash.toByteArray(Charsets.US_ASCII))
    val signatureBytes = signature.sign()

    return Base64.encodeToString(signatureBytes, Base64.NO_WRAP)
  }

  private class AndroidKeystoreContentSigner(
    private val algorithm: String,
    private val privateKey: PrivateKey
  ) : ContentSigner {

    private val KEYSTORE_SIGNATURE_PROVIDER_NAMES = listOf(
      "AndroidKeyStore",
      "AndroidKeyStoreBCWorkaround"
    )

    private val signature: Signature = createSignature(algorithm, privateKey)
    private val outputStream = SignatureOutputStream(signature)
    private val algorithmIdentifier = AlgorithmIdentifier(X9ObjectIdentifiers.ecdsa_with_SHA256)

    override fun getAlgorithmIdentifier(): AlgorithmIdentifier = algorithmIdentifier
    override fun getOutputStream(): OutputStream = outputStream
    override fun getSignature(): ByteArray = signature.sign()

    private fun createSignature(algorithm: String, privateKey: PrivateKey): Signature {
      var lastError: Exception? = null
      for (providerName in KEYSTORE_SIGNATURE_PROVIDER_NAMES) {
        try {
          return Signature.getInstance(algorithm, providerName).apply { initSign(privateKey) }
        } catch (e: Exception) {
          lastError = e
        }
      }
      throw lastError ?: NoSuchAlgorithmException("$algorithm not found under any of: $KEYSTORE_SIGNATURE_PROVIDER_NAMES")
    }
  }

  private class SignatureOutputStream(private val signature: Signature) : OutputStream() {
    override fun write(b: Int) {
      signature.update(b.toByte())
    }

    override fun write(b: ByteArray, off: Int, len: Int) {
      signature.update(b, off, len)
    }
  }
}
