use serde::Serialize;
use serde_json::Value;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

pub const DOWNLOAD_URL: &str = "https://www.google.com/chrome/";

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ChromeProfile {
    pub directory: String,
    pub name: String,
    pub email: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChromeError {
    NotInstalled,
    Unreadable(String),
}

impl fmt::Display for ChromeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ChromeError::NotInstalled => {
                write!(f, "Google Chrome is not installed for this user.")
            }
            ChromeError::Unreadable(reason) => {
                write!(f, "Chrome's profile list could not be read: {reason}")
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct ChromeUserData {
    pub root: PathBuf,
}

impl ChromeUserData {
    pub fn standard() -> Option<Self> {
        let root = if cfg!(target_os = "linux") {
            dirs::config_dir()?.join("google-chrome")
        } else if cfg!(windows) {
            dirs::data_local_dir()?
                .join("Google")
                .join("Chrome")
                .join("User Data")
        } else {
            dirs::data_dir()?.join("Google").join("Chrome")
        };
        Some(ChromeUserData { root })
    }

    pub fn local_state_path(&self) -> PathBuf {
        self.root.join("Local State")
    }

    pub fn local_state(&self) -> Result<Value, ChromeError> {
        let path = self.local_state_path();
        if !path.is_file() {
            return Err(ChromeError::NotInstalled);
        }
        let bytes = fs::read(&path).map_err(|e| ChromeError::Unreadable(e.to_string()))?;
        serde_json::from_slice(&bytes).map_err(|e| ChromeError::Unreadable(e.to_string()))
    }

    pub fn profiles(&self) -> Result<Vec<ChromeProfile>, ChromeError> {
        let local_state = self.local_state()?;
        Ok(parse_profiles(&local_state, |directory| {
            self.root.join(directory).is_dir()
        }))
    }

    pub fn cookies_path(&self, directory: &str) -> Option<PathBuf> {
        let base = self.root.join(directory);
        [base.join("Network").join("Cookies"), base.join("Cookies")]
            .into_iter()
            .filter(|path| path.is_file())
            .max_by_key(|path| modified(path))
    }
}

fn modified(path: &Path) -> SystemTime {
    fs::metadata(path)
        .and_then(|meta| meta.modified())
        .unwrap_or(SystemTime::UNIX_EPOCH)
}

pub fn parse_profiles(local_state: &Value, exists: impl Fn(&str) -> bool) -> Vec<ChromeProfile> {
    let profile = &local_state["profile"];
    let Some(cache) = profile["info_cache"].as_object() else {
        return Vec::new();
    };
    let order: Vec<&str> = profile["profiles_order"]
        .as_array()
        .map(|items| items.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();
    let mut directories: Vec<&str> = order
        .iter()
        .copied()
        .filter(|directory| cache.contains_key(*directory))
        .collect();
    let mut rest: Vec<&str> = cache
        .keys()
        .map(String::as_str)
        .filter(|directory| !order.contains(directory))
        .collect();
    rest.sort_by(|a, b| directory_order(a, b));
    directories.extend(rest);
    directories
        .into_iter()
        .filter(|directory| exists(directory))
        .map(|directory| {
            let info = &cache[directory];
            ChromeProfile {
                directory: directory.to_string(),
                name: display_name(info, directory),
                email: non_empty(&info["user_name"]),
            }
        })
        .collect()
}

fn display_name(info: &Value, directory: &str) -> String {
    let name = non_empty(&info["name"]);
    let given = non_empty(&info["gaia_given_name"]);
    let full = non_empty(&info["gaia_name"]);
    if info["is_using_default_name"].as_bool() == Some(true) {
        if let Some(given) = given.clone() {
            return given;
        }
    }
    name.or(full)
        .or(given)
        .unwrap_or_else(|| directory.to_string())
}

fn non_empty(value: &Value) -> Option<String> {
    let trimmed = value.as_str()?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

fn directory_order(lhs: &str, rhs: &str) -> std::cmp::Ordering {
    match (lhs == "Default", rhs == "Default") {
        (true, true) => std::cmp::Ordering::Equal,
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        (false, false) => lhs.to_lowercase().cmp(&rhs.to_lowercase()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn local_state() -> Value {
        json!({
            "profile": {
                "profiles_order": ["Profile 2"],
                "info_cache": {
                    "Default": {
                        "name": "Person 1",
                        "gaia_given_name": "Ada",
                        "is_using_default_name": true,
                        "user_name": "ada@example.com"
                    },
                    "Profile 2": {
                        "name": "Work",
                        "user_name": "  "
                    },
                    "Profile 3": {
                        "gaia_name": "Grace Hopper"
                    },
                    "Missing": {
                        "name": "Gone"
                    }
                }
            }
        })
    }

    #[test]
    fn profiles_follow_chrome_order_and_skip_missing_directories() {
        let profiles = parse_profiles(&local_state(), |directory| directory != "Missing");
        let directories: Vec<&str> = profiles.iter().map(|p| p.directory.as_str()).collect();
        assert_eq!(directories, ["Profile 2", "Default", "Profile 3"]);
        assert_eq!(profiles[0].name, "Work");
        assert_eq!(profiles[0].email, None);
        assert_eq!(profiles[1].name, "Ada");
        assert_eq!(profiles[1].email.as_deref(), Some("ada@example.com"));
        assert_eq!(profiles[2].name, "Grace Hopper");
    }

    #[test]
    fn malformed_local_state_yields_no_profiles() {
        assert!(parse_profiles(&json!({}), |_| true).is_empty());
        assert!(parse_profiles(&json!({"profile": {"info_cache": []}}), |_| true).is_empty());
    }

    #[test]
    fn user_data_reads_local_state_and_finds_the_newest_cookie_database() {
        let root = std::env::temp_dir().join(format!("botch-chrome-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let user_data = ChromeUserData { root: root.clone() };
        assert_eq!(user_data.profiles(), Err(ChromeError::NotInstalled));
        fs::create_dir_all(root.join("Default").join("Network")).unwrap();
        fs::write(user_data.local_state_path(), local_state().to_string()).unwrap();
        let profiles = user_data.profiles().unwrap();
        assert_eq!(profiles.len(), 1);
        assert_eq!(profiles[0].directory, "Default");
        assert_eq!(user_data.cookies_path("Default"), None);
        fs::write(root.join("Default").join("Cookies"), b"old").unwrap();
        assert_eq!(
            user_data.cookies_path("Default"),
            Some(root.join("Default").join("Cookies"))
        );
        fs::write(user_data.local_state_path(), b"{").unwrap();
        assert!(matches!(
            user_data.profiles(),
            Err(ChromeError::Unreadable(_))
        ));
        fs::remove_dir_all(&root).unwrap();
    }
}
