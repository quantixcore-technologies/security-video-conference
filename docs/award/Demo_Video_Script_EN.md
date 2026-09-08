# SVC — Demo Video Script (President Tech Award)

**Length:** ~2:30–3:00 · **Language:** English (voiceover or on-screen subtitles) · **Format:** screen recording + narration
**Goal:** show the jury a real, working product — problem → solution → live demo → team.

> **How to record:** OBS Studio (or any screen recorder) for the web panel; Android emulator / phone screen-record for the app.
> **Voice:** either record an English voiceover reading the lines below, **or** add them as on-screen subtitles / captions. Keep it calm and confident.
> **Resolution:** 1920×1080, 30 fps. Cut out loading pauses in editing.

---

## 🎬 Shot list (scene by scene)

### Scene 1 — Opening hook · 0:00–0:15
**On screen:** SVC logo / title card (use slide 1 of `Presentation_SVC_EN.html`, fullscreen). Optional: Zoom & Meet logos with a red ✗ over them.
**On-screen text:** `SVC — Security Video Conference`
**Voiceover (EN):**
> "Today, government bodies and enterprises hold confidential meetings on Zoom or Google Meet — where the data lives on foreign servers. For state secrets, that's a risk. SVC solves it."

---

### Scene 2 — The product is live (web) · 0:15–0:35
**On screen:** Browser → open **`https://svc.co1nlist.uz`** (landing page). Scroll slowly through features and the "Download the app" section.
**On-screen text:** `Live at svc.co1nlist.uz`
**Voiceover (EN):**
> "SVC is not just an idea — it's already deployed and running. A fully self-hosted, encrypted platform for secure video and document exchange, entirely under the organization's own control."

---

### Scene 3 — Web admin panel: sign in · 0:35–0:50
**On screen:** Go to **`https://admin.co1nlist.uz`** → login form. Type username **`shuxrat`**, password, click **"Sign in"** → dashboard appears.
**On-screen text:** `Web admin panel · role-based access`
**Voiceover (EN):**
> "This is the administrative panel. Access is strictly role-based — there is no self-registration. Only an administrator can add users and assign roles."

---

### Scene 4 — Staff & roles (RBAC) · 0:50–1:05
**On screen:** Click **"Employees / Сотрудники"** in the left menu. Show the staff list with different roles (Super Admin, Manager, Employee, Security Officer).
**On-screen text:** `Super Admin · Manager · Employee · Security Officer`
**Voiceover (EN):**
> "Every user has a clear role. Super-administrators register staff and assign roles. Managers run meetings. The hierarchy is enforced across the whole system."

---

### Scene 5 — Create a meeting + privacy · 1:05–1:30
**On screen:**
1. Click **"Meetings / Встречи"** → **"+ Meeting"** (top-right).
2. Enter a title, e.g. `Board meeting`, tick a couple of participants, click **Create**.
3. The new meeting appears in the list.
4. (Optional, strong) Sign out, log in as another manager who was NOT invited → open Meetings → **that meeting is not visible.**
**On-screen text:** `Meetings are private — visible only to organizer + invited members`
**Voiceover (EN):**
> "A manager creates a meeting and invites participants. Meetings are confidential by design: even another manager — or a super-admin — cannot see a meeting they were not invited to. Privacy is built in."

---

### Scene 6 — Native Android app: landing & login · 1:30–1:50
**On screen:** Switch to the Android app (emulator or phone). Open the app → **landing screen** (brand, features, profile icon top-right). Tap the **profile icon** → login screen → sign in as **`aziz`**.
**On-screen text:** `Native Android app — no server or IP shown to the user`
**Voiceover (EN):**
> "The same platform ships as a native Android app. It opens on a clean branded screen — no server address, no technical fields. The user simply signs in through the profile icon."

---

### Scene 7 — App: meetings, create, department · 1:50–2:15
**On screen:** After login, show the bottom navigation and walk through:
1. **Meetings** tab — the user's meetings list; tap **"+ Meeting"** (managers only) to show in-app meeting creation with participant selection.
2. **Department** tab — colleagues in the user's department.
3. **Messages** tab — notifications (meeting invites, orders) with the unread badge.
4. **Profile** tab — name, role, department, organization.
**On-screen text:** `Meetings · Messages · Department · Profile`
**Voiceover (EN):**
> "Inside the app: your meetings, one-tap join, and — for managers — creating meetings and inviting staff right from the phone. A messages feed delivers meeting invitations and official orders, and each user has their own profile."

---

### Scene 8 — Security in action · 2:15–2:35
**On screen:** Two quick beats:
1. In a call/secure screen, try to take a screenshot → it's **blocked / black** (Android FLAG_SECURE). Show the "can't capture" result.
2. Cut to slide 10 of the presentation (Security) OR the audit view.
**On-screen text:** `Screenshots & screen-recording blocked · immutable audit`
**Voiceover (EN):**
> "Security is enforced on the device: screenshots and screen-recording are blocked inside secure screens. Media is encrypted in transit, and every sensitive action is written to an immutable audit log."

---

### Scene 9 — Architecture & honesty · 2:35–2:50
**On screen:** Slide 12 (Architecture) or slide 13 (Stack) of the presentation, fullscreen.
**On-screen text:** `Elixir/Phoenix · LiveKit · PostgreSQL · Cloudflare`
**Voiceover (EN):**
> "Under the hood: an Elixir and Phoenix backend, LiveKit for scalable video, PostgreSQL, and a Cloudflare-protected perimeter. We're honest about our stage — encryption in transit today, end-to-end and E-IMZO on the roadmap."

---

### Scene 10 — Team & close · 2:50–3:00
**On screen:** Slide 16 (Team) of the presentation → then the SVC logo with `svc.co1nlist.uz`.
**On-screen text:** `QuantixCore Technologies · svc.co1nlist.uz`
**Voiceover (EN):**
> "Built by the QuantixCore team — a working product, a clear market, and an honest plan. SVC: secure communication for national data sovereignty. Thank you."

---

## ✅ Before recording — checklist
- [ ] `svc.co1nlist.uz` and `admin.co1nlist.uz` open and working (verified live).
- [ ] Log in ready: `shuxrat` (super-admin) and `aziz` (manager) for the RBAC/privacy demo.
- [ ] Android app v0.4.3 installed on emulator/phone; logged out (to show landing → login).
- [ ] `Presentation_SVC_EN.html` open in fullscreen (F11) for the slide cutaways (scenes 1, 8, 9, 10).
- [ ] Screen recorder set to 1920×1080, 30 fps; microphone tested (if narrating).

## 💡 Tips
- **Keep it under 3 minutes** — juries watch many videos.
- The **live demo is your biggest advantage** — most applicants only have slides. Spend the most time on scenes 3–7 (real working panel + app).
- If narrating live is hard, record clean screen video first, then add the English lines as **subtitles** in the editor.
- Cut all loading/waiting moments. Smooth, quick transitions.
- Optional strongest shot: once **LiveKit Cloud** is connected, add a 10-second clip of a **real two-device video call** between scenes 7 and 8 — that seals the "it actually works" message.

## 🎞️ Suggested tools (free)
- **Recording:** OBS Studio (desktop), built-in screen record (Android/phone).
- **Editing:** Kdenlive or Shotcut (free, subtitles + cuts), or CapCut.
- **Export:** MP4, H.264, 1080p — then upload to the award profile (or YouTube unlisted and paste the link).

*QuantixCore Technologies · SVC · demo video script (EN) · 2026-09*
