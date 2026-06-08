package uz.n3xt.svc

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    // E7: запрос разрешения на геолокацию (GPS отправляется при join, см. currentGeo()).
    private val locationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* отказ допустим: join пройдёт без координат */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { LoginScreen() } }
        locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
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

    @Composable
    private fun LoginScreen() {
        var server by remember { mutableStateOf("http://10.0.2.2:4000") }
        var username by remember { mutableStateOf("admin") }
        var password by remember { mutableStateOf("AdminPass12345") }
        var meetingId by remember { mutableStateOf("1") }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        // null = шаг логина; не-null = ждём TOTP-код (промежуточный токен 2FA).
        var totpToken by remember { mutableStateOf<String?>(null) }
        var totpCode by remember { mutableStateOf("") }

        Surface(color = Color(0xFF0F172A), modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(Icons.Default.Shield, null, tint = Color(0xFF10B981), modifier = Modifier.size(56.dp))
                Spacer(Modifier.height(8.dp))
                Text("Security Video Conference", style = MaterialTheme.typography.titleLarge)
                Text("Native client · Android", color = Color(0xFF64748B))
                Spacer(Modifier.height(28.dp))

                if (totpToken == null) {
                    OutlinedTextField(server, { server = it }, label = { Text("Сервер") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(username, { username = it }, label = { Text("Логин") },
                        singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(password, { password = it }, label = { Text("Пароль") },
                        singleLine = true, visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(meetingId, { meetingId = it }, label = { Text("ID встречи") },
                        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth())
                } else {
                    Text("Двухфакторная аутентификация", style = MaterialTheme.typography.titleMedium)
                    Text("Введите 6-значный код из приложения-аутентификатора",
                        color = Color(0xFF64748B), style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(totpCode, { totpCode = it.filter(Char::isDigit).take(6) },
                        label = { Text("Код 2FA") }, singleLine = true,
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
                                    val api = SvcApi(server.trim().trimEnd('/'))
                                    when (val res = api.login(username.trim(), password)) {
                                        is SvcApi.LoginResult.Success ->
                                            JoinTarget(api, res.session)
                                        is SvcApi.LoginResult.TotpRequired -> {
                                            totpToken = res.totpToken
                                            null
                                        }
                                    }
                                }.onSuccess { target ->
                                    busy = false
                                    target?.let { joinAndGo(it, meetingId.trim()) { msg -> error = msg } }
                                }.onFailure {
                                    busy = false
                                    error = it.message ?: "Ошибка"
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF10B981)),
                        modifier = Modifier.fillMaxWidth().height(50.dp)
                    ) {
                        if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
                        else Text("Войти в звонок")
                    }
                } else {
                    Button(
                        enabled = !busy && totpCode.length == 6,
                        onClick = {
                            error = null
                            busy = true
                            lifecycleScope.launch {
                                runCatching {
                                    val api = SvcApi(server.trim().trimEnd('/'))
                                    val session = api.verifyTotp(totpToken!!, totpCode)
                                    JoinTarget(api, session)
                                }.onSuccess { target ->
                                    busy = false
                                    joinAndGo(target, meetingId.trim()) { msg -> error = msg }
                                }.onFailure {
                                    busy = false
                                    error = it.message ?: "Ошибка"
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF10B981)),
                        modifier = Modifier.fillMaxWidth().height(50.dp)
                    ) {
                        if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.dp)
                        else Text("Подтвердить код")
                    }
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = { totpToken = null; totpCode = ""; error = null }) {
                        Text("Назад", color = Color(0xFF64748B))
                    }
                }
            }
        }
    }

    private data class JoinTarget(val api: SvcApi, val session: SvcApi.Session)

    /** Подключается к встрече по сессии и открывает экран звонка. */
    private suspend fun joinAndGo(target: JoinTarget, meetingId: String, onError: (String) -> Unit) {
        runCatching { target.api.join(target.session.token, meetingId, currentGeo()) }
            .onSuccess { room ->
                startActivity(
                    Intent(this@MainActivity, CallActivity::class.java).apply {
                        putExtra("url", room.url)
                        putExtra("token", room.token)
                        putExtra("room", room.room)
                    }
                )
            }
            .onFailure { onError(it.message ?: "Ошибка") }
    }
}
