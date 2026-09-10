// SVC desktop — ekran yozib oluvchi dasturlar detektori (E5, D-013, D-002).
//
// NEGA KERAK: `setContentProtected` faqat Windows'da haqiqiy ENFORCE beradi
// (WDA_EXCLUDEFROMCAPTURE). macOS 15+ da ScreenCaptureKit uni chetlab o'tadi,
// Linux'da esa umuman no-op. Shu sababli 2-qatlam kerak — DETECT: ishlab turgan
// jarayonlarni skanerlab, ma'lum rekorderlarni topamiz va `capture_events` ga
// yozamiz (audit + per-meeting siyosat: none/warn/eject).
//
// HALOLLIK CHEGARASI (D-013): bu **kafolat emas**. Jarayon nomini o'zgartirgan
// yoki ro'yxatda yo'q vosita aniqlanmaydi, telefonda suratga olishni esa hech
// qanday dastur to'sa olmaydi. Detektor xavfni kamaytiradi, yo'q qilmaydi.

use serde::Serialize;
use std::collections::HashSet;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

/// Aniqlangan dastur toifasi. Ikkalasi ham ekran tarkibini qurilmadan
/// chiqarib yuborishi mumkin, shuning uchun bitta `recorder_detected` turiga
/// yoziladi, lekin `detail.category` orqali farqlanadi.
pub const CATEGORY_RECORDER: &str = "recorder";
pub const CATEGORY_REMOTE: &str = "remote_access";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DetectedRecorder {
    /// Mahsulot nomi, masalan "OBS Studio".
    pub name: String,
    /// Kuzatilgan haqiqiy jarayon nomi (diagnostika uchun).
    pub process: String,
    pub pid: u32,
    pub category: &'static str,
}

/// Qisqa yoki umumiy nomlar — faqat to'liq moslik bo'yicha.
/// Substring bo'lsa yolg'on ijobiy natija beradi (masalan "action" → "transaction").
const EXACT: &[(&str, &str, &str)] = &[
    ("obs", "OBS Studio", CATEGORY_RECORDER),
    ("obs64", "OBS Studio", CATEGORY_RECORDER),
    ("obs32", "OBS Studio", CATEGORY_RECORDER),
    ("fraps", "Fraps", CATEGORY_RECORDER),
    ("action", "Mirillis Action!", CATEGORY_RECORDER),
    ("debut", "NCH Debut Video Capture", CATEGORY_RECORDER),
    ("loom", "Loom", CATEGORY_RECORDER),
    ("kazam", "Kazam", CATEGORY_RECORDER),
    ("peek", "Peek", CATEGORY_RECORDER),
    ("wf-recorder", "wf-recorder", CATEGORY_RECORDER),
    ("gpu-screen-recorder", "GPU Screen Recorder", CATEGORY_RECORDER),
    ("screencapture", "macOS screencapture", CATEGORY_RECORDER),
    ("screencaptureui", "macOS Screenshot", CATEGORY_RECORDER),
    ("quicktime player", "QuickTime Player", CATEGORY_RECORDER),
    ("camrecorder", "Camtasia Recorder", CATEGORY_RECORDER),
    ("anydesk", "AnyDesk", CATEGORY_REMOTE),
    ("rustdesk", "RustDesk", CATEGORY_REMOTE),
    ("teamviewer", "TeamViewer", CATEGORY_REMOTE),
];

/// Ajralib turadigan (uzun, o'ziga xos) tokenlar — substring bo'yicha,
/// chunki versiya/qurilma qo'shimchalari nomga qo'shilib ketadi
/// (masalan "Bandicam 7", "SnagitEditor32").
const CONTAINS: &[(&str, &str, &str)] = &[
    ("bandicam", "Bandicam", CATEGORY_RECORDER),
    ("camtasia", "Camtasia", CATEGORY_RECORDER),
    ("screentogif", "ScreenToGif", CATEGORY_RECORDER),
    ("sharex", "ShareX", CATEGORY_RECORDER),
    ("snagit", "Snagit", CATEGORY_RECORDER),
    ("xsplit", "XSplit", CATEGORY_RECORDER),
    ("apowerrec", "ApowerREC", CATEGORY_RECORDER),
    ("movavi", "Movavi Screen Recorder", CATEGORY_RECORDER),
    ("flashback", "FlashBack Recorder", CATEGORY_RECORDER),
    ("icecream", "Icecream Screen Recorder", CATEGORY_RECORDER),
    ("simplescreenrecorder", "SimpleScreenRecorder", CATEGORY_RECORDER),
    ("vokoscreen", "vokoscreen", CATEGORY_RECORDER),
    ("recordmydesktop", "recordMyDesktop", CATEGORY_RECORDER),
    ("screenrec", "ScreenRec", CATEGORY_RECORDER),
    ("screencastify", "Screencastify", CATEGORY_RECORDER),
    ("screencast-o-matic", "Screencast-O-Matic", CATEGORY_RECORDER),
    ("teamviewer", "TeamViewer", CATEGORY_REMOTE),
];

/// Jarayon nomini solishtirish uchun normallashtiradi: papka yo'li olib
/// tashlanadi, `.exe` kesiladi, kichik harfga o'tkaziladi.
fn normalize(raw: &str) -> String {
    let base = raw
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(raw)
        .trim()
        .to_lowercase();
    base.strip_suffix(".exe").unwrap_or(&base).to_string()
}

/// Bitta jarayon nomini imzolar ro'yxatiga solishtiradi.
/// Sof funksiya — testlar shu yerga qaratilgan.
pub fn match_recorder(process_name: &str) -> Option<(&'static str, &'static str)> {
    let name = normalize(process_name);
    if name.is_empty() {
        return None;
    }

    if let Some(&(_, label, cat)) = EXACT.iter().find(|(pat, _, _)| *pat == name) {
        return Some((label, cat));
    }

    CONTAINS
        .iter()
        .find(|(pat, _, _)| name.contains(pat))
        .map(|&(_, label, cat)| (label, cat))
}

/// Ishlab turgan jarayonlarni skanerlaydi.
pub fn scan() -> Vec<DetectedRecorder> {
    let mut sys = System::new();
    // Faqat nomlar kerak — CPU/xotira yig'ilmaydi (skan arzon bo'lsin).
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing(),
    );

    let mut found: Vec<DetectedRecorder> = sys
        .processes()
        .iter()
        .filter_map(|(pid, proc_)| {
            let raw = proc_.name().to_string_lossy().to_string();
            match_recorder(&raw).map(|(label, category)| DetectedRecorder {
                name: label.to_string(),
                process: raw,
                pid: pid.as_u32(),
                category,
            })
        })
        .collect();

    found.sort_by(|a, b| a.name.cmp(&b.name).then(a.pid.cmp(&b.pid)));
    found
}

/// Kuzatuvchi holati: allaqachon xabar berilgan jarayonlar.
/// PID qayta ishlatilishi mumkinligi uchun (nom, pid) juftligi saqlanadi.
#[derive(Default)]
pub struct SeenSet(HashSet<(String, u32)>);

impl SeenSet {
    /// Skan natijasidan faqat YANGI aniqlanganlarni qaytaradi va ularni
    /// ko'rilgan deb belgilaydi. Yo'qolgan jarayonlar unutiladi — dastur
    /// qayta ishga tushirilsa, u yangi hodisa sifatida qayd etiladi.
    pub fn take_new(&mut self, current: &[DetectedRecorder]) -> Vec<DetectedRecorder> {
        let live: HashSet<(String, u32)> = current
            .iter()
            .map(|d| (d.process.clone(), d.pid))
            .collect();
        self.0.retain(|k| live.contains(k));

        current
            .iter()
            .filter(|d| self.0.insert((d.process.clone(), d.pid)))
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topadi_windows_exe_nomlarini() {
        assert_eq!(match_recorder("obs64.exe").unwrap().0, "OBS Studio");
        assert_eq!(match_recorder("Bandicam.exe").unwrap().0, "Bandicam");
        assert_eq!(match_recorder("SnagitEditor32.exe").unwrap().0, "Snagit");
        assert_eq!(match_recorder("Fraps.exe").unwrap().0, "Fraps");
    }

    #[test]
    fn topadi_linux_va_macos_nomlarini() {
        assert_eq!(match_recorder("obs").unwrap().0, "OBS Studio");
        assert_eq!(
            match_recorder("simplescreenrecorder").unwrap().0,
            "SimpleScreenRecorder"
        );
        assert_eq!(match_recorder("QuickTime Player").unwrap().0, "QuickTime Player");
        assert_eq!(match_recorder("screencapture").unwrap().0, "macOS screencapture");
    }

    #[test]
    fn toliq_yolni_qisqartiradi() {
        assert_eq!(
            match_recorder("C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe")
                .unwrap()
                .0,
            "OBS Studio"
        );
        assert_eq!(match_recorder("/usr/bin/kazam").unwrap().0, "Kazam");
    }

    #[test]
    fn masofaviy_kirish_alohida_toifada() {
        assert_eq!(match_recorder("AnyDesk.exe").unwrap().1, CATEGORY_REMOTE);
        assert_eq!(match_recorder("obs64.exe").unwrap().1, CATEGORY_RECORDER);
    }

    // Yolg'on ijobiy natija xavflisi: siyosat `eject` bo'lsa, begunoh
    // foydalanuvchi majlisdan chiqarib yuboriladi.
    #[test]
    fn yolgon_ijobiy_natija_bermaydi() {
        for name in [
            "transaction-worker", // "action" substring bo'lsa tushib qolardi
            "chrome.exe",
            "beam",
            "peekaboo", // "peek" substring bo'lsa tushib qolardi
            "svc",
            "ffmpeg", // umumiy vosita — ataylab ro'yxatda yo'q
            "bloom",  // "loom" substring bo'lsa tushib qolardi
            "",
            "   ",
        ] {
            assert!(
                match_recorder(name).is_none(),
                "{name} noto'g'ri aniqlandi"
            );
        }
    }

    // `scan()` ning sysinfo bilan bog'lanishini tekshiradi: birlik-testlar
    // `match_recorder` ni qoplaydi, lekin `Process::name()` platformaga qarab
    // to'liq yo'l yoki basename qaytarishi mumkin — buni faqat haqiqiy
    // jarayonda bilib bo'ladi.
    #[cfg(unix)]
    #[test]
    fn haqiqiy_jarayonni_topadi() {
        use std::process::Command;
        use std::time::Duration;

        let dir = std::env::temp_dir().join(format!("svc-rec-{}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("vaqtinchalik papka");
        let fake = dir.join("obs64");
        std::fs::copy("/bin/sleep", &fake).expect("sleep nusxasi");

        let mut child = Command::new(&fake).arg("30").spawn().expect("ishga tushdi");
        let pid = child.id();
        std::thread::sleep(Duration::from_millis(300));

        let found = scan();

        let _ = child.kill();
        let _ = child.wait();
        let _ = std::fs::remove_dir_all(&dir);

        let hit = found.iter().find(|d| d.pid == pid);
        assert!(
            hit.is_some(),
            "obs64 nomli jarayon topilmadi; skan natijasi: {found:?}"
        );
        assert_eq!(hit.unwrap().name, "OBS Studio");
    }

    #[test]
    fn yangi_aniqlanganlarni_bir_marta_qaytaradi() {
        let mut seen = SeenSet::default();
        let obs = DetectedRecorder {
            name: "OBS Studio".into(),
            process: "obs64.exe".into(),
            pid: 100,
            category: CATEGORY_RECORDER,
        };

        assert_eq!(seen.take_new(&[obs.clone()]).len(), 1, "birinchi marta");
        assert!(seen.take_new(&[obs.clone()]).is_empty(), "takrorlanmaydi");

        // Jarayon yopildi → keyin qayta ochildi: yangi hodisa sifatida qayd etiladi.
        assert!(seen.take_new(&[]).is_empty());
        assert_eq!(seen.take_new(&[obs]).len(), 1, "qayta ishga tushirish");
    }
}
