package uz.svc

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Fon tekshiruvi (~15 daqiqada, WorkManager minimumi): yangi bildirishnoma bo'lsa —
 * tizim bildirishnomasi chiqaradi (ilova yopiq bo'lsa ham). Bu push/SMS emas,
 * davriy so'rov — real-vaqt push (FCM) va SMS-gateway yo'l xaritasida.
 */
class NotifyWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {

    companion object {
        private const val WORK_NAME = "svc-notify-poll"
        private const val CHANNEL_ID = "svc_notifications"
        private const val SERVER_URL = "https://admin.co1nlist.uz"

        fun schedule(ctx: Context) {
            val request = PeriodicWorkRequestBuilder<NotifyWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(ctx)
                .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(ctx: Context) {
            WorkManager.getInstance(ctx).cancelUniqueWork(WORK_NAME)
        }
    }

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        val token = Prefs.token(ctx) ?: return Result.success()

        val page = runCatching { SvcApi(SERVER_URL).notifications(token) }
            .getOrElse { return Result.success() } // tarmoq yo'q/401 — jim o'tkazamiz

        val lastSeen = Prefs.lastSeenNotification(ctx)
        val fresh = page.items.filter { it.id > lastSeen && it.readAt == null }
        if (fresh.isEmpty()) return Result.success()

        Prefs.saveLastSeenNotification(ctx, page.items.maxOf { it.id })

        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return Result.success()

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "SVC bildirishnomalari", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }

        val open = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fresh.take(3).forEach { n ->
            val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(n.title)
                .setContentText(n.body ?: "")
                .setAutoCancel(true)
                .setContentIntent(open)
                .build()
            nm.notify(n.id.toInt(), notif)
        }

        return Result.success()
    }
}
