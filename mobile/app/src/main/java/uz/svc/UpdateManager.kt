package uz.svc

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * OTA-обновление вне Play Store: version.json на лендинге → сравнение versionCode →
 * скачивание APK → системный установщик. Тихая установка на Android невозможна
 * без device-owner — пользователь подтверждает установку одним нажатием.
 */
class UpdateManager(private val context: Context) {

    companion object {
        private const val VERSION_URL = "https://svc.co1nlist.uz/downloads/version.json"
    }

    data class UpdateInfo(val versionCode: Long, val versionName: String, val url: String)

    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    private fun installedVersionCode(): Long {
        val pi = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode
        else @Suppress("DEPRECATION") pi.versionCode.toLong()
    }

    /** null — обновления нет или проверка не удалась (best-effort, запуску не мешаем). */
    suspend fun checkForUpdate(): UpdateInfo? = withContext(Dispatchers.IO) {
        runCatching {
            http.newCall(Request.Builder().url(VERSION_URL).build()).execute().use { resp ->
                if (!resp.isSuccessful) return@use null
                val o = JSONObject(resp.body?.string().orEmpty())
                val info = UpdateInfo(
                    versionCode = o.getLong("versionCode"),
                    versionName = o.getString("versionName"),
                    url = o.getString("url")
                )
                if (info.versionCode > installedVersionCode()) info else null
            }
        }.getOrNull()
    }

    /** Скачивает APK в cache и открывает системный установщик. */
    suspend fun downloadAndInstall(info: UpdateInfo, onProgress: (Int) -> Unit) {
        val apk = withContext(Dispatchers.IO) {
            val file = File(context.cacheDir, "update.apk")
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

        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", apk)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
