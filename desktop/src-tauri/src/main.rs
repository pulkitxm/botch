#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod address;
mod chrome;
mod cookies;
mod crypto;
mod session;
mod shell;

use tauri::AppHandle;

#[tauri::command]
fn state(app: AppHandle) {
    shell::emit_current_state(&app);
}

#[tauri::command]
fn expand(app: AppHandle) {
    shell::expand(&app);
}

#[tauri::command]
fn new_tab(app: AppHandle, url: Option<String>) {
    let url = url.and_then(|text| address::direct_url(&text));
    shell::open_tab_later(&app, url);
}

#[tauri::command]
fn close_tab(app: AppHandle, id: u64) {
    shell::close_tab(&app, id);
}

#[tauri::command]
fn select_tab(app: AppHandle, id: u64) {
    shell::select_tab(&app, id);
}

#[tauri::command]
fn navigate(app: AppHandle, id: u64, input: String) {
    shell::navigate(&app, id, &input);
}

#[tauri::command]
fn go_back(app: AppHandle, id: u64) {
    shell::run_in_tab(&app, id, "history.back()");
}

#[tauri::command]
fn go_forward(app: AppHandle, id: u64) {
    shell::run_in_tab(&app, id, "history.forward()");
}

#[tauri::command]
fn reload(app: AppHandle, id: u64) {
    shell::run_in_tab(&app, id, "location.reload()");
}

#[tauri::command]
fn set_overlay(app: AppHandle, open: bool) {
    shell::set_overlay(&app, open);
}

#[tauri::command]
fn set_search_engine(app: AppHandle, id: String) {
    shell::set_search_engine(&app, &id);
}

#[tauri::command]
fn set_expanded_size(app: AppHandle, width: f64, height: f64) {
    shell::set_expanded_size(&app, width, height);
}

#[tauri::command]
fn choose_profile(app: AppHandle, directory: String) {
    shell::choose_profile(&app, &directory);
}

#[tauri::command]
fn detach_profile(app: AppHandle) {
    shell::detach_profile(&app);
}

#[tauri::command]
fn open_external(url: String) {
    if url.starts_with("https://") {
        let _ = open::that_detached(url);
    }
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

fn main() {
    #[cfg(target_os = "linux")]
    if std::env::var_os("GDK_BACKEND").is_none() {
        std::env::set_var("GDK_BACKEND", "x11");
    }
    tauri::Builder::default()
        .setup(|app| Ok(shell::setup(app.handle())?))
        .invoke_handler(tauri::generate_handler![
            state,
            expand,
            new_tab,
            close_tab,
            select_tab,
            navigate,
            go_back,
            go_forward,
            reload,
            set_overlay,
            set_search_engine,
            set_expanded_size,
            choose_profile,
            detach_profile,
            open_external,
            quit
        ])
        .run(tauri::generate_context!())
        .expect("failed to start Botch");
}
