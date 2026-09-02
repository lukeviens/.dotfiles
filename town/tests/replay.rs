//! Golden tests over the scrubbed past.log — town's own log as a corpus. Refresh with
//! `cargo run --bin scrub`, then `UPDATE=1 cargo test --test replay` to re-accept.

mod common;
use common::{golden, replay, ROOT};
use serde_json::json;

use town::town::fold;
use town::word::Word;

// a small flow through every resident: a palette change (theme talkback, k9s write, tmux commands),
// a couple places, a flip, a jump. snapshots {present, talkbacks, effects} — the connectors' writes
// and commands become golden.
#[test]
fn replay_a_flow_captures_connector_effects() {
    let seq = vec![
        json!({ "kind": "colors", "tense": "present",
            "body": "# shared palette\nname=dark\nmode=dark\nbg=#1f1d20\nfg=#f8f8f2\nsubtle=#878787\nactive=#f92672\naccent=#66d9ef\n" }),
        json!({ "kind": "theme", "tense": "present",
            "body": { "name": "dark", "mode": "dark", "bg": "#1f1d20", "fg": "#f8f8f2", "subtle": "#878787", "active": "#f92672", "accent": "#66d9ef" } }),
        json!({ "kind": "place", "tense": "present", "body": { "kind": "window", "app": "Chrome" } }),
        json!({ "kind": "place", "tense": "present", "body": { "kind": "session", "name": "work" } }),
        json!({ "kind": "back", "tense": "future", "body": {} }),
        json!({ "kind": "jump", "tense": "future", "body": { "slot": 1 } }),
    ];
    golden("replay_flow", &serde_json::to_string_pretty(&replay(&seq)).unwrap());
}

#[test]
fn fold_over_the_real_corpus() {
    let log = std::fs::read_to_string(format!("{ROOT}/tests/fixtures/real.log"))
        .expect("missing fixture — run `cargo run --bin scrub` to generate tests/fixtures/real.log");
    let present = fold(log.lines().filter_map(Word::from_line));
    golden("fold_corpus", &serde_json::to_string_pretty(&present).unwrap());
}

// the committed fixture must never contain this machine's username. catches a re-scrub that leaks it.
#[test]
fn fixture_has_no_local_username() {
    let user = std::env::var("USER").unwrap_or_default();
    if user.is_empty() {
        return;
    }
    let log = std::fs::read_to_string(format!("{ROOT}/tests/fixtures/real.log")).unwrap();
    assert!(!log.contains(&user), "the scrubbed fixture leaked $USER ({user}) — re-run `cargo run --bin scrub`");
}
