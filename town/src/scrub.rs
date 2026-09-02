//! Scrub a real past.log into a shareable fixture. Fail-closed: every string word is tokenized
//! unless it's vocabulary the code knows — a kind, enum, key, hex, or number. So a name, a title, a
//! path segment gets scrubbed whether or not its field was ever named; an incomplete SAFE list only
//! tokenizes more, never less. Tokens are a salted hash in one namespace, so `mind` the session and
//! `…/code/mind` the cwd land on the same token and relations survive. Salt + codebook are local +
//! gitignored. Raw logs only.

use std::collections::{BTreeMap, HashSet};

use serde_json::Value;

use crate::word::Word;

/// Words the code understands, not data: enums residents branch on, palette-blob keys, generic path
/// segments (readability only), public apps. Everything else is data → tokenized. Missing a word
/// just tokenizes it, so this is safe to grow — but only add structural tokens, never a data-ish one.
const SAFE: &[&str] = &[
    // place kinds · pick targets · move dirs · arrange targets · key.at · theme names & modes
    "window", "session", "app", "all", "apps", "windows", "sessions",
    "h", "j", "k", "l", "left", "right", "top", "bottom", "max", "fullscreen",
    "leader", "tmux", "next", "dark", "light", "sun", "black", "random",
    // palette-blob words (the `colors` value is a raw key=value string; base00–0F handled below)
    "shared", "palette", "name", "mode", "bg", "fg", "subtle", "active", "accent",
    // generic path segments — readability only; personal segments still tokenize
    "Users", "code", "var", "folders", "private", "T", "Library", "home", "Applications",
    "System", "Utilities", "opt", "homebrew", "bin", "usr", "Caches", "cache", "config",
    "local", "share", "nvim", "cargo", "target", "release", "tmp",
    // known public apps (not personal) — kept readable
    "Chrome", "Google", "WezTerm", "Slack", "Spotify", "Zoom", "Linear", "Finder", "Safari",
    "Notes", "Messages", "Mail", "Terminal", "Code", "Figma", "Notion", "Discord", "Obsidian",
    "Hammerspoon", "Settings", "Calculator", "1Password",
];

pub struct Scrubber {
    salt: [u8; 16],
    safe: HashSet<&'static str>,
    pub codebook: BTreeMap<String, String>, // token → original word, for LOCAL debugging (gitignored)
}

impl Scrubber {
    pub fn new(salt: [u8; 16], _user: String) -> Self {
        Scrubber { salt, safe: SAFE.iter().copied().collect(), codebook: BTreeMap::new() }
    }

    /// Scrub one word: walk its body and rewrite every string value. The kind and tense are the
    /// vocabulary itself, never touched.
    pub fn scrub(&mut self, mut w: Word) -> Word {
        self.walk(&mut w.body);
        w
    }

    fn walk(&mut self, v: &mut Value) {
        match v {
            Value::String(s) => *s = self.scrub_str(s),
            Value::Array(a) => a.iter_mut().for_each(|e| self.walk(e)),
            Value::Object(o) => o.values_mut().for_each(|e| self.walk(e)), // keys kept, values scrubbed
            _ => {}
        }
    }

    /// Walk word by word: keep separators + safe/number/hex words (hex only right after `#`),
    /// tokenize the rest. Shape survives — paths stay paths, the palette stays a palette.
    fn scrub_str(&mut self, s: &str) -> String {
        let mut out = String::new();
        let mut word = String::new();
        let mut prev = ' '; // the char immediately before the current word run
        for c in s.chars() {
            if c.is_alphanumeric() || c == '_' {
                word.push(c);
            } else {
                self.flush(&mut word, prev, &mut out);
                out.push(c);
                prev = c;
            }
        }
        self.flush(&mut word, prev, &mut out);
        out
    }

    fn flush(&mut self, word: &mut String, prev: char, out: &mut String) {
        if word.is_empty() {
            return;
        }
        let keep = self.safe.contains(word.as_str())
            || word.bytes().all(|b| b.is_ascii_digit())            // numbers, pids, slots
            || is_base_key(word)                                   // base00–base0F
            || (prev == '#' && is_hex(word)); // #rrggbb / #rgb colour bodies
        if keep {
            out.push_str(word);
        } else {
            out.push_str(&self.tok(word));
        }
        word.clear();
    }

    /// A stable token for a data word: `tok_<7 hex>`, one namespace so equal words always collide
    /// (that's the correlation the residents rely on). Case-folded so `Mind`/`mind` map together.
    fn tok(&mut self, word: &str) -> String {
        let h = fnv1a(&self.salt, &word.to_lowercase());
        let token = format!("tok_{:07x}", h & 0xfff_ffff);
        self.codebook.entry(token.clone()).or_insert_with(|| word.to_string());
        token
    }
}

fn is_hex(w: &str) -> bool {
    (w.len() == 6 || w.len() == 3) && w.bytes().all(|b| b.is_ascii_hexdigit())
}

fn is_base_key(w: &str) -> bool {
    w.len() == 6 && w.starts_with("base") && w[4..].bytes().all(|b| b.is_ascii_hexdigit())
}

/// FNV-1a over salt ‖ word — a small, STABLE keyed hash (no crypto dep). The secret salt is what
/// makes a token non-reversible by anyone holding only the fixture.
fn fnv1a(salt: &[u8; 16], word: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in salt.iter().copied().chain(word.bytes()) {
        h ^= b as u64;
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn scrubber() -> Scrubber {
        Scrubber::new([7u8; 16], "lukeviens".into())
    }
    fn word(kind: &str, body: Value) -> Word {
        Word { kind: kind.into(), tense: crate::word::Tense::Present, body }
    }

    #[test]
    fn tokens_are_stable_and_case_folded() {
        let mut s = scrubber();
        assert_eq!(s.tok("mind"), s.tok("mind"));
        assert_eq!(s.tok("Mind"), s.tok("mind")); // case-folded → same project
        assert_ne!(s.tok("mind"), s.tok("eden"));
        assert!(s.tok("mind").starts_with("tok_"));
    }

    #[test]
    fn session_name_and_cwd_leaf_collide_by_design() {
        let mut s = scrubber();
        let sess = s.scrub(word("place", json!({ "kind": "session", "name": "mind" })));
        let focus = s.scrub(word("focus", json!({ "cwd": "/Users/lukeviens/code/mind" })));
        let tok = sess.body["name"].as_str().unwrap();
        assert!(tok.starts_with("tok_"));
        assert!(focus.body["cwd"].as_str().unwrap().ends_with(&format!("/code/{tok}")));
    }

    #[test]
    fn fail_closed_an_unknown_kind_and_field_is_still_scrubbed() {
        // a field we never named still gets scrubbed.
        let mut s = scrubber();
        let w = s.scrub(word("some_new_kind", json!({ "mystery": "TopSecretProject", "nested": ["Another Secret"] })));
        let dump = w.to_line();
        assert!(!dump.contains("TopSecretProject"), "unknown field leaked: {dump}");
        assert!(!dump.contains("Secret"), "nested unknown value leaked: {dump}");
    }

    #[test]
    fn no_known_pii_survives_but_shapes_do() {
        let mut s = scrubber();
        let focus = s.scrub(word("focus", json!({
            "cwd": "/Users/lukeviens/code/mind",
            "pane": "%56",
            "socket": "/var/folders/m3/HASH/T/nvim.lukeviens/rand/nvim.51167.0",
        })));
        let place = s.scrub(word("place", json!({ "kind": "window", "app": "AcmeInternalTool", "title": "Re: layoffs" })));
        let dump = format!("{}{}", focus.to_line(), place.to_line());
        for pii in ["lukeviens", "AcmeInternalTool", "layoffs"] {
            assert!(!dump.contains(pii), "PII `{pii}` leaked: {dump}");
        }
        // shape survives: the path skeleton, the pane id, a known app, and hex colours read cleanly
        assert!(focus.body["cwd"].as_str().unwrap().starts_with("/Users/"));
        assert!(focus.body["cwd"].as_str().unwrap().contains("/code/"));
        assert_eq!(focus.body["pane"], "%56"); // numbers kept
        assert_eq!(place.body["kind"], "window"); // enum kept
    }

    #[test]
    fn the_palette_blob_and_hex_are_preserved() {
        let mut s = scrubber();
        let colors = s.scrub(word("colors", json!(
            "# shared palette\nname=dark\nbg=#1f1d20\nbase08=#fa4c8b\n"
        )));
        let blob = colors.body.as_str().unwrap();
        assert!(blob.contains("name=dark"), "palette keys/enums kept: {blob}");
        assert!(blob.contains("bg=#1f1d20"), "hex colours kept: {blob}");
    }
}
