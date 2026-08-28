// SVC desktop (Tauri) — E1/E5.
// Ekran himoyasi (contentProtected) tauri.conf.json da yoqilgan:
// Windows: WDA_EXCLUDEFROMCAPTURE, macOS: sharingType=none, Linux: no-op (D-013).

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
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![security_status])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
