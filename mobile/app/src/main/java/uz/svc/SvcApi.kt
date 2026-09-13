package uz.svc

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
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

    data class Profile(
        val id: Long,
        val username: String,
        val fullName: String,
        val role: String,
        val phone: String?,
        val department: String?,
        val organization: String?
    )

    /** Profil (GET /api/me) — token tekshiruvi uchun ham ishlatiladi (auto-login). */
    suspend fun me(token: String): Profile =
        withContext(Dispatchers.IO) {
            getJson("/api/me", token).getJSONObject("user").let { u ->
                Profile(
                    id = u.getLong("id"),
                    username = u.optString("username"),
                    fullName = u.optString("full_name"),
                    role = u.optString("role"),
                    phone = u.optStringOrNull("phone"),
                    department = u.optJSONObject("department")?.optString("name"),
                    organization = u.optJSONObject("organization")?.optString("name")
                )
            }
        }

    data class Colleague(
        val id: Long,
        val username: String,
        val fullName: String,
        val role: String,
        val phone: String?,
        val status: String
    )

    /** Bo'limdoshlar ro'yxati (GET /api/users). */
    suspend fun colleagues(token: String): List<Colleague> =
        withContext(Dispatchers.IO) {
            parseColleagues(getJson("/api/users", token).getJSONArray("users"))
        }

    /** Majlisga biriktirish mumkin bo'lgan xodimlar (GET /api/assignable) — teng/past unvon. */
    suspend fun assignable(token: String): List<Colleague> =
        withContext(Dispatchers.IO) {
            parseColleagues(getJson("/api/assignable", token).getJSONArray("users"))
        }

    private fun parseColleagues(arr: JSONArray): List<Colleague> = buildList {
        for (i in 0 until arr.length()) {
            val u = arr.getJSONObject(i)
            add(
                Colleague(
                    id = u.getLong("id"),
                    username = u.optString("username"),
                    fullName = u.optString("full_name"),
                    role = u.optString("role"),
                    phone = u.optStringOrNull("phone"),
                    status = u.optString("status").ifBlank { "active" }
                )
            )
        }
    }

    /** Majlis yaratish (POST /api/meetings) — super_admin/manager. Yaratilgan majlis id. */
    suspend fun createMeeting(token: String, title: String, inviteeIds: List<Long>): Long =
        withContext(Dispatchers.IO) {
            val payload = JSONObject()
                .put("title", title)
                .put("invitee_ids", JSONArray(inviteeIds))

            val req = Request.Builder()
                .url("$baseUrl/api/meetings")
                .addHeader("Authorization", "Bearer $token")
                .post(payload.toString().toRequestBody(json))
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    if (resp.code == 403) error("Majlis yaratishga ruxsat yo'q")
                    error("Majlis yaratilmadi (${resp.code})")
                }
                JSONObject(text).getLong("id")
            }
        }

    data class NotificationItem(
        val id: Long,
        val kind: String,
        val title: String,
        val body: String?,
        val readAt: String?,
        val insertedAt: String?
    )

    data class NotificationsPage(val unread: Int, val items: List<NotificationItem>)

    /** Bildirishnomalar lentasi (GET /api/notifications). */
    suspend fun notifications(token: String): NotificationsPage =
        withContext(Dispatchers.IO) {
            val o = getJson("/api/notifications", token)
            val arr = o.getJSONArray("notifications")
            val items = buildList {
                for (i in 0 until arr.length()) {
                    val n = arr.getJSONObject(i)
                    add(
                        NotificationItem(
                            id = n.getLong("id"),
                            kind = n.optString("kind"),
                            title = n.optString("title"),
                            body = n.optStringOrNull("body"),
                            readAt = n.optStringOrNull("read_at"),
                            insertedAt = n.optStringOrNull("inserted_at")
                        )
                    )
                }
            }
            NotificationsPage(unread = o.optInt("unread"), items = items)
        }

    suspend fun markNotificationRead(token: String, id: Long): Unit =
        withContext(Dispatchers.IO) {
            postEmpty("/api/notifications/$id/read", token)
        }

    suspend fun markAllNotificationsRead(token: String): Unit =
        withContext(Dispatchers.IO) {
            postEmpty("/api/notifications/read-all", token)
        }

    // ── Yordamchi (S39, D-019): /api/assistant/* — web, Android va Tauri uchun bitta kontrakt ──

    data class AssistantEntry(val id: String, val question: String, val answer: String)

    /** Server javobi `status` bo'yicha: ok / unsure / restricted / no_match. */
    sealed class AssistantReply {
        data class Answer(val entry: AssistantEntry, val related: List<AssistantEntry>) : AssistantReply()
        data class Unsure(val candidates: List<AssistantEntry>) : AssistantReply()
        data class Restricted(val question: String, val roleLabels: List<String>) : AssistantReply()
        data class NoMatch(val suggestions: List<AssistantEntry>) : AssistantReply()
    }

    suspend fun assistantSuggestions(token: String, locale: String): List<AssistantEntry> =
        withContext(Dispatchers.IO) {
            parseEntries(getJson("/api/assistant/suggestions?locale=$locale", token).optJSONArray("suggestions"))
        }

    suspend fun assistantAsk(token: String, question: String, locale: String): AssistantReply =
        withContext(Dispatchers.IO) {
            val payload = JSONObject().put("question", question).put("locale", locale)
            val req = Request.Builder()
                .url("$baseUrl/api/assistant/ask")
                .addHeader("Authorization", "Bearer $token")
                .post(payload.toString().toRequestBody(json))
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) error("So'rov bajarilmadi (${resp.code})")
                parseReply(JSONObject(text))
            }
        }

    suspend fun assistantEntry(token: String, id: String, locale: String): AssistantEntry =
        withContext(Dispatchers.IO) {
            val path = "/api/assistant/${java.net.URLEncoder.encode(id, "UTF-8")}?locale=$locale"
            parseEntry(getJson(path, token).getJSONObject("answer"))
        }

    private fun parseReply(o: JSONObject): AssistantReply = when (o.optString("status")) {
        "ok" -> AssistantReply.Answer(parseEntry(o.getJSONObject("answer")), parseEntries(o.optJSONArray("related")))
        "unsure" -> AssistantReply.Unsure(parseEntries(o.optJSONArray("candidates")))
        // Eski server `allowed_role_labels` bermasa — xom rol nomlari (yaxshisi yo'q, lekin bo'sh qolmaydi).
        "restricted" -> AssistantReply.Restricted(
            o.optString("question"),
            strings(o.optJSONArray("allowed_role_labels") ?: o.optJSONArray("allowed_roles"))
        )
        else -> AssistantReply.NoMatch(parseEntries(o.optJSONArray("suggestions")))
    }

    private fun parseEntries(arr: JSONArray?): List<AssistantEntry> = buildList {
        if (arr == null) return@buildList
        for (i in 0 until arr.length()) add(parseEntry(arr.getJSONObject(i)))
    }

    private fun parseEntry(o: JSONObject) =
        AssistantEntry(o.getString("id"), o.optString("question"), o.optString("answer"))

    private fun strings(arr: JSONArray?): List<String> = buildList {
        if (arr == null) return@buildList
        for (i in 0 until arr.length()) add(arr.getString(i))
    }

    private fun getJson(path: String, token: String): JSONObject {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .addHeader("Authorization", "Bearer $token")
            .get()
            .build()

        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) error("So'rov bajarilmadi (${resp.code})")
            return JSONObject(text)
        }
    }

    private fun postEmpty(path: String, token: String) {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .addHeader("Authorization", "Bearer $token")
            .post(JSONObject().toString().toRequestBody(json))
            .build()

        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("So'rov bajarilmadi (${resp.code})")
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

    data class MeetingItem(
        val id: Long,
        val title: String,
        val status: String,
        val type: String,
        val scheduledStart: String?
    )

    /** Список встреч организации пользователя — экран после логина (без ввода ID). */
    suspend fun meetings(token: String): List<MeetingItem> =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url("$baseUrl/api/meetings")
                .addHeader("Authorization", "Bearer $token")
                .get()
                .build()

            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    error("Uchrashuvlar ro'yxatini olib bo'lmadi (${resp.code})")
                }
                val arr = JSONObject(text).getJSONArray("meetings")
                buildList {
                    for (i in 0 until arr.length()) {
                        val m = arr.getJSONObject(i)
                        add(
                            MeetingItem(
                                id = m.getLong("id"),
                                title = m.optString("title"),
                                status = m.optString("status"),
                                type = m.optString("type"),
                                scheduledStart =
                                    if (m.isNull("scheduled_start")) null
                                    else m.getString("scheduled_start")
                            )
                        )
                    }
                }
            }
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
