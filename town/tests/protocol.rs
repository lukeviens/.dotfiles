//! Protocol tests — the shape of town, as words in and words out.
//!
//! Each test loads a real resident (residents/*.lua) with the real vocabulary
//! (lib.lua), talks a word at it, and asserts what it talks back. This is the
//! spec of how town composes — living in the repo, not in a dotfiles readme.

mod common;
use common::{effects, feed_file, feed_popen, resident, say, ROOT};

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::json;
use town::word::{Tense, Word};

// ── keys: a key event becomes an intention ──────────────────────────────────
#[test]
fn a_key_becomes_an_intention() {
    let (lua, keys) = resident("keys", json!({}), json!({}));

    assert_eq!(
        say(&lua, &keys, json!({"kind":"key","tense":"past","body":{"at":"leader","press":"f"}})),
        Some(json!({"kind":"pick","tense":"future","body":{"what":"all"}}))
    );

    // the same key, a different surface → a different intention
    let tmux_o = say(&lua, &keys, json!({"kind":"key","body":{"at":"tmux","press":"o"}})).unwrap();
    assert_eq!(tmux_o, json!({"kind":"back","tense":"future","body":{"kind":"session"}}));

    // a digit in town-mode jumps to a favourite
    let one = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"1"}})).unwrap();
    assert_eq!(one["kind"], "jump");
    assert_eq!(one["body"]["slot"], 1);

    // i / o flip forward / back through ALL recent places (no kind filter)
    let fwd = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"i"}})).unwrap();
    assert_eq!(fwd["kind"], "forward");
    assert!(fwd["body"]["kind"].is_null());   // spans windows + sessions, like leader f

    // ⌃b i inside the terminal still flips sessions only
    let tmux_i = say(&lua, &keys, json!({"kind":"key","body":{"at":"tmux","press":"i"}})).unwrap();
    assert_eq!(tmux_i, json!({"kind":"forward","tense":"future","body":{"kind":"session"}}));

    // lowercase hjkl moves focus; uppercase HJKL snaps the window
    let mv = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"h"}})).unwrap();
    assert_eq!(mv, json!({"kind":"move","tense":"future","body":{"dir":"h"}}));
    let snap = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"H"}})).unwrap();
    assert_eq!(snap, json!({"kind":"arrange","tense":"future","body":{"to":"left"}}));

    // an unmapped key means nothing
    assert_eq!(say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"x"}})), None);
}

// ── keys: the keymap describes itself (the leader hint is the map) ───────────
#[test]
fn the_keymap_describes_itself() {
    let (lua, keys) = resident("keys", json!({}), json!({}));
    let hints = say(&lua, &keys, json!({"kind":"hint","body":{"at":"leader"}})).unwrap();
    assert_eq!(hints["kind"], "hints");
    let items = hints["body"]["items"].as_array().unwrap();
    assert!(items.iter().any(|i| i["keys"] == "f" && i["label"] == "all"));
    assert!(items.iter().any(|i| i["keys"] == "1–9" && i["label"] == "favourites")); // nine jumps collapse
}

// ── keys: town owns the whole keymap; the surface binds the chords it's handed ─────
#[test]
fn the_keymap_wires_the_surface() {
    let (lua, keys) = resident("keys", json!({}), json!({}));
    let wiring = say(&lua, &keys, json!({"kind":"wire","tense":"future","body":{}})).unwrap();
    assert_eq!(wiring["kind"], "wiring");
    let binds = wiring["body"]["binds"].as_array().unwrap();
    // one chord survives at the surface: ⌃⏎ zoom (aware — tmux zooms the pane in the terminal).
    // directional motion is Caps-hjkl now (HS emits ⌥hjkl itself), not a bound chord — ⌃ is freed.
    assert!(binds.iter().any(|b| b["key"] == "ctrl return" && b["act"] == "zoom" && b["aware"] == true));
    assert_eq!(binds.len(), 1); // just ⌃⏎ — nothing else
    assert!(!binds.iter().any(|b| b["key"] == "ctrl h")); // ⌃hjkl retired
    assert!(!binds.iter().any(|b| b["key"] == "ctrl alt return"));
    assert!(!binds.iter().any(|b| b["key"] == "ctrl space"));
    assert!(!binds.iter().any(|b| b["key"] == "leader f"));
}

// ── place: the trail flips through recent places, ⌘-tab style ────────────────
#[test]
fn the_trail_flips_through_recent_places() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});

    for app in ["Alpha", "Bravo", "Charlie"] {
        assert_eq!(say(&lua, &place, win(app)), None); // facts extend the trail, talk nothing
    }
    let back = |lua: &Lua, p: &Table| {
        say(lua, p, json!({"kind":"back","tense":"future","body":{"kind":"window"}})).unwrap()["body"]["app"].clone()
    };
    let fwd = |lua: &Lua, p: &Table| {
        say(lua, p, json!({"kind":"forward","tense":"future","body":{"kind":"window"}})).unwrap()["body"]["app"].clone()
    };
    assert_eq!(back(&lua, &place), "Bravo"); // back from Charlie
    assert_eq!(back(&lua, &place), "Alpha");
    assert_eq!(fwd(&lua, &place), "Bravo"); // forward again — nothing lost
}

// ── place: a flip drops its OWN echo. Flipping focuses a real window/session and the surface
// reports it straight back as a present fact (the tmux session hook does this from another process,
// so no surface-side guard catches it). The trail ignores a present fact matching the place the
// cursor is already parked on (`seen[at]`) — the echo of what we just flipped to — so the walk
// holds and descends. It's doubled-echo-proof, and a genuinely different focus still reorders. ──
#[test]
fn a_flip_drops_its_own_echo_even_doubled() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    let back = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"back","tense":"future","body":{"kind":"window"}})).unwrap()["body"]["app"].clone();

    for app in ["Alpha", "Bravo", "Charlie"] { say(&lua, &place, win(app)); } // seen=[Charlie,Bravo,Alpha]

    assert_eq!(back(&lua, &place), "Bravo");   // flip back to Bravo — cursor parks on Bravo
    say(&lua, &place, win("Bravo"));           // its echo…
    say(&lua, &place, win("Bravo"));           // …even doubled — both match seen[at], both dropped
    assert_eq!(back(&lua, &place), "Alpha");   // the walk CONTINUES deep — not dragged to the front

    say(&lua, &place, win("Delta"));           // a genuinely DIFFERENT focus does reorder to front
    assert_eq!(back(&lua, &place), "Charlie"); // seen=[Delta,Charlie,Bravo,Alpha]; back → Charlie
}

// ── place: a pure MRU stack. Walking (back/forward) moves the CURSOR only and never reorders;
// every genuine present focus promotes that place to the front and homes the cursor — like vim
// `:bnext` over a stable buffer list. (A flip's own echo never reaches here: the surface drops the
// focus it caused — init.lua's `expecting` — so the trail only ever sees genuine focuses.) ──
#[test]
fn a_present_focus_reorders_the_trail_to_the_front() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    let back = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"back","tense":"future","body":{"kind":"window"}})).unwrap()["body"]["app"].clone();

    for app in ["Alpha", "Bravo", "Charlie"] { say(&lua, &place, win(app)); } // seen=[Charlie,Bravo,Alpha]

    assert_eq!(back(&lua, &place), "Bravo");   // walk back to Bravo — cursor only, list unchanged
    say(&lua, &place, win("Delta"));           // a genuine focus of Delta → front, cursor homes
    assert_eq!(back(&lua, &place), "Charlie"); // seen=[Delta,Charlie,Bravo,Alpha]; back → Charlie
    say(&lua, &place, win("Alpha"));           // genuine focus of an EXISTING place moves it to front
    assert_eq!(back(&lua, &place), "Delta");   // seen=[Alpha,Delta,Charlie,Bravo]; back → Delta
}

// ── place: flipping past the end is a clean no-op — the cursor must NOT drift out of
// bounds (or you'd have to press the other way N times to "get back in"). ──
#[test]
fn flipping_past_the_end_does_not_drift() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    let fwd = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"forward","tense":"future","body":{}}));
    let back = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"back","tense":"future","body":{}}));

    for app in ["Alpha", "Bravo", "Charlie"] { say(&lua, &place, win(app)); } // at newest = Charlie

    for _ in 0..5 { assert_eq!(fwd(&lua, &place), None); } // crank forward at the top → all no-ops
    // exactly ONE back steps to the adjacent item — the cursor never left index 1
    assert_eq!(back(&lua, &place).unwrap()["body"]["app"], "Bravo");
}

// ── place: empty / single-item trails, and a kind-filter with no such kind, are no-ops.
#[test]
fn degenerate_trails_and_absent_kinds_noop() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    let f = |k: &str| json!({"kind":k,"tense":"future","body":{}});

    assert_eq!(say(&lua, &place, f("back")), None);          // empty trail
    assert_eq!(say(&lua, &place, f("forward")), None);
    say(&lua, &place, win("Solo"));
    assert_eq!(say(&lua, &place, f("back")), None);          // single item
    assert_eq!(say(&lua, &place, f("forward")), None);

    for app in ["Alpha", "Bravo", "Charlie"] { say(&lua, &place, win(app)); } // all windows
    // a session-only flip when no session exists must no-op AND leave the cursor put
    assert_eq!(say(&lua, &place, json!({"kind":"back","tense":"future","body":{"kind":"session"}})), None);
    assert_eq!(say(&lua, &place, f("back")).unwrap()["body"]["app"], "Bravo"); // cursor never moved
}

// ── favourites: remember via present, recall the same ───────────────────────
#[test]
fn favourites_persist_as_a_present_fact() {
    // present already holds the fact (as if folded from the past on boot)
    let present = json!({"favourites": {"1": {"kind":"session","name":"work"}}});
    let (lua, fav) = resident("favourites", present, json!({}));

    // jump recalls it → a future place to go there
    assert_eq!(
        say(&lua, &fav, json!({"kind":"jump","tense":"future","body":{"slot":"1"}})),
        Some(json!({"kind":"place","tense":"future","body":{"kind":"session","name":"work"}}))
    );

    // save merges a new slot and re-talks the whole favourites fact (present → persists)
    let saved = say(&lua, &fav, json!({"kind":"save","body":{"slot":"2","place":{"kind":"app","name":"Linear"}}})).unwrap();
    assert_eq!(saved["kind"], "favourites");
    assert_eq!(saved["tense"], "present");
    assert_eq!(saved["body"]["1"], json!({"kind":"session","name":"work"})); // kept
    assert_eq!(saved["body"]["2"], json!({"kind":"app","name":"Linear"})); // added
}

// ── menu: pick → gather → show → choose, all decided in town ─────────────────
#[test]
fn a_menu_is_pick_gather_show_choose() {
    let (lua, menu) = resident("menu", json!({}), json!({}));

    // pick apps → town asks the surface to gather (it can't list mac apps itself)
    let gather = say(&lua, &menu, json!({"kind":"pick","tense":"future","body":{"what":"apps"}})).unwrap();
    assert_eq!(gather["kind"], "gather");
    assert_eq!(gather["body"]["what"], "apps");

    // the surface returns the list → town shows the labels
    let show = say(&lua, &menu, json!({"kind":"apps","tense":"past","body":{"places":[
        {"kind":"app","name":"Linear"}, {"kind":"app","name":"Chrome"}]}})).unwrap();
    assert_eq!(show["kind"], "show");
    assert_eq!(show["body"]["choices"][0]["label"], "Linear");

    // choosing id 2 → go to Chrome
    assert_eq!(
        say(&lua, &menu, json!({"kind":"chose","tense":"past","body":{"id":"2"}})),
        Some(json!({"kind":"place","tense":"future","body":{"kind":"app","name":"Chrome"}}))
    );
}

// ── menu: the universal picker searches every source at once ─────────────────
#[test]
fn the_universal_picker_merges_every_source() {
    let past = json!({"place": [
        {"kind":"window","app":"Chrome"},
        {"kind":"session","name":"work"}
    ]});
    let (lua, menu) = resident("menu", json!({}), past);

    // pick all → town asks the surface for its live windows + apps
    let gather = say(&lua, &menu, json!({"kind":"pick","tense":"future","body":{"what":"all"}})).unwrap();
    assert_eq!(gather["kind"], "gather");
    assert_eq!(gather["body"]["what"], "all");

    // the surface returns them as `everything` → town folds in its own places + sessions
    let show = say(&lua, &menu, json!({"kind":"everything","tense":"past","body":{"places":[
        {"kind":"window","app":"Chrome","title":""},
        {"kind":"app","name":"Linear"}]}})).unwrap();
    assert_eq!(show["kind"], "show");
    let labels: Vec<&str> = show["body"]["choices"].as_array().unwrap()
        .iter().map(|c| c["label"].as_str().unwrap()).collect();
    assert_eq!(labels[0], "work  ·  session");      // recent places lead, most-recent first
    assert!(labels.contains(&"work  ·  session"));  // from town's own past
    assert!(labels.contains(&"Linear"));            // from the surface's live apps
    assert_eq!(labels.iter().filter(|&&l| l == "Chrome").count(), 1); // past + live Chrome deduped
}

// ── grammar: every constructor in lib.lua must produce a word the ENGINE accepts. A typo'd
// tense would silently deserialize to nothing at runtime (say() drops it) — this catches it
// here, loudly, at test time. Deserializes via the exact path the engine uses (lua.from_value).
#[test]
fn every_constructor_round_trips_into_a_word() {
    let lua = Lua::new();
    let lib = std::fs::read_to_string(format!("{ROOT}/lib.lua")).unwrap();
    lua.load(&lib).set_name("lib").exec().unwrap();

    let cases: &[(&str, Tense)] = &[
        ("fact('theme', {bg='#111'})", Tense::Present),
        ("event('key', {press='f'})", Tense::Past),
        ("intent('place', {kind='window', app='X'})", Tense::Future),
        ("pick('apps')", Tense::Future),
        ("move('h')", Tense::Future),
        ("back('window')", Tense::Future),
        ("forward()", Tense::Future),
        ("jump(3)", Tense::Future),
        ("grep()", Tense::Future),
        ("retheme('random', 'r')", Tense::Future),
        ("arrange('left', 'snap')", Tense::Future),
    ];
    for (expr, want) in cases {
        let v: LuaValue = lua.load(&format!("return {expr}")).eval().unwrap();
        let word: Word = lua
            .from_value(v)
            .unwrap_or_else(|e| panic!("{expr} is not a valid word (engine would drop it): {e}"));
        assert_eq!(word.tense, *want, "{expr} has the wrong tense");
        assert!(!word.kind.is_empty(), "{expr} has an empty kind");
    }
}

// ── sandbox: menu's io.popen(tmux list-sessions) is hermetic now — feed canned sessions and
// assert they flow into the universal picker, with no real tmux and no dev-machine dependency.
#[test]
fn canned_sessions_flow_through_the_picker() {
    let (lua, menu) = resident("menu", json!({}), json!({ "place": [] }));
    feed_popen(&lua, "list-sessions", "alpha\nbravo\n");
    let show = say(&lua, &menu, json!({"kind":"everything","tense":"future","body":{"places":[]}})).unwrap();
    let labels: Vec<String> = show["body"]["choices"].as_array().unwrap()
        .iter().map(|c| c["label"].as_str().unwrap().to_string()).collect();
    assert!(labels.iter().any(|l| l == "alpha  ·  session"), "{labels:?}");
    assert!(labels.iter().any(|l| l == "bravo  ·  session"), "{labels:?}");
}

// ── sandbox: a CONNECTOR resident (theme) is testable at last — its file write is CAPTURED, not
// performed. Cycling the palette (Caps t) writes the next skin; assert the captured content.
#[test]
fn theme_cycle_writes_the_next_skin_as_a_captured_effect() {
    let (lua, theme) = resident("theme", json!({}), json!({}));
    feed_file(&lua, "theme/colors", // current palette → name resolves to "dark", so cycle → "sun"
        "name=dark\nmode=dark\nbg=#1f1d20\nfg=#f8f8f2\nsubtle=#878787\nactive=#f92672\naccent=#66d9ef\n");
    let out = say(&lua, &theme, json!({"kind":"theme","tense":"future","body":{"to":"next"}}));
    assert!(out.is_none(), "a cycle writes the file, it doesn't talk a word back");
    let last_write = effects(&lua).into_iter().rev()
        .find(|e| e["kind"] == "write").expect("theme cycle should have written the palette");
    assert!(last_write["content"].as_str().unwrap().contains("name=sun"), "cycled dark → sun");
}
