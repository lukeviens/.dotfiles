//! `cargo run --bin scrub` — scrub the real ~/.cache/town/past.log into the committed golden
//! fixture tests/fixtures/real.log. The token salt (tests/fixtures/.salt) and the token→original
//! codebook (tests/fixtures/.codebook.json) are machine-local and gitignored. Re-run to refresh
//! the corpus after real usage; the fixture diff is minimal because tokens are stable.

use std::io::{BufRead, Read};

use town::scrub::Scrubber;
use town::word::Word;

fn main() {
    let home = std::env::var("HOME").expect("town scrub: $HOME");
    let root = env!("CARGO_MANIFEST_DIR");
    let log = format!("{home}/.cache/town/past.log");
    let fixtures = format!("{root}/tests/fixtures");
    std::fs::create_dir_all(&fixtures).expect("mkdir fixtures");

    let salt = load_or_make_salt(&format!("{fixtures}/.salt"));
    let mut sc = Scrubber::new(salt);

    let f = std::fs::File::open(&log).unwrap_or_else(|e| panic!("open {log}: {e}"));
    let mut out = String::new();
    let (mut kept, mut dropped) = (0u32, 0u32);
    for line in std::io::BufReader::new(f).lines().map_while(Result::ok) {
        match Word::from_line(&line) {
            Some(w) => {
                out.push_str(&sc.scrub(w).to_line());
                out.push('\n');
                kept += 1;
            }
            None => dropped += 1, // malformed / blank — the engine drops these too
        }
    }

    std::fs::write(format!("{fixtures}/real.log"), &out).expect("write real.log");
    std::fs::write(
        format!("{fixtures}/.codebook.json"),
        serde_json::to_string_pretty(&sc.codebook).unwrap(),
    )
    .expect("write codebook");

    eprintln!(
        "scrubbed {kept} words ({dropped} dropped) → {fixtures}/real.log · {} tokens in .codebook.json",
        sc.codebook.len()
    );
}

/// Read the persistent 16-byte salt, or mint one from /dev/urandom and save it. Machine-local +
/// gitignored: stable so re-scrubs diff minimally, secret so tokens can't be reversed from the fixture.
fn load_or_make_salt(path: &str) -> [u8; 16] {
    if let Ok(bytes) = std::fs::read(path) {
        if bytes.len() >= 16 {
            let mut s = [0u8; 16];
            s.copy_from_slice(&bytes[..16]);
            return s;
        }
    }
    let mut s = [0u8; 16];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut s))
        .expect("read /dev/urandom for salt");
    std::fs::write(path, s).expect("write .salt");
    s
}
