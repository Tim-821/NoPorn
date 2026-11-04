package io.flight.key

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

/**
 * Flight 钥匙 —— 私钥长在这台手机里，签一次少一次。
 *
 * 触发方式：
 *   1. Mac 发邮件到朋友邮箱，正文带 flight://sign?c=<挑战码> 链接
 *   2. 点链接 → 唤起本 App，挑战码已填入
 *   3. 点「同意并签名」→ 弹出邮件草稿，响应码已填好，点发送即可
 */
class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var fingerprint: TextView
    private lateinit var pubkeyView: TextView
    private lateinit var challengeInput: EditText
    private lateinit var recipientView: TextView

    private val prefs by lazy { getSharedPreferences("flight", Context.MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        status = findViewById(R.id.status)
        fingerprint = findViewById(R.id.fingerprint)
        pubkeyView = findViewById(R.id.pubkeyView)
        challengeInput = findViewById(R.id.challenge)
        recipientView = findViewById(R.id.recipientView)

        findViewById<Button>(R.id.btnGen).setOnClickListener {
            AlertDialog.Builder(this)
                .setTitle("生成新密钥")
                .setMessage("旧密钥作废。Mac 上要用新公钥重新换一次。\n继续吗？")
                .setPositiveButton("生成") { _, _ -> generate() }
                .setNegativeButton("取消", null)
                .show()
        }

        findViewById<Button>(R.id.btnCopyPub).setOnClickListener {
            copy(Crypto.exportPublicKeyPem())
        }

        findViewById<Button>(R.id.btnSign).setOnClickListener {
            signAndSend()
        }

        findViewById<Button>(R.id.btnRecipient).setOnClickListener {
            askRecipient()
        }

        refreshUi()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    /** 从 flight://sign?c=<挑战码> 进来 */
    private fun handleIntent(intent: Intent?) {
        val challenge = intent?.data?.getQueryParameter("c") ?: return
        if (challenge.isNotBlank()) {
            challengeInput.setText(challenge)
            Toast.makeText(this, "请求码已填入，请核对后点同意", Toast.LENGTH_LONG).show()
        }
    }

    private fun generate() {
        try {
            Crypto.generateKey()
            refreshUi()
            copy(Crypto.exportPublicKeyPem())
            Toast.makeText(this, "密钥已生成，公钥已复制到剪贴板", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(this, "失败：${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun refreshUi() {
        val has = Crypto.hasKey()
        if (has) {
            status.text = "密钥就绪"
            status.setTextColor(0xFF34D399.toInt())
        } else {
            status.text = "还没有密钥，先点下面的「生成新密钥」"
            status.setTextColor(0xFFF5B942.toInt())
        }
        if (has) {
            fingerprint.text = "指纹 ${Crypto.publicKeyFingerprint()}"
            pubkeyView.visibility = View.VISIBLE
            pubkeyView.text = Crypto.exportPublicKeyPem()
        } else {
            fingerprint.text = ""
            pubkeyView.visibility = View.GONE
        }
        recipientView.text = "回传到 ${prefs.getString("recipient", "(未设置)")}"
    }

    private fun signAndSend() {
        val challenge = challengeInput.text.toString().trim()
        if (!challenge.startsWith("FLIGHT")) {
            Toast.makeText(this, "请求码格式不对，要以 FLIGHT 开头", Toast.LENGTH_LONG).show()
            return
        }
        val recipient = prefs.getString("recipient", null)
        if (recipient.isNullOrBlank()) {
            askRecipient()
            return
        }
        try {
            val sig = Crypto.sign(challenge)
            // mailto 预填收件人 + 正文，朋友只要点"发送"
            val uri = Uri.parse("mailto:")
                .buildUpon()
                .appendQueryParameter("to", recipient)
                .appendQueryParameter("subject", "Flight 响应码")
                .appendQueryParameter("body", sig)
                .build()
            startActivity(Intent(Intent.ACTION_SENDTO, uri))
            copy(sig)
        } catch (e: Exception) {
            Toast.makeText(this, "签名失败：${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun askRecipient() {
        val input = EditText(this).apply {
            hint = "Mac 那边的收件邮箱"
            setText(prefs.getString("recipient", ""))
        }
        AlertDialog.Builder(this)
            .setTitle("回传邮箱")
            .setView(input)
            .setPositiveButton("保存") { _, _ ->
                prefs.edit().putString("recipient", input.text.toString().trim()).apply()
                refreshUi()
            }
            .setNegativeButton("取消", null)
            .show()
    }

    private fun copy(text: String) {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("flight", text))
    }
}
