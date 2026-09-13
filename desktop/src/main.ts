import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { Room, RoomEvent, Track, type RemoteTrack, type Participant } from "livekit-client";
import { fetch as httpFetch } from "@tauri-apps/plugin-http";
import "./styles.css";

const app = document.querySelector<HTMLDivElement>("#app")!;

const state = {
  server: "http://localhost:4000",
  bearer: "",
  username: "",
  meetingId: "1",
  room: null as Room | null,
  platform: "linux",
  // Login ekraniga o'tkaziladigan xabar (masalan majlisdan chiqarilish sababi).
  notice: "",
};

// Rust tomonidan aniqlangan rekorder (recorder.rs → DetectedRecorder).
interface DetectedRecorder {
  name: string;
  process: string;
  pid: number;
  category: "recorder" | "remote_access";
}

interface RecorderAlert {
  platform: string;
  detections: DetectedRecorder[];
}

// ---------- Ekran himoyasi (Tauri Rust IPC) ----------
async function paintBadge(): Promise<void> {
  const dot = document.querySelector<HTMLSpanElement>("#secdot");
  const txt = document.querySelector<HTMLSpanElement>("#sectext");
  try {
    const info = await invoke<string>("security_status");
    const on = info.includes("enforced");
    if (dot) dot.className = "dot" + (on ? " on" : "");
    if (txt) txt.textContent = on ? "Ekran himoyasi: yoqilgan" : `Ekran himoyasi: ${info}`;
  } catch {
    if (txt) txt.textContent = "Ekran himoyasi: noma'lum";
  }
}

// ---------- Anti-capture: rekorder detektori (E5, S36) ----------
// Rust `recorder` moduli jarayonlarni skanerlaydi; bu yer aniqlanganini
// serverga yozadi va per-meeting siyosat javobini (none/warn/eject) qo'llaydi.
// D-013: bu DETECT qatlami — bloklash emas, kafolat bermaymiz.

function alertBanner(msg: string, kind: "warn" | "crit"): void {
  const box = document.querySelector<HTMLDivElement>("#capalert");
  if (!box) return;
  box.className = "capalert " + kind;
  box.textContent = msg;
}

/// Aniqlangan rekorderni serverga qayd etadi va reaksiyani qaytaradi.
async function reportRecorders(found: DetectedRecorder[]): Promise<void> {
  // Token yo'q bo'lsa yubora olmaymiz (login oldidan aniqlanganlar
  // majlisga kirishdagi qayta skanda baribir qayd etiladi).
  if (!state.bearer || found.length === 0) return;

  const names = [...new Set(found.map((d) => d.name))].join(", ");
  const body: Record<string, unknown> = {
    kind: "recorder_detected",
    platform: state.platform,
    severity: "warning",
    detail: {
      processes: found.map((d) => ({ name: d.name, process: d.process, pid: d.pid, category: d.category })),
    },
  };
  if (state.room) body.meeting_id = Number(state.meetingId);

  try {
    const r = await httpFetch(`${state.server}/api/capture-events`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${state.bearer}` },
      body: JSON.stringify(body),
    });
    const data = await r.json().catch(() => ({}));
    applyReaction(String(data.reaction ?? "none"), names);
  } catch (e) {
    // Tarmoq xatosi qo'ng'iroqni buzmasin — foydalanuvchini baribir ogohlantiramiz.
    console.error(e);
    alertBanner(`⚠️ Ekran yozib olish aniqlandi: ${names}. Serverga qayd etilmadi.`, "warn");
  }
}

function applyReaction(reaction: string, names: string): void {
  if (reaction === "eject") {
    // Server LiveKit'dan allaqachon chiqarib yubordi — mahalliy holatni tozalaymiz.
    const msg = `⛔ Ekran yozib olish aniqlandi (${names}). Majlisdan chiqarildingiz.`;
    alertBanner(msg, "crit");
    // `disconnect()` → RoomEvent.Disconnected → renderLogin(), ya'ni banner
    // yo'qoladi. Sababni login ekraniga o'tkazamiz, aks holda foydalanuvchi
    // nega chiqarilganini bilmay qoladi.
    state.notice = msg;
    void state.room?.disconnect();
    return;
  }
  const suffix = reaction === "warn" ? " Tashkilotchi xabardor qilindi." : "";
  alertBanner(`⚠️ Ekran yozib olish dasturi aniqlandi: ${names}. Hodisa qayd etildi.${suffix}`, "warn");
}

/// Fon kuzatuvchisi — majlis davomida ishga tushirilgan rekorderni tutadi.
/// Bir marta o'rnatiladi; Rust tomoni faqat YANGI aniqlanganlarni yuboradi.
async function watchRecorders(): Promise<void> {
  try {
    state.platform = await invoke<string>("client_platform");
  } catch {
    /* platform aniqlanmasa, standart "linux" qoladi */
  }
  await listen<RecorderAlert>("recorder-detected", (event) => {
    void reportRecorders(event.payload.detections ?? []);
  });
}

/// Majlisga kirishdan oldingi skan — ilova ishga tushishidan OLDIN ochilgan
/// rekorderni tutadi (fon kuzatuvchisi uni login'gacha "ko'rilgan" deb belgilagan).
async function scanBeforeJoin(): Promise<void> {
  try {
    await reportRecorders(await invoke<DetectedRecorder[]>("detect_recorders"));
  } catch (e) {
    console.error(e);
  }
}

function authShell(inner: string): string {
  return `<div class="center"><div class="card">
    <div class="brand"><span class="logo">S</span><b>SVC</b></div>
    ${inner}
    <div class="secbadge"><span class="dot" id="secdot"></span><span id="sectext">…</span></div>
  </div></div>`;
}

function status(msg: string, kind = ""): void {
  const s = document.querySelector<HTMLDivElement>("#status");
  if (s) { s.textContent = msg; s.className = "status " + kind; }
}

// ---------- Login ----------
function renderLogin(): void {
  app.innerHTML = authShell(`
    <h1>Tizimga kirish</h1>
    <div class="sub">Xavfsiz video-konferensiya · desktop</div>
    <label>Server</label>
    <input id="server" value="${state.server}" spellcheck="false" />
    <label>Login</label>
    <input id="username" value="admin" autocomplete="username" spellcheck="false" />
    <label>Parol</label>
    <input id="password" type="password" autocomplete="current-password" />
    <label>Majlis ID</label>
    <input id="meeting" value="${state.meetingId}" spellcheck="false" />
    <button class="primary" id="loginBtn">Kirish va qo'shilish →</button>
    <div class="status" id="status"></div>
  `);
  void paintBadge();
  if (state.notice) {
    status(state.notice, "err");
    state.notice = "";
  }
  const go = () => void doLogin();
  document.querySelector<HTMLButtonElement>("#loginBtn")!.addEventListener("click", go);
  document.querySelector<HTMLInputElement>("#password")!.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter") go();
  });
}

async function doLogin(): Promise<void> {
  const server = document.querySelector<HTMLInputElement>("#server")!.value.trim().replace(/\/$/, "");
  const username = document.querySelector<HTMLInputElement>("#username")!.value.trim();
  const password = document.querySelector<HTMLInputElement>("#password")!.value;
  state.server = server;
  state.username = username;
  state.meetingId = document.querySelector<HTMLInputElement>("#meeting")!.value.trim() || "1";
  if (!username || !password) { status("Login va parolni kiriting", "err"); return; }

  status("Ulanmoqda…");
  try {
    const r = await httpFetch(`${server}/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    const data = await r.json();
    if (!r.ok) { status(data.error ? `Xato: ${data.error}` : `Kirish xatosi (${r.status})`, "err"); return; }
    if (data.totp_required) { renderTotp(data.totp_token as string); return; }
    if (typeof data.token === "string") { state.bearer = data.token; await joinMeeting(); return; }
    status("Kutilmagan javob", "err");
  } catch (e) {
    status("Serverga ulanib bo'lmadi. Backend ishlayaptimi?", "err");
    console.error(e);
  }
}

function renderTotp(totpToken: string): void {
  app.innerHTML = authShell(`
    <h1>Ikki bosqichli tasdiqlash</h1>
    <div class="sub">6 xonali kodni kiriting</div>
    <label>TOTP kod</label>
    <input id="code" inputmode="numeric" maxlength="6" placeholder="000000" />
    <button class="primary" id="verifyBtn">Tasdiqlash →</button>
    <div class="status" id="status"></div>
  `);
  void paintBadge();
  document.querySelector<HTMLButtonElement>("#verifyBtn")!.addEventListener("click", async () => {
    const code = document.querySelector<HTMLInputElement>("#code")!.value.trim();
    status("Tekshirilmoqda…");
    try {
      const r = await httpFetch(`${state.server}/api/login/totp`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ totp_token: totpToken, code }),
      });
      const data = await r.json();
      if (!r.ok) { status("Kod noto'g'ri yoki muddati o'tgan", "err"); return; }
      if (typeof data.token === "string") { state.bearer = data.token; await joinMeeting(); }
    } catch { status("Serverga ulanib bo'lmadi", "err"); }
  });
}

// ---------- Join → LiveKit ----------
async function joinMeeting(): Promise<void> {
  status("Majlisga ulanmoqda…");
  try {
    const r = await httpFetch(`${state.server}/api/meetings/${state.meetingId}/join`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${state.bearer}` },
      body: JSON.stringify({}),
    });
    const data = await r.json();
    if (!r.ok) { status(data.error ? `Xato: ${data.error}` : `Ulanish xatosi (${r.status})`, "err"); return; }
    await connectLiveKit(data.url as string, data.token as string, data.room as string);
  } catch {
    status("Majlisga ulanib bo'lmadi", "err");
  }
}

async function connectLiveKit(url: string, token: string, roomName: string): Promise<void> {
  const room = new Room({ adaptiveStream: true, dynacast: true });
  state.room = room;
  renderCall(roomName);

  room.on(RoomEvent.TrackSubscribed, (track, _pub, participant) => addRemoteTrack(track, participant));
  room.on(RoomEvent.TrackUnsubscribed, (track) => track.detach().forEach((el) => el.remove()));
  room.on(RoomEvent.ParticipantDisconnected, (p) => removeTile(p.identity));
  room.on(RoomEvent.Disconnected, () => renderLogin());

  try {
    await room.connect(url, token);
    await room.localParticipant.setMicrophoneEnabled(true);
    await room.localParticipant.setCameraEnabled(true);
    renderLocalTile(room);
    // E5: majlis kontekstida allaqachon ochiq rekorderlarni qayd etamiz.
    void scanBeforeJoin();
  } catch (e) {
    console.error(e);
    const grid = document.querySelector("#grid");
    if (grid) grid.innerHTML = `<div class="tile"><div class="ph">Kamera yoki ulanish xatosi.<br>${String(e)}</div></div>`;
  }
}

function tileId(identity: string): string { return "tile-" + identity.replace(/[^a-zA-Z0-9_-]/g, ""); }

function ensureTile(identity: string, label: string): HTMLElement {
  const grid = document.querySelector<HTMLDivElement>("#grid")!;
  let tile = document.getElementById(tileId(identity));
  if (!tile) {
    tile = document.createElement("div");
    tile.className = "tile";
    tile.id = tileId(identity);
    tile.innerHTML = `<div class="ph">${label}</div><div class="wm"></div><div class="name">${label}</div>`;
    fillWatermark(tile.querySelector<HTMLDivElement>(".wm")!);
    grid.appendChild(tile);
  }
  return tile;
}

function addRemoteTrack(track: RemoteTrack, participant: Participant): void {
  const tile = ensureTile(participant.identity, participant.name || participant.identity);
  if (track.kind === Track.Kind.Video) {
    const el = track.attach();
    tile.querySelector(".ph")?.remove();
    tile.insertBefore(el, tile.firstChild);
  } else if (track.kind === Track.Kind.Audio) {
    track.attach();
  }
}

function renderLocalTile(room: Room): void {
  const tile = ensureTile("local", (state.username || "Siz") + " (siz)");
  const pub = Array.from(room.localParticipant.videoTrackPublications.values())[0];
  if (pub?.track) {
    const el = pub.track.attach();
    el.muted = true;
    // Kamera sizni qarama-qarshi tomondan ko'radi, shuning uchun xom tasvir
    // ko'zgudagi aksga teskari bo'lib, foydalanuvchiga g'alati tuyuladi.
    // Faqat O'Z tasvirimizni ko'zgu qilamiz — boshqa ishtirokchilarni hech qachon
    // (ularni teskari ko'rsatish yozuvlarni o'qib bo'lmas holga keltiradi).
    el.classList.add("mirror");
    tile.querySelector(".ph")?.remove();
    tile.insertBefore(el, tile.firstChild);
  }
}

function removeTile(identity: string): void {
  document.getElementById(tileId(identity))?.remove();
}

// E5/D-013: har plitkada foydalanuvchi izi (forensik watermark)
function fillWatermark(el: HTMLDivElement): void {
  const label = `${state.username || "user"} · ${new Date().toISOString().slice(0, 16)}`;
  let html = "";
  for (let y = 0; y < 6; y++) {
    for (let x = 0; x < 3; x++) {
      html += `<span style="top:${y * 18}%;left:${x * 40}%">${label}</span>`;
    }
  }
  el.innerHTML = html;
}

// ---------- Yordamchi (S39, D-019) ----------
// Web va Android bilan bir xil /api/assistant/* kontrakti: javoblar serverdagi yagona
// bilimlar bazasidan keladi, klientda matn saqlanmaydi.

interface AssistEntry { id: string; question: string; answer: string }

const assistLocale: "uz" | "ru" | "en" = (() => {
  const lang = (navigator.language || "uz").slice(0, 2);
  return lang === "ru" || lang === "en" ? lang : "uz";
})();

const ASSIST_T = {
  uz: {
    title: "Yordamchi",
    greeting: "Assalomu alaykum! Tizimdan qanday foydalanishni so'rang yoki mavzuni tanlang:",
    placeholder: "Savolingizni yozing…",
    thinking: "Qidirilmoqda…",
    unsure: "Aniq tushunmadim. Quyidagilardan birini nazarda tutdingizmi?",
    noMatch: "Buni tushunmadim. Mana nimalar bo'yicha yordam bera olaman:",
    restricted: "Bu amalni bajarish huquqi sizda yo'q. U quyidagi rollar uchun:",
    error: "Javob olinmadi. Internet aloqasini tekshiring.",
  },
  ru: {
    title: "Помощник",
    greeting: "Здравствуйте! Спросите, как пользоваться системой, или выберите тему:",
    placeholder: "Ваш вопрос…",
    thinking: "Ищу ответ…",
    unsure: "Не совсем понял. Вы имели в виду одно из этого?",
    noMatch: "Не понял вопрос. Вот с чем я могу помочь:",
    restricted: "У вас нет прав на это действие. Оно доступно ролям:",
    error: "Не удалось получить ответ. Проверьте подключение к интернету.",
  },
  en: {
    title: "Assistant",
    greeting: "Hello! Ask how to use the system, or pick a topic:",
    placeholder: "Your question…",
    thinking: "Searching…",
    unsure: "I'm not sure what you meant. Was it one of these?",
    noMatch: "I didn't understand. Here is what I can help with:",
    restricted: "You don't have permission for this action. It is available to:",
    error: "Couldn't get an answer. Check your internet connection.",
  },
}[assistLocale];

// Har bir qo'ng'iroq ekrani yangi bo'sh jurnal bilan chiziladi — takliflar ham qaytadan olinadi.
let assistLoaded = false;

// Tarmoq xatosi qo'ng'iroqni buzmasin: yordamchi ikkinchi darajali.
async function assistRequest(path: string, init: { method?: string; body?: string } = {}): Promise<any | null> {
  try {
    const r = await httpFetch(`${state.server}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${state.bearer}` },
    });
    return r.ok ? await r.json() : null;
  } catch (e) {
    console.error(e);
    return null;
  }
}

function assistBubble(text: string, mine = false, muted = false): HTMLElement {
  const log = document.querySelector<HTMLDivElement>("#assistLog")!;
  const el = document.createElement("div");
  el.className = "ab" + (mine ? " mine" : "") + (muted ? " muted" : "");
  el.textContent = text;
  log.appendChild(el);
  log.scrollTop = log.scrollHeight;
  return el;
}

function assistChips(entries: AssistEntry[] | undefined): void {
  if (!entries || entries.length === 0) return;
  const log = document.querySelector<HTMLDivElement>("#assistLog")!;
  const box = document.createElement("div");
  box.className = "achips";
  for (const entry of entries) {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = entry.question;
    b.onclick = () => { box.remove(); void assistOpen(entry); };
    box.appendChild(b);
  }
  log.appendChild(box);
  log.scrollTop = log.scrollHeight;
}

async function assistAsk(question: string): Promise<void> {
  assistBubble(question, true);
  const wait = assistBubble(ASSIST_T.thinking, false, true);
  const data = await assistRequest("/api/assistant/ask", {
    method: "POST",
    body: JSON.stringify({ question, locale: assistLocale }),
  });
  wait.remove();
  if (!data) { assistBubble(ASSIST_T.error); return; }

  if (data.status === "ok") {
    assistBubble(data.answer.answer);
    assistChips(data.related);
  } else if (data.status === "unsure") {
    assistBubble(ASSIST_T.unsure);
    assistChips(data.candidates);
  } else if (data.status === "restricted") {
    // Eski server `allowed_role_labels` bermasa — xom rol nomlari, bo'sh qolmasin.
    const roles: string[] = data.allowed_role_labels ?? data.allowed_roles ?? [];
    assistBubble(`${ASSIST_T.restricted} ${roles.join(", ")}`);
  } else {
    assistBubble(ASSIST_T.noMatch);
    assistChips(data.suggestions);
  }
}

// Taklif bosilganda javob id bo'yicha olinadi — o'z savolini qidiruvdan qayta o'tkazish shart emas.
async function assistOpen(entry: AssistEntry): Promise<void> {
  assistBubble(entry.question, true);
  const data = await assistRequest(`/api/assistant/${encodeURIComponent(entry.id)}?locale=${assistLocale}`);
  assistBubble(data ? data.answer.answer : ASSIST_T.error);
}

async function assistToggle(): Promise<void> {
  const panel = document.querySelector<HTMLElement>("#assist")!;
  panel.hidden = !panel.hidden;
  document.querySelector("#assistBtn")!.classList.toggle("on", !panel.hidden);
  if (panel.hidden) return;
  document.querySelector<HTMLInputElement>("#assistInput")!.focus();

  // Takliflar birinchi ochilishda bir marta olinadi — ungacha panel hech kimga kerak emas.
  if (assistLoaded) return;
  assistLoaded = true;
  assistBubble(ASSIST_T.greeting);
  const data = await assistRequest(`/api/assistant/suggestions?locale=${assistLocale}`);
  if (data) assistChips(data.suggestions); else assistBubble(ASSIST_T.error);
}

function renderCall(roomName: string): void {
  app.innerHTML = `
    <div class="call">
      <div class="call-head">
        <div class="rn">SVC — majlis<small>${roomName}</small></div>
        <span class="pill">🔒 Himoyalangan kanal (DTLS-SRTP)</span>
      </div>
      <div class="capalert" id="capalert"></div>
      <div class="grid" id="grid"></div>
      <div class="controls">
        <button class="ctrl" id="micBtn" title="Mikrofon">🎙️</button>
        <button class="ctrl" id="camBtn" title="Kamera">🎥</button>
        <button class="ctrl" id="assistBtn" title="${ASSIST_T.title}">💬</button>
        <button class="ctrl leave" id="leaveBtn">Chiqish</button>
      </div>
      <section class="assist" id="assist" hidden>
        <header>💬 ${ASSIST_T.title}</header>
        <div class="alog" id="assistLog"></div>
        <form id="assistForm">
          <input id="assistInput" type="text" autocomplete="off" placeholder="${ASSIST_T.placeholder}" />
          <button type="submit" aria-label="${ASSIST_T.title}">➤</button>
        </form>
      </section>
    </div>`;

  assistLoaded = false;

  document.querySelector<HTMLButtonElement>("#micBtn")!.addEventListener("click", async () => {
    const lp = state.room?.localParticipant; if (!lp) return;
    const on = !lp.isMicrophoneEnabled;
    await lp.setMicrophoneEnabled(on);
    document.querySelector("#micBtn")!.classList.toggle("off", !on);
  });
  document.querySelector<HTMLButtonElement>("#camBtn")!.addEventListener("click", async () => {
    const lp = state.room?.localParticipant; if (!lp) return;
    const on = !lp.isCameraEnabled;
    await lp.setCameraEnabled(on);
    document.querySelector("#camBtn")!.classList.toggle("off", !on);
    if (on && state.room) renderLocalTile(state.room);
  });
  document.querySelector<HTMLButtonElement>("#assistBtn")!.addEventListener("click", () => void assistToggle());
  document.querySelector<HTMLFormElement>("#assistForm")!.addEventListener("submit", (e) => {
    e.preventDefault();
    const input = document.querySelector<HTMLInputElement>("#assistInput")!;
    const question = input.value.trim();
    if (question) { input.value = ""; void assistAsk(question); }
  });
  document.querySelector<HTMLButtonElement>("#leaveBtn")!.addEventListener("click", async () => {
    await state.room?.disconnect();
    state.room = null;
    renderLogin();
  });
}

renderLogin();
void watchRecorders();
