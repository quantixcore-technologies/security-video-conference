package uz.svc

import android.app.Activity
import android.content.Context
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.ScreenShare
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.StopScreenShare
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.Room
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import io.livekit.android.room.track.screencapture.ScreenCaptureParams
import kotlinx.coroutines.launch

/**
 * Экран звонка (E1) — нативный LiveKit (WebRTC), не webview (D-001).
 * E5 anti-capture: FLAG_SECURE — блокирует скриншоты/запись экрана на Android (enforce).
 */
class CallActivity : ComponentActivity() {

    private lateinit var room: Room

    private val permissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { connectToRoom() }

    // Запрос разрешения MediaProjection для демонстрации экрана (screen-share).
    private val screenCapture = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            lifecycleScope.launch {
                runCatching {
                    room.localParticipant.setScreenShareEnabled(
                        true, ScreenCaptureParams(result.data!!)
                    )
                    screenSharing = true
                }
            }
        }
    }

    // Compose-состояние видеодорожек
    private val videoTracks = mutableStateListOf<TrackTile>()
    private var status by mutableStateOf("Ulanmoqda…")
    private var micOn by mutableStateOf(true)
    private var camOn by mutableStateOf(true)

    // Чат (LiveKit data-сообщения, topic "chat") — паритет с web.
    private val messages = mutableStateListOf<ChatMessage>()
    private var chatVisible by mutableStateOf(false)
    private var screenSharing by mutableStateOf(false)

    /**
     * [mirror] — faqat O'ZINGIZNING old kameradan olingan tasviringiz uchun `true`.
     * Kamera sizni qarama-qarshi tomondan ko'radi, shuning uchun xom tasvir
     * ko'zgudagi aksga teskari bo'ladi va foydalanuvchiga g'alati tuyuladi
     * (qo'lni o'ngga qimirlatsa, ekranda chapga ketadi). Barcha video-ilovalar
     * o'z tasvirini ko'zgu qilib ko'rsatadi — biz ham shunday qilamiz.
     * Boshqa ishtirokchilar va ekran namoyishi HECH QACHON ko'zgu qilinmaydi:
     * ularni teskari ko'rsatish yozuvlarni o'qib bo'lmas holga keltiradi.
     */
    data class TrackTile(
        val id: String,
        val label: String,
        val track: VideoTrack,
        val mirror: Boolean = false
    )

    data class ChatMessage(val sender: String, val text: String, val mine: Boolean)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // E5 ENFORCE (Android): запрет скриншотов и записи экрана окна звонка.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        room = LiveKit.create(applicationContext)

        setContent { MaterialTheme(colorScheme = darkColorScheme()) { CallScreen() } }

        permissions.launch(arrayOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO))
    }

    private fun connectToRoom() {
        val url = intent.getStringExtra("url") ?: return finish()
        val token = intent.getStringExtra("token") ?: return finish()

        lifecycleScope.launch {
            launch { room.events.collect { onRoomEvent(it) } }
            runCatching {
                room.connect(url, token)
                status = "Efirda"
                room.localParticipant.setMicrophoneEnabled(true)
                room.localParticipant.setCameraEnabled(true)
                // Локальный трек камеры доступен сразу после публикации (нет LocalTrackPublished в SDK 2.18)
                room.localParticipant.getTrackPublication(Track.Source.CAMERA)
                    ?.let { (it.track as? VideoTrack)?.let { t -> addTile(t, "Siz", mirror = true) } }
            }.onFailure { status = "Xatolik: ${it.message}" }
        }
    }

    private fun onRoomEvent(event: RoomEvent) {
        when (event) {
            is RoomEvent.TrackSubscribed ->
                (event.track as? VideoTrack)?.let {
                    addTile(it, event.participant.identity?.value ?: "ishtirokchi")
                }
            is RoomEvent.TrackUnsubscribed -> removeTile(event.track as? VideoTrack)
            is RoomEvent.DataReceived -> {
                val text = String(event.data, Charsets.UTF_8)
                val sender = event.participant?.identity?.value ?: "ishtirokchi"
                messages.add(ChatMessage(sender, text, mine = false))
            }
            else -> {}
        }
    }

    /** Включает/выключает демонстрацию экрана (MediaProjection → LiveKit screen-track). */
    private fun toggleScreenShare() {
        if (screenSharing) {
            lifecycleScope.launch {
                runCatching { room.localParticipant.setScreenShareEnabled(false) }
                screenSharing = false
            }
        } else {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            screenCapture.launch(mpm.createScreenCaptureIntent())
        }
    }

    /** Отправка текстового сообщения в комнату (reliable data, topic "chat"). */
    private fun sendChat(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        messages.add(ChatMessage("Siz", trimmed, mine = true))
        lifecycleScope.launch {
            runCatching {
                room.localParticipant.publishData(trimmed.toByteArray(Charsets.UTF_8), topic = "chat")
            }
        }
    }

    private fun addTile(track: VideoTrack, label: String, mirror: Boolean = false) {
        if (videoTracks.none { it.track == track }) {
            videoTracks.add(TrackTile(track.sid ?: track.hashCode().toString(), label, track, mirror))
        }
    }

    private fun removeTile(track: VideoTrack?) {
        track ?: return
        videoTracks.removeAll { it.track == track }
    }

    override fun onDestroy() {
        super.onDestroy()
        room.disconnect()
    }

    @Composable
    private fun CallScreen() {
        Scaffold(
            containerColor = Color(0xFF0F172A),
            topBar = {
                Surface(color = Color(0xFF1E293B)) {
                    Row(
                        Modifier.fillMaxWidth().padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Shield, null, tint = Color(0xFF10B981))
                        Spacer(Modifier.width(8.dp))
                        Text(status, color = Color.White)
                    }
                }
            },
            bottomBar = { Controls() }
        ) { pad ->
            Box(Modifier.fillMaxSize().padding(pad)) {
                if (videoTracks.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("Video kutilmoqda…", color = Color(0xFF64748B))
                    }
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(if (videoTracks.size == 1) 1 else 2),
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(8.dp)
                    ) {
                        items(videoTracks, key = { it.id }) { tile -> VideoTile(tile) }
                    }
                }

                if (chatVisible) {
                    ChatPanel(Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }

    @Composable
    private fun ChatPanel(modifier: Modifier = Modifier) {
        var input by remember { mutableStateOf("") }
        Surface(color = Color(0xF21E293B), modifier = modifier.fillMaxWidth().fillMaxHeight(0.55f)) {
            Column(Modifier.fillMaxSize().padding(8.dp)) {
                Text("Chat", color = Color.White, style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(8.dp))
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                ) {
                    if (messages.isEmpty()) {
                        Text("Hozircha xabar yo'q", color = Color(0xFF64748B),
                            modifier = Modifier.padding(8.dp))
                    }
                    messages.forEach { m ->
                        Text(
                            "${m.sender}: ${m.text}",
                            color = if (m.mine) Color(0xFF10B981) else Color.White,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                }
                Row(
                    Modifier.fillMaxWidth().padding(top = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        input, { input = it }, modifier = Modifier.weight(1f),
                        singleLine = true, placeholder = { Text("Xabar…") }
                    )
                    IconButton(onClick = { sendChat(input); input = "" }) {
                        Icon(Icons.AutoMirrored.Filled.Send, "send", tint = Color(0xFF10B981))
                    }
                }
            }
        }
    }

    @Composable
    private fun VideoTile(tile: TrackTile) {
        Box(Modifier.padding(4.dp).fillMaxWidth().height(240.dp)) {
            key(tile.id) {
                AndroidView(
                    factory = { ctx ->
                        TextureViewRenderer(ctx).also { v ->
                            room.initVideoRenderer(v)
                            // Har plitka uchun ochiq belgilaymiz: SDK standartiga
                            // tayanmaymiz, aks holda versiya yangilanganda xatti-harakat
                            // sezdirmay o'zgarib ketishi mumkin.
                            v.setMirror(tile.mirror)
                            tile.track.addRenderer(v)
                        }
                    },
                    onRelease = { v ->
                        tile.track.removeRenderer(v)
                        v.release()
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
            Surface(
                color = Color(0xAA000000),
                modifier = Modifier.align(Alignment.BottomStart).padding(6.dp)
            ) {
                Text(tile.label, color = Color.White, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
            }
        }
    }

    @Composable
    private fun Controls() {
        Surface(color = Color(0xFF1E293B)) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                FilledIconButton(onClick = {
                    micOn = !micOn
                    lifecycleScope.launch { room.localParticipant.setMicrophoneEnabled(micOn) }
                }) { Icon(if (micOn) Icons.Default.Mic else Icons.Default.MicOff, "mic") }

                FilledIconButton(onClick = {
                    camOn = !camOn
                    lifecycleScope.launch { room.localParticipant.setCameraEnabled(camOn) }
                }) { Icon(if (camOn) Icons.Default.Videocam else Icons.Default.VideocamOff, "cam") }

                FilledIconButton(onClick = { chatVisible = !chatVisible }) {
                    Icon(Icons.AutoMirrored.Filled.Chat, "chat")
                }

                FilledIconButton(onClick = { toggleScreenShare() }) {
                    Icon(
                        if (screenSharing) Icons.AutoMirrored.Filled.StopScreenShare
                        else Icons.AutoMirrored.Filled.ScreenShare,
                        "screen-share"
                    )
                }

                FilledIconButton(
                    onClick = { finish() },
                    colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color(0xFFDC2626))
                ) { Icon(Icons.Default.CallEnd, "leave") }
            }
        }
    }
}
