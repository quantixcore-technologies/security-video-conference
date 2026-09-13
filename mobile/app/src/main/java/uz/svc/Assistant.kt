package uz.svc

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import java.util.Locale

// Ilova ichidagi yordamchi (S39, D-019). Web va Tauri bilan bir xil /api/assistant/…
// kontrakti: javoblar serverdagi yagona bilimlar bazasidan keladi, ilovada matn
// saqlanmaydi — aks holda bazadagi har bir tuzatish uchun yangi APK chiqarish kerak bo'lardi.
// Bu yerda blok izoh yozilmasin: Kotlin'da izohlar ichma-ich, yo'ldagi "/*" yangi izoh ochadi.

private sealed class Bubble {
    data class Mine(val text: String) : Bubble()
    data class Bot(val text: String, val muted: Boolean = false) : Bubble()
    data class Chips(val entries: List<SvcApi.AssistantEntry>) : Bubble()
}

private data class AssistantStrings(
    val title: String,
    val subtitle: String,
    val greeting: String,
    val placeholder: String,
    val send: String,
    val thinking: String,
    val unsure: String,
    val noMatch: String,
    val restricted: String,
    val error: String
)

/** Qurilma tili: server qo'llaydigan uchtasidan biri, aks holda o'zbekcha. */
private fun assistantLocale(): String = when (Locale.getDefault().language) {
    "ru" -> "ru"
    "en" -> "en"
    else -> "uz"
}

private fun assistantStrings(locale: String): AssistantStrings = when (locale) {
    "ru" -> AssistantStrings(
        title = "Помощник",
        subtitle = "Вопросы о работе с системой",
        greeting = "Здравствуйте! Спросите, как пользоваться системой, или выберите тему:",
        placeholder = "Ваш вопрос…",
        send = "Отправить",
        thinking = "Ищу ответ…",
        unsure = "Не совсем понял. Вы имели в виду одно из этого?",
        noMatch = "Не понял вопрос. Вот с чем я могу помочь:",
        restricted = "У вас нет прав на это действие. Оно доступно ролям:",
        error = "Не удалось получить ответ. Проверьте подключение к интернету."
    )
    "en" -> AssistantStrings(
        title = "Assistant",
        subtitle = "Questions about using the system",
        greeting = "Hello! Ask how to use the system, or pick a topic:",
        placeholder = "Your question…",
        send = "Send",
        thinking = "Searching…",
        unsure = "I'm not sure what you meant. Was it one of these?",
        noMatch = "I didn't understand. Here is what I can help with:",
        restricted = "You don't have permission for this action. It is available to:",
        error = "Couldn't get an answer. Check your internet connection."
    )
    else -> AssistantStrings(
        title = "Yordamchi",
        subtitle = "Tizimdan foydalanish bo'yicha savollar",
        greeting = "Assalomu alaykum! Tizimdan qanday foydalanishni so'rang yoki mavzuni tanlang:",
        placeholder = "Savolingizni yozing…",
        send = "Yuborish",
        thinking = "Qidirilmoqda…",
        unsure = "Aniq tushunmadim. Quyidagilardan birini nazarda tutdingizmi?",
        noMatch = "Buni tushunmadim. Mana nimalar bo'yicha yordam bera olaman:",
        restricted = "Bu amalni bajarish huquqi sizda yo'q. U quyidagi rollar uchun:",
        error = "Javob olinmadi. Internet aloqasini tekshiring."
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssistantSheet(
    api: SvcApi,
    token: String,
    accent: Color,
    panel: Color,
    muted: Color,
    onDismiss: () -> Unit
) {
    val locale = remember { assistantLocale() }
    val t = remember(locale) { assistantStrings(locale) }
    val bubbles = remember { mutableStateListOf<Bubble>() }
    var input by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    // Takliflar varaq ochilganda bir marta olinadi — ungacha tarmoqqa murojaat yo'q.
    LaunchedEffect(Unit) {
        bubbles.add(Bubble.Bot(t.greeting))
        runCatching { api.assistantSuggestions(token, locale) }
            .onSuccess { if (it.isNotEmpty()) bubbles.add(Bubble.Chips(it)) }
            .onFailure { bubbles.add(Bubble.Bot(t.error)) }
    }

    LaunchedEffect(bubbles.size, busy) {
        val last = bubbles.lastIndex + if (busy) 1 else 0
        if (last >= 0) listState.animateScrollToItem(last)
    }

    fun ask(question: String) {
        if (question.isBlank() || busy) return
        bubbles.add(Bubble.Mine(question))
        busy = true
        scope.launch {
            runCatching { api.assistantAsk(token, question, locale) }
                .onSuccess { reply ->
                    when (reply) {
                        is SvcApi.AssistantReply.Answer -> {
                            bubbles.add(Bubble.Bot(reply.entry.answer))
                            if (reply.related.isNotEmpty()) bubbles.add(Bubble.Chips(reply.related))
                        }
                        is SvcApi.AssistantReply.Unsure -> {
                            bubbles.add(Bubble.Bot(t.unsure))
                            bubbles.add(Bubble.Chips(reply.candidates))
                        }
                        is SvcApi.AssistantReply.Restricted ->
                            bubbles.add(Bubble.Bot("${t.restricted} ${reply.roleLabels.joinToString(", ")}"))
                        is SvcApi.AssistantReply.NoMatch -> {
                            bubbles.add(Bubble.Bot(t.noMatch))
                            if (reply.suggestions.isNotEmpty()) bubbles.add(Bubble.Chips(reply.suggestions))
                        }
                    }
                }
                .onFailure { bubbles.add(Bubble.Bot(t.error)) }
            busy = false
        }
    }

    // Taklif bosilganda javob id bo'yicha olinadi — yordamchining o'z savolini
    // qidiruvdan qayta o'tkazish shart emas.
    fun open(entry: SvcApi.AssistantEntry) {
        if (busy) return
        bubbles.add(Bubble.Mine(entry.question))
        busy = true
        scope.launch {
            runCatching { api.assistantEntry(token, entry.id, locale) }
                .onSuccess { bubbles.add(Bubble.Bot(it.answer)) }
                .onFailure { bubbles.add(Bubble.Bot(t.error)) }
            busy = false
        }
    }

    // Chat varag'i darhol to'liq ochilsin: yarim holatda kiritish maydoni ekran pastidan
    // tashqarida qoladi va foydalanuvchi qayerga yozishni ko'rmaydi (emulyatorda ushlangan).
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = panel) {
        Column(
            Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.85f)
                .padding(horizontal = 16.dp)
                // Klaviatura ochilganda kiritish qatori uning ostida qolmasin.
                .imePadding()
        ) {
            Text(t.title, color = Color.White, style = MaterialTheme.typography.titleMedium)
            Text(t.subtitle, color = muted, style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(10.dp))

            LazyColumn(
                Modifier.weight(1f),
                state = listState,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(bubbles) { bubble -> BubbleView(bubble, accent, muted, onChip = { open(it) }) }
                if (busy) {
                    item { Text(t.thinking, color = muted, fontStyle = FontStyle.Italic, fontSize = 13.sp) }
                }
            }

            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    placeholder = { Text(t.placeholder) }
                )
                IconButton(onClick = { ask(input.trim()); input = "" }, enabled = !busy) {
                    Icon(Icons.AutoMirrored.Filled.Send, t.send, tint = accent)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BubbleView(
    bubble: Bubble,
    accent: Color,
    muted: Color,
    onChip: (SvcApi.AssistantEntry) -> Unit
) {
    val shape = RoundedCornerShape(14.dp)
    when (bubble) {
        is Bubble.Mine -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Text(
                bubble.text,
                color = Color.White,
                modifier = Modifier
                    .background(accent.copy(alpha = 0.85f), shape)
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            )
        }
        is Bubble.Bot -> Text(
            bubble.text,
            color = if (bubble.muted) muted else Color.White,
            modifier = Modifier
                .background(Color.White.copy(alpha = 0.06f), shape)
                .padding(horizontal = 12.dp, vertical = 8.dp)
        )
        is Bubble.Chips -> FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            bubble.entries.forEach { entry ->
                AssistChip(onClick = { onChip(entry) }, label = { Text(entry.question, fontSize = 12.sp) })
            }
        }
    }
}
