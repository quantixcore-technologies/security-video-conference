package uz.svc

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Password
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    companion object {
        // Manzil foydalanuvchiga ko'rsatilmaydi — UI'da server/IP maydoni yo'q.
        private const val SERVER_URL = "https://admin.co1nlist.uz"

        private val Bg = Color(0xFF0F172A)
        private val Panel = Color(0xFF1E293B)
        private val Accent = Color(0xFF10B981)
        private val Muted = Color(0xFF64748B)
    }

    // E7: запрос разрешения на геолокацию (GPS отправляется при join, см. currentGeo()).
    private val locationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* отказ допустим: join пройдёт без координат */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { App() } }
    }

    /** Последняя известная GPS-точка (best-effort, без Play Services). null, если нет разрешения/фикса. */
    private fun currentGeo(): SvcApi.GeoPoint? {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return null

        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        val best = try {
            lm.getProviders(true)
                .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
                .maxByOrNull { it.time }
        } catch (_: SecurityException) {
            null
        } ?: return null

        return SvcApi.GeoPoint(
            lat = best.latitude,
            lon = best.longitude,
            accuracy = if (best.hasAccuracy()) best.accuracy.toDouble() else null
        )
    }

    private data class Auth(val api: SvcApi, val session: SvcApi.Session)

    @Composable
    private fun App() {
        var showLogin by rememberSaveable { mutableStateOf(false) }
        var auth by remember { mutableStateOf<Auth?>(null) }

        when {
            auth != null -> {
                BackHandler { auth = null; showLogin = false }
                MeetingsScreen(auth!!, onLogout = { auth = null; showLogin = false })
            }
            showLogin -> {
                BackHandler { showLogin = false }
                LoginScreen(onBack = { showLogin = false }, onSuccess = { auth = it })
            }
            else -> LandingScreen(onLoginClick = {
                showLogin = true
                locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
            })
        }
        UpdateDialog()
    }

    // ── OTA: serverdagi version.json bilan solishtirib, yangi APK'ni taklif qiladi ──

    @Composable
    private fun UpdateDialog() {
        val updater = remember { UpdateManager(applicationContext) }
        var update by remember { mutableStateOf<UpdateManager.UpdateInfo?>(null) }
        var downloading by remember { mutableStateOf(false) }
        var progress by remember { mutableStateOf(0) }
        var failed by remember { mutableStateOf(false) }

        LaunchedEffect(Unit) { update = updater.checkForUpdate() }

        update?.let { info ->
            AlertDialog(
                onDismissRequest = { if (!downloading) update = null },
                containerColor = Panel,
                title = { Text("Yangi versiya: v${info.versionName}", color = Color.White) },
                text = {
                    when {
                        downloading -> Column {
                            Text("Yuklab olinmoqda… $progress%", color = Muted)
                            Spacer(Modifier.height(10.dp))
                            LinearProgressIndicator(
                                progress = { progress / 100f },
                                color = Accent,
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                        failed -> Text("Yuklab olishda xatolik. Qayta urinib ko'ring.", color = MaterialTheme.colorScheme.error)
                        else -> Text("Ilovaning yangilangan versiyasi chiqdi. Hozir yangilansinmi?", color = Muted)
                    }
                },
                confirmButton = {
                    TextButton(
                        enabled = !downloading,
                        onClick = {
                            downloading = true
                            failed = false
                            lifecycleScope.launch {
                                runCatching { updater.downloadAndInstall(info) { p -> progress = p } }
                                    .onSuccess { update = null }
                                    .onFailure { failed = true }
                                downloading = false
                            }
                        }
                    ) { Text(if (failed) "Qayta urinish" else "Yangilash", color = Accent) }
                },
                dismissButton = {
                    TextButton(enabled = !downloading, onClick = { update = null }) {
                        Text("Keyinroq", color = Muted)
                    }
                }
            )
        }
    }

    // ── Landing: ilova ochilganda ko'rinadigan bosh sahifa (kirish — o'ng yuqorida) ──

    @Composable
    private fun LandingScreen(onLoginClick: () -> Unit) {
        Surface(color = Bg, modifier = Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Shield, null, tint = Accent, modifier = Modifier.size(28.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("SVC", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = onLoginClick) {
                        Icon(
                            Icons.Default.AccountCircle, contentDescription = "Kirish",
                            tint = Accent, modifier = Modifier.size(34.dp)
                        )
                    }
                }
                HorizontalDivider(color = Panel)

                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Spacer(Modifier.height(28.dp))
                    Icon(Icons.Default.Shield, null, tint = Accent, modifier = Modifier.size(72.dp))
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "Security Video Conference",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Davlat va korporativ tuzilmalar uchun xavfsiz video-aloqa platformasi",
                        color = Muted,
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Spacer(Modifier.height(32.dp))

                    FeatureCard(
                        Icons.Default.Lock, "Himoyalangan aloqa",
                        "Media oqimlari zamonaviy shifrlash (DTLS-SRTP) bilan uzatiladi"
                    )
                    FeatureCard(
                        Icons.Default.Password, "Ikki bosqichli kirish",
                        "Parol va bir martalik kod (2FA) orqali autentifikatsiya"
                    )
                    FeatureCard(
                        Icons.Default.Videocam, "Video va ekran namoyishi",
                        "Yuqori sifatli video, guruh chati va ekranni ulashish"
                    )
                    FeatureCard(
                        Icons.Default.VisibilityOff, "Yozib olishdan himoya",
                        "Qo'ng'iroq oynasida skrinshot va ekran yozuvi bloklanadi"
                    )

                    Spacer(Modifier.height(32.dp))
                    Button(
                        onClick = onLoginClick,
                        colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.White),
                        modifier = Modifier.fillMaxWidth().height(50.dp)
                    ) { Text("Tizimga kirish") }
                    Spacer(Modifier.height(24.dp))
                    Text(
                        "QuantixCore Technologies · O'zbekiston",
                        color = Muted, style = MaterialTheme.typography.bodySmall
                    )
                    Spacer(Modifier.height(16.dp))
                }
            }
        }
    }

    @Composable
    private fun FeatureCard(icon: ImageVector, title: String, text: String) {
        Surface(
            color = Panel,
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)
        ) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, tint = Accent, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(title, color = Color.White, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(2.dp))
                    Text(text, color = Muted, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }

    // ── Kirish ekrani (server maydoni ham, uchrashuv ID ham yo'q) ──

    @Composable
    private fun LoginScreen(onBack: () -> Unit, onSuccess: (Auth) -> Unit) {
        var username by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        // null = шаг логина; не-null = ждём TOTP-код (промежуточный токен 2FA).
        var totpToken by remember { mutableStateOf<String?>(null) }
        var totpCode by remember { mutableStateOf("") }

        Surface(color = Bg, modifier = Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Orqaga", tint = Color.White)
                    }
                    Text("Tizimga kirish", color = Color.White, fontWeight = FontWeight.SemiBold)
                }
                HorizontalDivider(color = Panel)

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(Icons.Default.Shield, null, tint = Accent, modifier = Modifier.size(56.dp))
                    Spacer(Modifier.height(8.dp))
                    Text("Security Video Conference", style = MaterialTheme.typography.titleLarge, color = Color.White)
                    Text("Xavfsiz video-aloqa", color = Muted)
                    Spacer(Modifier.height(28.dp))

                    if (totpToken == null) {
                        OutlinedTextField(username, { username = it }, label = { Text("Login") },
                            singleLine = true, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(password, { password = it }, label = { Text("Parol") },
                            singleLine = true, visualTransformation = PasswordVisualTransformation(),
                            modifier = Modifier.fillMaxWidth())
                    } else {
                        Text("Ikki bosqichli tasdiqlash", style = MaterialTheme.typography.titleMedium)
                        Text("Autentifikator ilovasidagi 6 xonali kodni kiriting",
                            color = Muted, style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(totpCode, { totpCode = it.filter(Char::isDigit).take(6) },
                            label = { Text("2FA kod") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth())
                    }

                    error?.let {
                        Spacer(Modifier.height(12.dp))
                        Text(it, color = MaterialTheme.colorScheme.error)
                    }

                    Spacer(Modifier.height(24.dp))
                    if (totpToken == null) {
                        Button(
                            enabled = !busy,
                            onClick = {
                                error = null
                                busy = true
                                lifecycleScope.launch {
                                    runCatching {
                                        val api = SvcApi(SERVER_URL)
                                        when (val res = api.login(username.trim(), password)) {
                                            is SvcApi.LoginResult.Success -> Auth(api, res.session)
                                            is SvcApi.LoginResult.TotpRequired -> {
                                                totpToken = res.totpToken
                                                null
                                            }
                                        }
                                    }.onSuccess { a ->
                                        busy = false
                                        a?.let(onSuccess)
                                    }.onFailure {
                                        busy = false
                                        error = it.message ?: "Xatolik yuz berdi"
                                    }
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.White),
                            modifier = Modifier.fillMaxWidth().height(50.dp)
                        ) {
                            if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
                            else Text("Kirish")
                        }
                    } else {
                        Button(
                            enabled = !busy && totpCode.length == 6,
                            onClick = {
                                error = null
                                busy = true
                                lifecycleScope.launch {
                                    runCatching {
                                        val api = SvcApi(SERVER_URL)
                                        val session = api.verifyTotp(totpToken!!, totpCode)
                                        Auth(api, session)
                                    }.onSuccess { a ->
                                        busy = false
                                        onSuccess(a)
                                    }.onFailure {
                                        busy = false
                                        error = it.message ?: "Xatolik yuz berdi"
                                    }
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.White),
                            modifier = Modifier.fillMaxWidth().height(50.dp)
                        ) {
                            if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
                            else Text("Kodni tasdiqlash")
                        }
                        Spacer(Modifier.height(8.dp))
                        TextButton(onClick = { totpToken = null; totpCode = ""; error = null }) {
                            Text("Orqaga", color = Muted)
                        }
                    }
                }
            }
        }
    }

    // ── Uchrashuvlar ro'yxati: login'dan keyin foydalanuvchi o'zi boshqaradi ──

    @Composable
    private fun MeetingsScreen(auth: Auth, onLogout: () -> Unit) {
        var meetings by remember { mutableStateOf<List<SvcApi.MeetingItem>?>(null) }
        var loadError by remember { mutableStateOf<String?>(null) }
        var joinError by remember { mutableStateOf<String?>(null) }
        var busyId by remember { mutableStateOf<Long?>(null) }
        var reload by remember { mutableStateOf(0) }

        LaunchedEffect(reload) {
            loadError = null
            meetings = null
            runCatching { auth.api.meetings(auth.session.token) }
                .onSuccess { meetings = it }
                .onFailure { loadError = it.message ?: "Xatolik yuz berdi" }
        }

        Surface(color = Bg, modifier = Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Shield, null, tint = Accent, modifier = Modifier.size(26.dp))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Uchrashuvlar", color = Color.White, fontWeight = FontWeight.Bold)
                        Text(
                            auth.session.fullName.ifBlank { "Foydalanuvchi" },
                            color = Muted, style = MaterialTheme.typography.bodySmall
                        )
                    }
                    IconButton(onClick = { reload++ }) {
                        Icon(Icons.Default.Refresh, "Yangilash", tint = Muted)
                    }
                    IconButton(onClick = onLogout) {
                        Icon(Icons.AutoMirrored.Filled.Logout, "Chiqish", tint = Muted)
                    }
                }
                HorizontalDivider(color = Panel)

                joinError?.let {
                    Text(
                        it, color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                }

                when {
                    loadError != null -> Column(
                        Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(loadError!!, color = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.height(12.dp))
                        TextButton(onClick = { reload++ }) { Text("Qayta urinish", color = Accent) }
                    }

                    meetings == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Accent)
                    }

                    meetings!!.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("Hozircha uchrashuvlar yo'q", color = Muted)
                    }

                    else -> LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        items(meetings!!, key = { it.id }) { m ->
                            MeetingCard(
                                m,
                                busy = busyId == m.id,
                                enabled = busyId == null,
                                onJoin = {
                                    joinError = null
                                    busyId = m.id
                                    lifecycleScope.launch {
                                        joinAndGo(auth, m.id.toString()) { msg -> joinError = msg }
                                        busyId = null
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun MeetingCard(m: SvcApi.MeetingItem, busy: Boolean, enabled: Boolean, onJoin: () -> Unit) {
        Surface(color = Panel, shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth()) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        m.title.ifBlank { "Uchrashuv №${m.id}" },
                        color = Color.White, fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(
                        listOfNotNull(statusLabel(m.status), prettyDate(m.scheduledStart))
                            .joinToString(" · "),
                        color = Muted, style = MaterialTheme.typography.bodySmall
                    )
                }
                Spacer(Modifier.width(12.dp))
                Button(
                    onClick = onJoin,
                    enabled = enabled,
                    colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.White),
                    contentPadding = PaddingValues(horizontal = 18.dp, vertical = 8.dp)
                ) {
                    if (busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    else Text("Kirish")
                }
            }
        }
    }

    private fun statusLabel(status: String): String = when (status) {
        "planned" -> "Rejalashtirilgan"
        "active", "started", "in_progress" -> "Davom etmoqda"
        "finished", "ended", "completed" -> "Yakunlangan"
        "canceled", "cancelled" -> "Bekor qilingan"
        else -> status
    }

    /** "2026-09-02T14:30:00.000000Z" → "2026-09-02 14:30" (ko'rsatish uchun). */
    private fun prettyDate(iso: String?): String? =
        iso?.take(16)?.replace("T", " ")?.takeIf { it.isNotBlank() }

    /** Подключается к встрече по сессии и открывает экран звонка. */
    private suspend fun joinAndGo(auth: Auth, meetingId: String, onError: (String) -> Unit) {
        runCatching { auth.api.join(auth.session.token, meetingId, currentGeo()) }
            .onSuccess { room ->
                startActivity(
                    Intent(this@MainActivity, CallActivity::class.java).apply {
                        putExtra("url", room.url)
                        putExtra("token", room.token)
                        putExtra("room", room.room)
                    }
                )
            }
            .onFailure { onError(it.message ?: "Xatolik yuz berdi") }
    }
}
