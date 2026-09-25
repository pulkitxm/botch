mod address;
mod chrome;
mod cookies;
mod crypto;
mod session;

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("failed to start Botch");
}
