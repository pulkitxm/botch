#![allow(dead_code)]

use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyIvInit};
use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use base64::prelude::{Engine as _, BASE64_STANDARD};
use sha2::{Digest, Sha256};

pub const HOST_HASH_LENGTH: usize = 32;
const CBC_IV: [u8; 16] = [b' '; 16];
const GCM_NONCE_LENGTH: usize = 12;
const GCM_TAG_LENGTH: usize = 16;
const DPAPI_PREFIX: &[u8] = b"DPAPI";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CookieKey {
    Cbc([u8; 16]),
    Gcm([u8; 32]),
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CookieKeys {
    pub v10: Option<CookieKey>,
    pub v11: Option<CookieKey>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Skip {
    KeyringKeyMissing,
    AppBound,
    Undecryptable,
}

pub fn derive_cbc_key(password: &str) -> [u8; 16] {
    let mut key = [0u8; 16];
    pbkdf2::pbkdf2_hmac::<sha1::Sha1>(password.as_bytes(), b"saltysalt", 1, &mut key);
    key
}

pub fn host_hash(host: &str) -> [u8; HOST_HASH_LENGTH] {
    Sha256::digest(host.as_bytes()).into()
}

pub fn decrypt(
    blob: &[u8],
    keys: &CookieKeys,
    host: &str,
    hash_prefixed: bool,
) -> Result<String, Skip> {
    let (prefix, body) = blob.split_at_checked(3).ok_or(Skip::Undecryptable)?;
    let key = match prefix {
        b"v10" => keys.v10.as_ref().ok_or(Skip::Undecryptable)?,
        b"v11" => keys.v11.as_ref().ok_or(Skip::KeyringKeyMissing)?,
        b"v20" => return Err(Skip::AppBound),
        _ => return Err(Skip::Undecryptable),
    };
    let mut plain = match key {
        CookieKey::Cbc(key) => decrypt_cbc(key, body),
        CookieKey::Gcm(key) => decrypt_gcm(key, body),
    }
    .ok_or(Skip::Undecryptable)?;
    if hash_prefixed
        && plain.len() >= HOST_HASH_LENGTH
        && plain[..HOST_HASH_LENGTH] == host_hash(host)
    {
        plain.drain(..HOST_HASH_LENGTH);
    }
    String::from_utf8(plain).map_err(|_| Skip::Undecryptable)
}

fn decrypt_cbc(key: &[u8; 16], body: &[u8]) -> Option<Vec<u8>> {
    if body.is_empty() || !body.len().is_multiple_of(16) {
        return None;
    }
    cbc::Decryptor::<aes::Aes128>::new(key.into(), &CBC_IV.into())
        .decrypt_padded_vec_mut::<Pkcs7>(body)
        .ok()
}

fn decrypt_gcm(key: &[u8; 32], body: &[u8]) -> Option<Vec<u8>> {
    if body.len() < GCM_NONCE_LENGTH + GCM_TAG_LENGTH {
        return None;
    }
    let (nonce, ciphertext) = body.split_at(GCM_NONCE_LENGTH);
    Aes256Gcm::new(key.into())
        .decrypt(Nonce::from_slice(nonce), ciphertext)
        .ok()
}

pub fn dpapi_blob_from_local_state(local_state: &serde_json::Value) -> Result<Vec<u8>, String> {
    let encoded = local_state["os_crypt"]["encrypted_key"]
        .as_str()
        .ok_or("Local State has no os_crypt.encrypted_key")?;
    let bytes = BASE64_STANDARD
        .decode(encoded)
        .map_err(|e| format!("os_crypt.encrypted_key is not base64: {e}"))?;
    bytes
        .strip_prefix(DPAPI_PREFIX)
        .map(<[u8]>::to_vec)
        .ok_or_else(|| "os_crypt.encrypted_key does not start with DPAPI".to_string())
}

#[cfg(windows)]
pub fn windows_keys(local_state: &serde_json::Value) -> Result<CookieKeys, String> {
    let protected = dpapi_blob_from_local_state(local_state)?;
    let key = dpapi_unprotect(&protected)?;
    let key: [u8; 32] = key
        .try_into()
        .map_err(|_| "the Chrome master key is not 32 bytes".to_string())?;
    Ok(CookieKeys {
        v10: Some(CookieKey::Gcm(key)),
        v11: None,
    })
}

#[cfg(windows)]
fn dpapi_unprotect(protected: &[u8]) -> Result<Vec<u8>, String> {
    use windows::Win32::Foundation::{LocalFree, HLOCAL};
    use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};
    let mut input = protected.to_vec();
    let input_blob = CRYPT_INTEGER_BLOB {
        cbData: input.len() as u32,
        pbData: input.as_mut_ptr(),
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptUnprotectData(&input_blob, None, None, None, None, 0, &mut output)
            .map_err(|e| format!("CryptUnprotectData failed: {e}"))?;
        let bytes = std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec();
        LocalFree(Some(HLOCAL(output.pbData.cast())));
        Ok(bytes)
    }
}

#[cfg(target_os = "linux")]
pub fn linux_keys(needs_keyring: bool) -> (CookieKeys, Option<String>) {
    let v10 = Some(CookieKey::Cbc(derive_cbc_key("peanuts")));
    if !needs_keyring {
        return (CookieKeys { v10, v11: None }, None);
    }
    match keyring_password() {
        Ok(password) => (
            CookieKeys {
                v10,
                v11: Some(CookieKey::Cbc(derive_cbc_key(&password))),
            },
            None,
        ),
        Err(reason) => (CookieKeys { v10, v11: None }, Some(reason)),
    }
}

#[cfg(target_os = "linux")]
fn keyring_password() -> Result<String, String> {
    use secret_service::{EncryptionType, SecretService};
    use std::collections::HashMap;
    tauri::async_runtime::block_on(async {
        let service = SecretService::connect(EncryptionType::Dh)
            .await
            .map_err(|e| format!("the desktop keyring is unavailable: {e}"))?;
        let found = service
            .search_items(HashMap::from([("application", "chrome")]))
            .await
            .map_err(|e| format!("the desktop keyring could not be searched: {e}"))?;
        let items: Vec<_> = found.unlocked.into_iter().chain(found.locked).collect();
        for item in items {
            let _ = item.unlock().await;
            if let Ok(secret) = item.get_secret().await {
                if let Ok(password) = String::from_utf8(secret) {
                    if !password.is_empty() {
                        return Ok(password);
                    }
                }
            }
        }
        Err("Chrome's Safe Storage key is not in the desktop keyring".to_string())
    })
}

#[cfg(test)]
pub mod test_support {
    use super::*;
    use aes::cipher::BlockEncryptMut;
    use aes_gcm::aead::Payload;

    pub fn encrypt_cbc(key: &[u8; 16], plain: &[u8]) -> Vec<u8> {
        cbc::Encryptor::<aes::Aes128>::new(key.into(), &CBC_IV.into())
            .encrypt_padded_vec_mut::<Pkcs7>(plain)
    }

    pub fn encrypt_gcm(key: &[u8; 32], nonce: &[u8; 12], plain: &[u8]) -> Vec<u8> {
        let sealed = Aes256Gcm::new(key.into())
            .encrypt(Nonce::from_slice(nonce), Payload::from(plain))
            .unwrap();
        [nonce.as_slice(), &sealed].concat()
    }

    pub fn hashed(host: &str, value: &str) -> Vec<u8> {
        [host_hash(host).as_slice(), value.as_bytes()].concat()
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::*;
    use super::*;

    fn cbc_keys() -> CookieKeys {
        CookieKeys {
            v10: Some(CookieKey::Cbc(derive_cbc_key("peanuts"))),
            v11: Some(CookieKey::Cbc(derive_cbc_key("keyring secret"))),
        }
    }

    #[test]
    fn linux_v10_and_v11_cookies_decrypt_with_cbc() {
        let keys = cbc_keys();
        let v10 = [
            b"v10".as_slice(),
            &encrypt_cbc(&derive_cbc_key("peanuts"), b"session=1"),
        ]
        .concat();
        assert_eq!(
            decrypt(&v10, &keys, "example.com", false).unwrap(),
            "session=1"
        );
        let v11 = [
            b"v11".as_slice(),
            &encrypt_cbc(
                &derive_cbc_key("keyring secret"),
                &hashed(".example.com", "token"),
            ),
        ]
        .concat();
        assert_eq!(decrypt(&v11, &keys, ".example.com", true).unwrap(), "token");
        let without_v11 = CookieKeys { v11: None, ..keys };
        assert_eq!(
            decrypt(&v11, &without_v11, ".example.com", true),
            Err(Skip::KeyringKeyMissing)
        );
    }

    #[test]
    fn windows_v10_cookies_decrypt_with_gcm_and_v20_is_skipped() {
        let key = [7u8; 32];
        let keys = CookieKeys {
            v10: Some(CookieKey::Gcm(key)),
            v11: None,
        };
        let blob = [
            b"v10".as_slice(),
            &encrypt_gcm(&key, &[3u8; 12], &hashed("accounts.example.com", "abc")),
        ]
        .concat();
        assert_eq!(
            decrypt(&blob, &keys, "accounts.example.com", true).unwrap(),
            "abc"
        );
        assert_eq!(
            decrypt(&blob, &keys, "other.example.com", true),
            Err(Skip::Undecryptable)
        );
        let tampered = [&blob[..blob.len() - 1], &[0u8]].concat();
        assert_eq!(
            decrypt(&tampered, &keys, "accounts.example.com", true),
            Err(Skip::Undecryptable)
        );
        assert_eq!(decrypt(b"v20abc", &keys, "a", true), Err(Skip::AppBound));
        assert_eq!(decrypt(b"v1", &keys, "a", true), Err(Skip::Undecryptable));
    }

    #[test]
    fn the_hash_prefix_is_only_stripped_when_it_matches() {
        let keys = cbc_keys();
        let plain = [b"x".repeat(32), b"value".to_vec()].concat();
        let blob = [
            b"v10".as_slice(),
            &encrypt_cbc(&derive_cbc_key("peanuts"), &plain),
        ]
        .concat();
        let value = decrypt(&blob, &keys, "example.com", true).unwrap();
        assert_eq!(value, String::from_utf8(plain).unwrap());
    }

    #[test]
    fn the_windows_master_key_is_base64_with_a_dpapi_prefix() {
        let local_state = serde_json::json!({
            "os_crypt": {"encrypted_key": BASE64_STANDARD.encode(b"DPAPIsecret")}
        });
        assert_eq!(
            dpapi_blob_from_local_state(&local_state).unwrap(),
            b"secret"
        );
        let bad =
            serde_json::json!({"os_crypt": {"encrypted_key": BASE64_STANDARD.encode(b"nope")}});
        assert!(dpapi_blob_from_local_state(&bad).is_err());
        assert!(dpapi_blob_from_local_state(&serde_json::json!({})).is_err());
    }
}
