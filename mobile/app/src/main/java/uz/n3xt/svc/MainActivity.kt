package uz.n3xt.svc

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { LoginScreen() } }
    }

    @Composable
    private fun LoginScreen() {
        var server by remember { mutableStateOf("http://10.0.2.2:4000") }
        var username by remember { mutableStateOf("admin") }
        var password by remember { mutableStateOf("AdminPass12345") }
        var meetingId by remember { mutableStateOf("1") }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }

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

                error?.let {
                    Spacer(Modifier.height(12.dp))
                    Text(it, color = MaterialTheme.colorScheme.error)
                }

                Spacer(Modifier.height(24.dp))
                Button(
                    enabled = !busy,
                    onClick = {
                        error = null
                        busy = true
                        lifecycleScope.launch {
                            runCatching {
                                val api = SvcApi(server.trim().trimEnd('/'))
                                val session = api.login(username.trim(), password)
                                api.join(session.token, meetingId.trim())
                            }.onSuccess { room ->
                                busy = false
                                startActivity(
                                    Intent(this@MainActivity, CallActivity::class.java).apply {
                                        putExtra("url", room.url)
                                        putExtra("token", room.token)
                                        putExtra("room", room.room)
                                    }
                                )
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
            }
        }
    }
}
