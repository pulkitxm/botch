use crate::address::SearchEngine;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

pub const DEFAULT_WIDTH: f64 = 1000.0;
pub const DEFAULT_HEIGHT: f64 = 640.0;
pub const MIN_WIDTH: f64 = 480.0;
pub const MIN_HEIGHT: f64 = 320.0;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SavedTab {
    pub url: String,
    pub title: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Session {
    pub profile: Option<String>,
    pub tabs: Vec<SavedTab>,
    pub selected: usize,
    pub width: f64,
    pub height: f64,
    pub search_engine: SearchEngine,
}

impl Default for Session {
    fn default() -> Self {
        Session {
            profile: None,
            tabs: Vec::new(),
            selected: 0,
            width: DEFAULT_WIDTH,
            height: DEFAULT_HEIGHT,
            search_engine: SearchEngine::default(),
        }
    }
}

impl Session {
    pub fn clamp_size(width: f64, height: f64) -> (f64, f64) {
        (width.max(MIN_WIDTH).round(), height.max(MIN_HEIGHT).round())
    }
}

pub fn path() -> Option<PathBuf> {
    Some(dirs::config_dir()?.join("botch-desktop.json"))
}

pub fn load() -> Session {
    path()
        .and_then(|path| fs::read(path).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

pub fn save(session: &Session) {
    let Some(path) = path() else {
        return;
    };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_vec_pretty(session) {
        let _ = fs::write(path, json);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_fields_fall_back_to_defaults() {
        let session: Session =
            serde_json::from_str(r#"{"profile":"Default","search_engine":"kagi"}"#).unwrap();
        assert_eq!(session.profile.as_deref(), Some("Default"));
        assert_eq!(session.search_engine, SearchEngine::Kagi);
        assert_eq!(session.width, DEFAULT_WIDTH);
        assert!(session.tabs.is_empty());
        assert_eq!(Session::clamp_size(10.0, 5000.4), (MIN_WIDTH, 5000.0));
        assert!(serde_json::from_str::<Session>("{}").is_ok());
    }
}
