package uz.n3xt.svc

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
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

    // Compose-состояние видеодорожек
    private val videoTracks = mutableStateListOf<TrackTile>()
    private var status by mutableStateOf("Подключение…")
    private var micOn by mutableStateOf(true)
    private var camOn by mutableStateOf(true)

    data class TrackTile(val id: String, val label: String, val track: VideoTrack)

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
                status = "В эфире"
                room.localParticipant.setMicrophoneEnabled(true)
                room.localParticipant.setCameraEnabled(true)
                // Локальный трек камеры доступен сразу после публикации (нет LocalTrackPublished в SDK 2.18)
                room.localParticipant.getTrackPublication(Track.Source.CAMERA)
                    ?.let { (it.track as? VideoTrack)?.let { t -> addTile(t, "Вы") } }
            }.onFailure { status = "Ошибка: ${it.message}" }
        }
    }

    private fun onRoomEvent(event: RoomEvent) {
        when (event) {
            is RoomEvent.TrackSubscribed ->
                (event.track as? VideoTrack)?.let {
                    addTile(it, event.participant.identity?.value ?: "участник")
                }
            is RoomEvent.TrackUnsubscribed -> removeTile(event.track as? VideoTrack)
            else -> {}
        }
    }

    private fun addTile(track: VideoTrack, label: String) {
        if (videoTracks.none { it.track == track }) {
            videoTracks.add(TrackTile(track.sid ?: track.hashCode().toString(), label, track))
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
            if (videoTracks.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(pad), contentAlignment = Alignment.Center) {
                    Text("Ожидание видео…", color = Color(0xFF64748B))
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(if (videoTracks.size == 1) 1 else 2),
                    modifier = Modifier.fillMaxSize().padding(pad),
                    contentPadding = PaddingValues(8.dp)
                ) {
                    items(videoTracks, key = { it.id }) { tile -> VideoTile(tile) }
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

                FilledIconButton(
                    onClick = { finish() },
                    colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color(0xFFDC2626))
                ) { Icon(Icons.Default.CallEnd, "leave") }
            }
        }
    }
}
