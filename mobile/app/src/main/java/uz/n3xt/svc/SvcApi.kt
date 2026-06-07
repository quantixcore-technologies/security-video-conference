package uz.n3xt.svc

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Клиент REST API Phoenix-бэкенда (E1):
 *   POST /api/login           -> bearer-токен
 *   POST /api/meetings/:id/join -> {url, token, room} для LiveKit
 *
 * Нативный клиент (D-001): аутентификация bearer-токеном, не cookie.
 */
class SvcApi(private val baseUrl: String) {

    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val json = "application/json".toMediaType()

    data class Session(val token: String, val fullName: String, val role: String)

    data class RoomInfo(val url: String, val token: String, val room: String)

    suspend fun login(username: String, password: String): Session =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
                .put("username", username)
                .put("password", password)
                .toString()
                .toRequestBody(json)

            val req = Request.Builder()
                .url("$baseUrl/api/login")
                .post(body)
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val err = runCatching { JSONObject(text).optString("error") }.getOrNull()
                    error("Вход не удался (${resp.code}): ${err ?: text}")
                }
                val o = JSONObject(text)
                val user = o.getJSONObject("user")
                Session(
                    token = o.getString("token"),
                    fullName = user.optString("full_name"),
                    role = user.optString("role")
                )
            }
        }

    suspend fun join(token: String, meetingId: String): RoomInfo =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url("$baseUrl/api/meetings/$meetingId/join")
                .addHeader("Authorization", "Bearer $token")
                .post(ByteArray(0).toRequestBody(json))
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val err = runCatching { JSONObject(text).optString("error") }.getOrNull()
                    error("Подключение к встрече не удалось (${resp.code}): ${err ?: text}")
                }
                val o = JSONObject(text)
                RoomInfo(
                    // Бэкенд отдаёт ws://127.0.0.1:7880 (его loopback). С устройства/эмулятора
                    // 127.0.0.1 — это сам клиент, поэтому подставляем хост сервера.
                    url = rewriteHost(o.getString("url")),
                    token = o.getString("token"),
                    room = o.getString("room")
                )
            }
        }

    /** Меняет loopback-хост в ws/wss URL на хост, по которому реально доступен сервер. */
    private fun rewriteHost(wsUrl: String): String {
        val serverHost = baseUrl
            .substringAfter("://")
            .substringBefore("/")
            .substringBefore(":")
        return wsUrl
            .replace("127.0.0.1", serverHost)
            .replace("localhost", serverHost)
    }
}
