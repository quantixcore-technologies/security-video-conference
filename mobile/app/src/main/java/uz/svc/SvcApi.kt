package uz.svc

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

    /** Результат первого шага логина: либо готовая сессия, либо требование 2FA. */
    sealed class LoginResult {
        data class Success(val session: Session) : LoginResult()
        data class TotpRequired(val totpToken: String) : LoginResult()
    }

    suspend fun login(username: String, password: String): LoginResult =
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
                    error("Kirish amalga oshmadi (${resp.code}): ${err ?: text}")
                }
                val o = JSONObject(text)
                if (o.optBoolean("totp_required")) {
                    LoginResult.TotpRequired(o.getString("totp_token"))
                } else {
                    LoginResult.Success(parseSession(o))
                }
            }
        }

    /** Второй шаг 2FA: обмен промежуточного токена + TOTP-кода на bearer-сессию. */
    suspend fun verifyTotp(totpToken: String, code: String): Session =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
                .put("totp_token", totpToken)
                .put("code", code)
                .toString()
                .toRequestBody(json)

            val req = Request.Builder()
                .url("$baseUrl/api/login/totp")
                .post(body)
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val err = runCatching { JSONObject(text).optString("error") }.getOrNull()
                    error("2FA kod qabul qilinmadi (${resp.code}): ${err ?: text}")
                }
                parseSession(JSONObject(text))
            }
        }

    private fun parseSession(o: JSONObject): Session {
        val user = o.getJSONObject("user")
        return Session(
            token = o.getString("token"),
            fullName = user.optString("full_name"),
            role = user.optString("role")
        )
    }

    /** GPS-координаты клиента на момент join (E7). Все поля опциональны. */
    data class GeoPoint(val lat: Double, val lon: Double, val accuracy: Double?)

    suspend fun join(token: String, meetingId: String, geo: GeoPoint? = null): RoomInfo =
        withContext(Dispatchers.IO) {
            val payload = JSONObject()
            geo?.let {
                payload.put("lat", it.lat).put("lon", it.lon)
                it.accuracy?.let { acc -> payload.put("accuracy", acc) }
            }

            val req = Request.Builder()
                .url("$baseUrl/api/meetings/$meetingId/join")
                .addHeader("Authorization", "Bearer $token")
                .post(payload.toString().toRequestBody(json))
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    val err = runCatching { JSONObject(text).optString("error") }.getOrNull()
                    error("Uchrashuvga ulanib bo'lmadi (${resp.code}): ${err ?: text}")
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
