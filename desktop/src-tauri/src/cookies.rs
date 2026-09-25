use crate::crypto::{self, CookieKeys, Skip};
use rusqlite::{Connection, OpenFlags};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const WINDOWS_EPOCH_OFFSET: i64 = 11_644_473_600;
const HASH_PREFIX_VERSION: i64 = 24;
const SNAPSHOT_ATTEMPTS: usize = 3;
const SIDECARS: [&str; 3] = ["-journal", "-wal", "-shm"];

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SameSite {
    #[default]
    Unspecified,
    None,
    Lax,
    Strict,
}

impl SameSite {
    fn from_chrome(value: i64) -> Self {
        match value {
            0 => SameSite::None,
            1 => SameSite::Lax,
            2 => SameSite::Strict,
            _ => SameSite::Unspecified,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChromeCookie {
    pub host: String,
    pub name: String,
    pub value: String,
    pub path: String,
    pub expires_unix: Option<i64>,
    pub secure: bool,
    pub http_only: bool,
    pub same_site: SameSite,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SkippedCookies {
    pub keyring: usize,
    pub app_bound: usize,
    pub undecryptable: usize,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CookieBatch {
    pub cookies: Vec<ChromeCookie>,
    pub skipped: SkippedCookies,
}

pub fn unix_seconds(chrome_microseconds: i64) -> Option<i64> {
    (chrome_microseconds > 0).then(|| chrome_microseconds / 1_000_000 - WINDOWS_EPOCH_OFFSET)
}

pub fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

pub fn needs_keyring_key(database: &Path) -> bool {
    let Ok(scratch) = Scratch::new() else {
        return false;
    };
    let Ok(copy) = snapshot(database, &scratch.dir) else {
        return false;
    };
    Connection::open_with_flags(copy, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .and_then(|db| {
            db.query_row(
                "SELECT COUNT(*) FROM cookies WHERE substr(encrypted_value, 1, 3) = X'763131'",
                [],
                |row| row.get::<_, i64>(0),
            )
        })
        .map(|count| count > 0)
        .unwrap_or(false)
}

pub fn read(database: &Path, keys: &CookieKeys, now: i64) -> Result<CookieBatch, String> {
    if !database.is_file() {
        return Err("This Chrome profile has no cookie database yet.".to_string());
    }
    let mut last_error = "the database kept changing".to_string();
    for attempt in 0..SNAPSHOT_ATTEMPTS {
        if attempt > 0 {
            std::thread::sleep(Duration::from_millis(150));
        }
        let scratch = Scratch::new()?;
        match snapshot(database, &scratch.dir).and_then(|copy| rows(&copy, keys, now)) {
            Ok(batch) => return Ok(batch),
            Err(reason) => last_error = reason,
        }
    }
    Err(format!(
        "Chrome's cookie database could not be read: {last_error}"
    ))
}

struct Scratch {
    dir: PathBuf,
}

impl Scratch {
    fn new() -> Result<Self, String> {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or_default();
        let dir =
            std::env::temp_dir().join(format!("botch-cookies-{}-{unique}", std::process::id()));
        fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
        Ok(Scratch { dir })
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

fn fingerprint(database: &Path) -> Vec<String> {
    std::iter::once("")
        .chain(SIDECARS)
        .map(|suffix| {
            let path = sidecar(database, suffix);
            match fs::metadata(&path) {
                Ok(meta) => format!("{suffix}:{}:{:?}", meta.len(), meta.modified().ok()),
                Err(_) => format!("{suffix}:absent"),
            }
        })
        .collect()
}

fn sidecar(database: &Path, suffix: &str) -> PathBuf {
    let mut name = database.as_os_str().to_os_string();
    name.push(suffix);
    PathBuf::from(name)
}

fn snapshot(database: &Path, scratch: &Path) -> Result<PathBuf, String> {
    let before = fingerprint(database);
    let copy = scratch.join("Cookies");
    fs::copy(database, &copy).map_err(|e| e.to_string())?;
    for suffix in SIDECARS {
        let source = sidecar(database, suffix);
        if source.is_file() {
            fs::copy(&source, sidecar(&copy, suffix)).map_err(|e| e.to_string())?;
        }
    }
    if fingerprint(database) != before {
        return Err("the database changed while it was copied".to_string());
    }
    Ok(copy)
}

fn rows(copy: &Path, keys: &CookieKeys, now: i64) -> Result<CookieBatch, String> {
    let db = Connection::open_with_flags(copy, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .map_err(|e| e.to_string())?;
    let version: i64 = db
        .query_row("SELECT value FROM meta WHERE key = 'version'", [], |row| {
            row.get::<_, String>(0)
        })
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let columns = column_names(&db, "cookies")?;
    let mut sql = String::from(
        "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite FROM cookies",
    );
    if columns.contains("top_frame_site_key") {
        sql.push_str(" WHERE top_frame_site_key = ''");
    }
    let mut statement = db.prepare(&sql).map_err(|e| e.to_string())?;
    let hash_prefixed = version >= HASH_PREFIX_VERSION;
    let mut batch = CookieBatch::default();
    let mut query = statement.query([]).map_err(|e| e.to_string())?;
    while let Some(row) = query.next().map_err(|e| e.to_string())? {
        let host: String = row.get(0).unwrap_or_default();
        let name: String = row.get(1).unwrap_or_default();
        if host.is_empty() || name.is_empty() {
            continue;
        }
        let expires_unix = unix_seconds(row.get::<_, i64>(5).unwrap_or_default());
        if expires_unix.is_some_and(|expires| expires <= now) {
            continue;
        }
        let mut value: String = row.get(2).unwrap_or_default();
        let encrypted: Vec<u8> = row.get(3).unwrap_or_default();
        if value.is_empty() && !encrypted.is_empty() {
            match crypto::decrypt(&encrypted, keys, &host, hash_prefixed) {
                Ok(decrypted) => value = decrypted,
                Err(Skip::KeyringKeyMissing) => {
                    batch.skipped.keyring += 1;
                    continue;
                }
                Err(Skip::AppBound) => {
                    batch.skipped.app_bound += 1;
                    continue;
                }
                Err(Skip::Undecryptable) => {
                    batch.skipped.undecryptable += 1;
                    continue;
                }
            }
        }
        batch.cookies.push(ChromeCookie {
            host,
            name,
            value,
            path: row.get(4).unwrap_or_default(),
            expires_unix,
            secure: row.get::<_, i64>(6).unwrap_or_default() != 0,
            http_only: row.get::<_, i64>(7).unwrap_or_default() != 0,
            same_site: SameSite::from_chrome(row.get::<_, i64>(8).unwrap_or(-1)),
        });
    }
    Ok(batch)
}

fn column_names(db: &Connection, table: &str) -> Result<HashSet<String>, String> {
    let mut statement = db
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|e| e.to_string())?;
    let names = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .collect();
    Ok(names)
}

#[cfg(test)]
pub mod test_support {
    use super::*;
    use crate::crypto::test_support::{encrypt_cbc, hashed};

    pub const PASSWORD: &str = "peanuts";

    pub fn chrome_microseconds(unix: i64) -> i64 {
        (unix + WINDOWS_EPOCH_OFFSET) * 1_000_000
    }

    pub fn encrypted(host: &str, value: &str) -> Vec<u8> {
        [
            b"v10".as_slice(),
            &encrypt_cbc(&crypto::derive_cbc_key(PASSWORD), &hashed(host, value)),
        ]
        .concat()
    }

    pub fn write_database(path: &Path, version: i64, partitioned_column: bool) -> Connection {
        let db = Connection::open(path).unwrap();
        let partition = if partitioned_column {
            ", top_frame_site_key TEXT NOT NULL DEFAULT ''"
        } else {
            ""
        };
        db.execute_batch(&format!(
            "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
             INSERT INTO meta VALUES ('version', '{version}');
             CREATE TABLE cookies (host_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL DEFAULT '',
             encrypted_value BLOB NOT NULL DEFAULT X'', path TEXT NOT NULL DEFAULT '/', expires_utc INTEGER NOT NULL DEFAULT 0,
             is_secure INTEGER NOT NULL DEFAULT 0, is_httponly INTEGER NOT NULL DEFAULT 0, samesite INTEGER NOT NULL DEFAULT -1{partition});"
        ))
        .unwrap();
        db
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::*;
    use super::*;
    use crate::crypto::{derive_cbc_key, CookieKey};

    fn keys() -> CookieKeys {
        CookieKeys {
            v10: Some(CookieKey::Cbc(derive_cbc_key(PASSWORD))),
            v11: None,
        }
    }

    fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("botch-cookie-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir.join("Cookies")
    }

    #[test]
    fn chrome_timestamps_convert_to_unix_seconds() {
        assert_eq!(unix_seconds(0), None);
        assert_eq!(
            unix_seconds(chrome_microseconds(1_700_000_000)),
            Some(1_700_000_000)
        );
        assert_eq!(unix_seconds(11_644_473_600 * 1_000_000), Some(0));
    }

    #[test]
    fn cookies_are_decrypted_filtered_and_typed() {
        let path = temp("read");
        let now = 1_700_000_000;
        {
            let db = write_database(&path, 24, true);
            let mut insert = db
                .prepare("INSERT INTO cookies (host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, top_frame_site_key) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)")
                .unwrap();
            let live = chrome_microseconds(now + 3600);
            let dead = chrome_microseconds(now - 1);
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "sid",
                    "",
                    encrypted(".example.com", "secret"),
                    "/",
                    live,
                    1,
                    1,
                    1,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    "plain.example.com",
                    "plain",
                    "visible",
                    Vec::<u8>::new(),
                    "/app",
                    0,
                    0,
                    0,
                    -1,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "old",
                    "",
                    encrypted(".example.com", "x"),
                    "/",
                    dead,
                    0,
                    0,
                    0,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "partitioned",
                    "",
                    encrypted(".example.com", "x"),
                    "/",
                    live,
                    0,
                    0,
                    0,
                    "https://other.test"
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "keyring",
                    "",
                    b"v11garbage".to_vec(),
                    "/",
                    live,
                    0,
                    0,
                    0,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "appbound",
                    "",
                    b"v20garbage".to_vec(),
                    "/",
                    live,
                    0,
                    0,
                    0,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    ".example.com",
                    "broken",
                    "",
                    b"v10tooshort".to_vec(),
                    "/",
                    live,
                    0,
                    0,
                    0,
                    ""
                ])
                .unwrap();
            insert
                .execute(rusqlite::params![
                    "",
                    "nohost",
                    "v",
                    Vec::<u8>::new(),
                    "/",
                    live,
                    0,
                    0,
                    0,
                    ""
                ])
                .unwrap();
        }
        assert!(needs_keyring_key(&path));
        let batch = read(&path, &keys(), now).unwrap();
        assert_eq!(
            batch.skipped,
            SkippedCookies {
                keyring: 1,
                app_bound: 1,
                undecryptable: 1
            }
        );
        assert_eq!(batch.cookies.len(), 2);
        assert_eq!(
            batch.cookies[0],
            ChromeCookie {
                host: ".example.com".into(),
                name: "sid".into(),
                value: "secret".into(),
                path: "/".into(),
                expires_unix: Some(now + 3600),
                secure: true,
                http_only: true,
                same_site: SameSite::Lax,
            }
        );
        assert_eq!(batch.cookies[1].value, "visible");
        assert_eq!(batch.cookies[1].expires_unix, None);
        assert_eq!(batch.cookies[1].same_site, SameSite::Unspecified);
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn older_schemas_without_partition_column_or_hash_prefix_still_read() {
        let path = temp("legacy");
        {
            let db = write_database(&path, 18, false);
            let blob = [
                b"v10".as_slice(),
                &crate::crypto::test_support::encrypt_cbc(&derive_cbc_key(PASSWORD), b"legacy"),
            ]
            .concat();
            db.execute(
                "INSERT INTO cookies (host_key, name, encrypted_value) VALUES (?1, ?2, ?3)",
                rusqlite::params!["legacy.test", "c", blob],
            )
            .unwrap();
        }
        assert!(!needs_keyring_key(&path));
        let batch = read(&path, &keys(), 0).unwrap();
        assert_eq!(batch.cookies.len(), 1);
        assert_eq!(batch.cookies[0].value, "legacy");
        assert!(read(&path.with_file_name("Missing"), &keys(), 0).is_err());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }
}
