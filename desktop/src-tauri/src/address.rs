use serde::{Deserialize, Serialize};
use tauri::Url;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SearchEngine {
    #[default]
    Google,
    DuckDuckGo,
    Bing,
    Kagi,
}

impl SearchEngine {
    pub const ALL: [SearchEngine; 4] = [
        SearchEngine::Google,
        SearchEngine::DuckDuckGo,
        SearchEngine::Bing,
        SearchEngine::Kagi,
    ];

    pub fn id(self) -> &'static str {
        match self {
            SearchEngine::Google => "google",
            SearchEngine::DuckDuckGo => "duckduckgo",
            SearchEngine::Bing => "bing",
            SearchEngine::Kagi => "kagi",
        }
    }

    pub fn from_id(id: &str) -> Option<Self> {
        SearchEngine::ALL
            .into_iter()
            .find(|engine| engine.id() == id)
    }

    pub fn title(self) -> &'static str {
        match self {
            SearchEngine::Google => "Google",
            SearchEngine::DuckDuckGo => "DuckDuckGo",
            SearchEngine::Bing => "Bing",
            SearchEngine::Kagi => "Kagi",
        }
    }

    pub fn home(self) -> Url {
        let home = match self {
            SearchEngine::Google => "https://www.google.com/",
            SearchEngine::DuckDuckGo => "https://duckduckgo.com/",
            SearchEngine::Bing => "https://www.bing.com/",
            SearchEngine::Kagi => "https://kagi.com/",
        };
        Url::parse(home).expect("search engine home is a valid url")
    }

    pub fn search_url(self, query: &str) -> Url {
        let mut url = self.home();
        url.set_path(if self == SearchEngine::DuckDuckGo {
            "/"
        } else {
            "/search"
        });
        url.query_pairs_mut().append_pair("q", query);
        url
    }
}

const ALLOWED_SCHEMES: [&str; 5] = ["http", "https", "about", "file", "data"];

pub fn url_for(input: &str, engine: SearchEngine) -> Option<Url> {
    let text = input.trim();
    if text.is_empty() {
        return None;
    }
    direct_url(text).or_else(|| Some(engine.search_url(text)))
}

pub fn direct_url(text: &str) -> Option<Url> {
    if text.contains(' ') {
        return None;
    }
    if let Ok(url) = Url::parse(text) {
        let scheme = url.scheme();
        if ALLOWED_SCHEMES.contains(&scheme)
            && (!matches!(scheme, "http" | "https") || url.host().is_some())
        {
            return Some(url);
        }
    }
    if !looks_like_host(text) {
        return None;
    }
    let scheme = if is_local(text) { "http" } else { "https" };
    Url::parse(&format!("{scheme}://{text}")).ok()
}

pub fn display_text(url: &str) -> &str {
    if url == "about:blank" {
        ""
    } else {
        url
    }
}

fn looks_like_host(text: &str) -> bool {
    let host = text
        .split('/')
        .next()
        .unwrap_or("")
        .split(':')
        .next()
        .unwrap_or("");
    if host.is_empty() {
        return false;
    }
    if host == "localhost" {
        return true;
    }
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() == 4 && host.chars().all(|c| c.is_ascii_digit() || c == '.') {
        return true;
    }
    let Some(tld) = labels.last() else {
        return false;
    };
    labels.len() >= 2
        && labels.iter().all(|label| !label.is_empty())
        && tld.len() >= 2
        && tld.chars().all(|c| c.is_alphabetic())
        && host
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '.')
}

fn is_local(text: &str) -> bool {
    text.starts_with("localhost") || text.starts_with("127.") || text.starts_with("0.0.0.0")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hosts_become_https_urls() {
        assert_eq!(
            direct_url("example.com/path").unwrap().as_str(),
            "https://example.com/path"
        );
        assert_eq!(
            direct_url("localhost:3000").unwrap().as_str(),
            "http://localhost:3000/"
        );
        assert_eq!(
            direct_url("127.0.0.1:8080").unwrap().as_str(),
            "http://127.0.0.1:8080/"
        );
    }

    #[test]
    fn explicit_schemes_are_kept() {
        assert_eq!(
            direct_url("http://example.com").unwrap().as_str(),
            "http://example.com/"
        );
        assert_eq!(direct_url("about:blank").unwrap().as_str(), "about:blank");
        assert!(direct_url("javascript:alert(1)").is_none());
        assert!(direct_url("https://").is_none());
    }

    #[test]
    fn everything_else_is_a_search() {
        let url = url_for("rust cookies", SearchEngine::Google).unwrap();
        assert_eq!(url.as_str(), "https://www.google.com/search?q=rust+cookies");
        let url = url_for("botch", SearchEngine::DuckDuckGo).unwrap();
        assert_eq!(url.as_str(), "https://duckduckgo.com/?q=botch");
        assert!(url_for("   ", SearchEngine::Bing).is_none());
        assert!(direct_url("notahost").is_none());
        assert!(direct_url("a.b").is_none());
    }

    #[test]
    fn engines_round_trip_through_ids() {
        for engine in SearchEngine::ALL {
            assert_eq!(SearchEngine::from_id(engine.id()), Some(engine));
            assert_eq!(
                serde_json::to_string(&engine).unwrap(),
                format!("\"{}\"", engine.id())
            );
        }
        assert_eq!(display_text("about:blank"), "");
        assert_eq!(display_text("https://kagi.com/"), "https://kagi.com/");
    }
}
