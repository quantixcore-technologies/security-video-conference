package uz.svc

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Play Store'siz yangilanish (OTA): landing'dagi `version.json` → versionCode
 * solishtirish → APK yuklab olish → tizim o'rnatuvchisi. Brauzer ham, Play Market
 * ham kerak emas — hammasi ilova ichida.
 *
 * **Majburiy rejim:** `version.json` dagi `minVersionCode` dan past versiyalar
 * yangilanmaguncha ilovadan foydalana olmaydi (mijoz talabi — eski, zaif
 * klientlar maxfiy majlislarga ulanmasligi uchun).
 *
 * Android'da jimjit (silent) o'rnatish device-owner'siz mumkin emas — foydalanuvchi
 * bir marta "O'rnatish" tugmasini bosadi.
 */
class UpdateManager(private val context: Context) {

    companion object {
        private const val VERSION_URL = "https://svc.co1nlist.uz/downloads/version.json"
    }

    data class UpdateInfo(
        val versionCode: Long,
        val versionName: String,
        val url: String,
        val notes: String?,
        /** true — yangilanmaguncha ilova bloklanadi. */
        val mandatory: Boolean
    )

    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    fun installedVersionCode(): Long {
        val pi = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode
        else @Suppress("DEPRECATION") pi.versionCode.toLong()
    }

    fun installedVersionName(): String =
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: "?"

    /**
     * null — yangilanish yo'q yoki tekshirib bo'lmadi.
     * Tarmoq yo'q bo'lsa ilova bloklanmaydi (fail-open): server bilan ishlamasa
     * ilova baribir foydasiz, lekin uni "g'ishtga" aylantirmaymiz.
     */
    suspend fun checkForUpdate(): UpdateInfo? = withContext(Dispatchers.IO) {
        runCatching {
            http.newCall(Request.Builder().url(VERSION_URL).build()).execute().use { resp ->
                if (!resp.isSuccessful) return@use null
                val o = JSONObject(resp.body?.string().orEmpty())

                val latest = o.getLong("versionCode")
                val installed = installedVersionCode()
                if (latest <= installed) return@use null

                // minVersionCode ko'rsatilmagan bo'lsa — yangilanish ixtiyoriy.
                val minRequired = o.optLong("minVersionCode", 0L)

                UpdateInfo(
                    versionCode = latest,
                    versionName = o.getString("versionName"),
                    url = o.getString("url"),
                    notes = o.optString("notes").takeIf { it.isNotBlank() },
                    mandatory = installed < minRequired
                )
            }
        }.getOrNull()
    }

    /** Android 8+ da "noma'lum manbalardan o'rnatish" ruxsati kerak. */
    fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    /** Ruxsat sozlamalari ekrani (Activity'dan ishga tushiriladi). */
    fun installPermissionIntent(): Intent =
        Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** APK'ni cache'ga yuklab, tizim o'rnatuvchisini ochadi. */
    suspend fun downloadAndInstall(info: UpdateInfo, onProgress: (Int) -> Unit) {
        val apk = withContext(Dispatchers.IO) {
            val file = File(context.cacheDir, "update.apk")
            if (file.exists()) file.delete()

            http.newCall(Request.Builder().url(info.url).build()).execute().use { resp ->
                if (!resp.isSuccessful) error("Yuklab olishda xatolik (${resp.code})")
                val body = resp.body ?: error("Serverdan bo'sh javob keldi")
                val total = body.contentLength()
                body.byteStream().use { input ->
                    file.outputStream().use { out ->
                        val buf = ByteArray(64 * 1024)
                        var done = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            done += n
                            if (total > 0) onProgress((done * 100 / total).toInt())
                        }
                    }
                }
            }
            file
        }

        if (apk.length() < 1_000_000) error("Yuklangan fayl to'liq emas — qayta urinib ko'ring")

        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", apk)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
