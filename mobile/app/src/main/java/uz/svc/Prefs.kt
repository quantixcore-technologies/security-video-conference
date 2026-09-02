package uz.svc

import android.content.Context

/**
 * Sessiya holati (token, oxirgi ko'rilgan bildirishnoma) — app-private storage.
 * TODO(roadmap): EncryptedSharedPreferences'ga ko'chirish.
 */
object Prefs {
    private const val FILE = "svc_session"

    private fun sp(ctx: Context) = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun token(ctx: Context): String? = sp(ctx).getString("token", null)

    fun saveSession(ctx: Context, token: String) {
        sp(ctx).edit().putString("token", token).apply()
    }

    fun clearSession(ctx: Context) {
        sp(ctx).edit().remove("token").remove("last_seen_notification").apply()
    }

    fun lastSeenNotification(ctx: Context): Long = sp(ctx).getLong("last_seen_notification", 0L)

    fun saveLastSeenNotification(ctx: Context, id: Long) {
        sp(ctx).edit().putLong("last_seen_notification", id).apply()
    }
}
