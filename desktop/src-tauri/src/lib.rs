// SVC desktop (Tauri) — E1/E5.
// Ekran himoyasi (contentProtected) tauri.conf.json da yoqilgan:
// Windows: WDA_EXCLUDEFROMCAPTURE, macOS: sharingType=none, Linux: no-op (D-013).
//
// 2-qatlam (E5, S36): `recorder` moduli ishlab turgan rekorderlarni aniqlaydi
// va frontend ularni `/api/capture-events` ga yuboradi.

mod recorder;

use serde::Serialize;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

/// Rekorder skanerlash oralig'i. Qisqaroq qilish aniqlash kechikishini
/// kamaytiradi, lekin har skan jarayonlar ro'yxatini o'qiydi.
const SCAN_INTERVAL: Duration = Duration::from_secs(5);

/// Frontend `capture_events.platform` maydoniga shu qiymatni yuboradi
/// (mobil klientlar bilan bir xil konvensiya: "ios" / "android").
fn platform() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        "windows"
    }
    #[cfg(target_os = "macos")]
    {
        "macos"
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        "linux"
    }
}

#[derive(Serialize, Clone)]
struct RecorderAlert {
    platform: &'static str,
    detections: Vec<recorder::DetectedRecorder>,
}

#[tauri::command]
fn security_status() -> String {
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    {
        "enforced".to_string()
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        "Linux'da qo'llab-quvvatlanmaydi (Win/macOS'da enforce)".to_string()
    }
}

#[tauri::command]
fn client_platform() -> &'static str {
    platform()
}

/// Hozir ishlab turgan rekorderlar ro'yxati (talab bo'yicha skan).
/// Majlisga kirishdan oldin tekshirish uchun ishlatiladi.
#[tauri::command]
fn detect_recorders() -> Vec<recorder::DetectedRecorder> {
    recorder::scan()
}

/// Fon kuzatuvchisi: har `SCAN_INTERVAL` da skanerlaydi va faqat YANGI
/// aniqlanganlar uchun `recorder-detected` hodisasini yuboradi.
/// Alohida OS-oqimida ishlaydi — `scan()` bloklovchi, async runtime'ni band qilmasin.
fn spawn_watcher(app: AppHandle) {
    std::thread::spawn(move || {
        let mut seen = recorder::SeenSet::default();
        loop {
            let fresh = seen.take_new(&recorder::scan());
            if !fresh.is_empty() {
                log::warn!("Ekran yozib olish dasturi aniqlandi: {fresh:?}");
                let payload = RecorderAlert {
                    platform: platform(),
                    detections: fresh,
                };
                // Frontend hali yuklanmagan bo'lsa xato qaytadi — qo'ng'iroqqa
                // xalaqit bermasin, keyingi skanda qayta urinamiz.
                if let Err(e) = app.emit("recorder-detected", payload) {
                    log::debug!("recorder-detected yuborilmadi: {e}");
                }
            }
            std::thread::sleep(SCAN_INTERVAL);
        }
    });
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_http::init())
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            spawn_watcher(app.handle().clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            security_status,
            client_platform,
            detect_recorders
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
