import { invoke } from "@tauri-apps/api/core";
import "./styles.css";

// Backend javob turlari (bearer-auth API: /api/login, /api/login/totp)
interface LoginOk {
  token: string;
}
interface TotpRequired {
  totp_required: true;
  totp_token: string;
}
type LoginResp = Partial<LoginOk & TotpRequired> & Record<string, unknown>;

const app = document.querySelector<HTMLDivElement>("#app")!;

const state = {
  server: "http://localhost:4000",
  bearer: "" as string,
};

function shell(inner: string): string {
  return `
    <div class="card">
      <div class="brand">
        <span class="logo">S</span>
        <b>SVC</b>
      </div>
      ${inner}
      <div class="secbadge" id="secbadge">
        <span class="dot" id="secdot"></span>
        <span id="sectext">Ekran himoyasi tekshirilmoqda…</span>
      </div>
    </div>`;
}

function renderLogin(): void {
  app.innerHTML = shell(`
    <h1>Tizimga kirish</h1>
    <div class="sub">Xavfsiz video-konferensiya · desktop</div>
    <label>Server</label>
    <input id="server" type="text" value="${state.server}" spellcheck="false" />
    <label>Email</label>
    <input id="email" type="email" placeholder="admin" autocomplete="username" spellcheck="false" />
    <label>Parol</label>
    <input id="password" type="password" autocomplete="current-password" />
    <button class="primary" id="loginBtn">Kirish →</button>
    <div class="status" id="status"></div>
  `);
  refreshSecurityBadge();

  const btn = document.querySelector<HTMLButtonElement>("#loginBtn")!;
  btn.addEventListener("click", () => void doLogin());
  app.querySelector("#password")!.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter") void doLogin();
  });
}

function setStatus(msg: string, kind: "" | "err" | "ok" = ""): void {
  const s = document.querySelector<HTMLDivElement>("#status");
  if (s) { s.textContent = msg; s.className = "status " + kind; }
}

async function doLogin(): Promise<void> {
  const server = (document.querySelector<HTMLInputElement>("#server")!).value.trim().replace(/\/$/, "");
  const email = (document.querySelector<HTMLInputElement>("#email")!).value.trim();
  const password = (document.querySelector<HTMLInputElement>("#password")!).value;
  state.server = server;
  if (!email || !password) { setStatus("Email va parolni kiriting", "err"); return; }

  setStatus("Ulanmoqda…");
  try {
    const r = await fetch(`${server}/api/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    if (!r.ok) { setStatus(`Kirish xatosi (${r.status})`, "err"); return; }
    const data = (await r.json()) as LoginResp;

    if (data.totp_required && typeof data.totp_token === "string") {
      renderTotp(data.totp_token);
      return;
    }
    if (typeof data.token === "string") {
      state.bearer = data.token;
      renderConnected(email);
      return;
    }
    setStatus("Kutilmagan javob", "err");
  } catch (err) {
    setStatus("Serverga ulanib bo'lmadi. Ishlayaptimi?", "err");
    console.error(err);
  }
}

function renderTotp(totpToken: string): void {
  app.innerHTML = shell(`
    <h1>Ikki bosqichli tasdiqlash</h1>
    <div class="sub">Ilovadagi 6 xonali kodni kiriting</div>
    <label>TOTP kod</label>
    <input id="code" type="text" inputmode="numeric" maxlength="6" placeholder="000000" />
    <button class="primary" id="verifyBtn">Tasdiqlash →</button>
    <div class="status" id="status"></div>
  `);
  refreshSecurityBadge();
  document.querySelector<HTMLButtonElement>("#verifyBtn")!.addEventListener("click", async () => {
    const code = (document.querySelector<HTMLInputElement>("#code")!).value.trim();
    setStatus("Tekshirilmoqda…");
    try {
      const r = await fetch(`${state.server}/api/login/totp`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ totp_token: totpToken, code }),
      });
      if (!r.ok) { setStatus("Kod noto'g'ri yoki muddati o'tgan", "err"); return; }
      const data = (await r.json()) as LoginResp;
      if (typeof data.token === "string") { state.bearer = data.token; renderConnected(""); }
      else setStatus("Kutilmagan javob", "err");
    } catch { setStatus("Serverga ulanib bo'lmadi", "err"); }
  });
}

function renderConnected(email: string): void {
  app.innerHTML = shell(`
    <h1>Ulandingiz ✓</h1>
    <div class="sub">${email || "Foydalanuvchi"} · bearer olindi</div>
    <div class="status ok">Keyingi qadam: majlisga qo'shilish (LiveKit) — tez orada.</div>
  `);
  refreshSecurityBadge();
}

// Tauri Rust buyrug'i orqali ekran-himoya holati (E5, D-013)
async function refreshSecurityBadge(): Promise<void> {
  const dot = document.querySelector<HTMLSpanElement>("#secdot");
  const txt = document.querySelector<HTMLSpanElement>("#sectext");
  if (!dot || !txt) return;
  try {
    const info = await invoke<string>("security_status");
    const enforced = info.includes("enforced");
    dot.className = "dot" + (enforced ? " on" : "");
    txt.textContent = enforced
      ? "Ekran himoyasi: yoqilgan"
      : `Ekran himoyasi: ${info}`;
  } catch {
    txt.textContent = "Ekran himoyasi: noma'lum";
  }
}

renderLogin();
