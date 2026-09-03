//! Protocol tests — the shape of town, as words in and words out.
//!
//! Each test loads a real resident (residents/*.lua) with the real vocabulary
//! (lib.lua), talks a word at it, and asserts what it talks back. This is the
//! spec of how town composes — living in the repo, not in a dotfiles readme.

mod common;
use common::{effects, feed_file, golden, resident, say, ROOT};

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::{json, Value};
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

    // lowercase hjkl moves focus; uppercase HJKL is HS-owned (the "outer" motion), so town never
    // routes it — a surface key, like the registers.
    let mv = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"h"}})).unwrap();
    assert_eq!(mv, json!({"kind":"move","tense":"future","body":{"dir":"h"}}));
    assert_eq!(say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"H"}})), None);

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
    // surface-handled keys are still in the ONE doc: the registers (edge/cell), split, and the
    // inner/outer zoom all derive into the `?` card — no hand-kept menu to drift.
    // the mesh registers read as one vocabulary — point (hjkl, default) / edge / cell — not "focus".
    assert!(items.iter().any(|i| i["label"] == "point"));                      // hjkl, the default register
    assert!(items.iter().any(|i| i["keys"] == "e" && i["label"] == "edge"));   // arm: resize the wall
    assert!(items.iter().any(|i| i["keys"] == "c" && i["label"] == "cell"));   // arm: carry the tile
    assert!(items.iter().any(|i| i["label"] == "split"));   // % / "
    assert!(items.iter().any(|i| i["label"] == "scroll"));  // d / u half-page
    assert!(items.iter().any(|i| i["label"] == "outer"));   // ⇧hjkl one layer out (Shift = outward)
    assert!(items.iter().any(|i| i["label"] == "zoom"));    // Caps ⏎ inner
    assert!(items.iter().any(|i| i["label"] == "full"));   // Caps ⇧⏎ outer
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

// every constructor must produce a word the engine accepts — a typo'd tense would just vanish at
// runtime (say() drops it). Same deserialize path the engine uses.
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

// sessions the surface gathered reach the picker — menu no longer shells tmux itself.
#[test]
fn sessions_from_the_surface_reach_the_picker() {
    let (lua, menu) = resident("menu", json!({}), json!({ "place": [] }));
    let live = json!([{ "kind": "session", "name": "alpha" }, { "kind": "session", "name": "bravo" }]);
    let show = say(&lua, &menu, json!({ "kind": "everything", "tense": "future", "body": { "places": live } })).unwrap();
    let labels: Vec<String> = show["body"]["choices"].as_array().unwrap()
        .iter().map(|c| c["label"].as_str().unwrap().to_string()).collect();
    assert!(labels.iter().any(|l| l == "alpha  ·  session"), "{labels:?}");
    assert!(labels.iter().any(|l| l == "bravo  ·  session"), "{labels:?}");
}

// a connector resident under test: theme's file write is captured, not performed. cycle → next skin.
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

// ── the trail (Caps o/i), one full walk: build, walk down, swallow the flip's own echo, walk up,
// past-the-end no-op, reorder, the o/i case (a real re-focus of a flipped-through place reorders,
// isn't swallowed), kind filter. The snapshot records where each flip lands — read it to check the
// walk is ⌘-tab / :bnext. ──
#[test]
fn the_trail_walk_pinned() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({ "kind": "place", "tense": "present", "body": { "kind": "window", "app": app } });
    let back = json!({ "kind": "back", "tense": "future", "body": {} });
    let fwd = json!({ "kind": "forward", "tense": "future", "body": {} });
    let back_session = json!({ "kind": "back", "tense": "future", "body": { "kind": "session" } });

    let steps: Vec<(&str, Value)> = vec![
        ("focus Alpha", win("Alpha")),
        ("focus Bravo", win("Bravo")),
        ("focus Charlie", win("Charlie")),          // stack: [Charlie, Bravo, Alpha], cursor at front
        ("back", back.clone()),                     // → Bravo
        ("back", back.clone()),                     // → Alpha
        ("echo Alpha (flip's own echo — swallow)", win("Alpha")),
        ("forward", fwd.clone()),                   // → Bravo
        ("forward", fwd.clone()),                   // → Charlie
        ("forward at front (no-op)", fwd.clone()),
        ("focus Delta (genuine → front)", win("Delta")),
        ("back", back.clone()),                     // → Charlie
        ("focus Bravo (o/i case: flipped-through → refocus reorders)", win("Bravo")),
        ("back", back.clone()),                     // → Delta (proves Bravo went to front)
        ("back session (no session → no-op)", back_session),
    ];

    let mut trace = Vec::new();
    for (label, word) in steps {
        let landed = say(&lua, &place, word)
            .map(|w| w["body"]["app"].clone())
            .unwrap_or(Value::Null);
        trace.push(json!({ "step": label, "lands_on": landed }));
    }
    golden("trail_walk", &serde_json::to_string_pretty(&Value::Array(trace)).unwrap());
}

// ── the universal picker (Caps f), pinned: town's recent places + the surface's live windows/apps
// + tmux sessions, merged and deduped, order kept. read the snapshot to check the merge. ──
#[test]
fn the_menu_merge_pinned() {
    let past = json!({ "place": [
        { "kind": "window", "app": "Chrome" },
        { "kind": "session", "name": "work" },
        { "kind": "window", "app": "Slack" },
    ] });
    let (lua, menu) = resident("menu", json!({}), past);
    let live = json!([ // the surface now gathers windows, apps AND sessions
        { "kind": "window", "app": "Chrome" }, // dups a recent window
        { "kind": "app", "name": "Linear" },   // new
        { "kind": "session", "name": "work" }, // dups the recent session
        { "kind": "session", "name": "mind" }, // new
    ]);
    let show = say(&lua, &menu, json!({ "kind": "everything", "tense": "future", "body": { "places": live } })).unwrap();
    golden("menu_merge", &serde_json::to_string_pretty(&show["body"]["choices"]).unwrap());
}

// ── favourites (Caps 1-9): save pins a place; jump recalls it, or falls back to a default. ──
#[test]
fn favourites_flow_pinned() {
    let save = |slot: i32, app: &str|
        json!({ "kind": "save", "tense": "future", "body": { "slot": slot, "place": { "kind": "window", "app": app } } });
    let jump = |slot: i32| json!({ "kind": "jump", "tense": "future", "body": { "slot": slot } });

    let mut trace = Vec::new();
    let (lua, fav) = resident("favourites", json!({}), json!({}));
    trace.push(json!({ "step": "save 2 = Slack", "result": say(&lua, &fav, save(2, "Slack")) }));
    let (lua, fav) = resident("favourites", json!({ "favourites": { "2": { "kind": "window", "app": "Slack" } } }), json!({}));
    trace.push(json!({ "step": "jump 2 (saved)", "result": say(&lua, &fav, jump(2)) }));
    let (lua, fav) = resident("favourites", json!({}), json!({}));
    trace.push(json!({ "step": "jump 1 (default)", "result": say(&lua, &fav, jump(1)) }));
    trace.push(json!({ "step": "jump 9 (unsaved, no default)", "result": say(&lua, &fav, jump(9)) }));
    golden("favourites_flow", &serde_json::to_string_pretty(&Value::Array(trace)).unwrap());
}
