//! Protocol tests — the shape of town, as words in and words out.
//!
//! Each test loads a real resident (residents/*.lua) with the real vocabulary
//! (lib.lua), talks a word at it, and asserts what it talks back. This is the
//! spec of how town composes — living in the repo, not in a dotfiles readme.

mod common;
use common::{effects, feed_file, golden, resident, say, talked, ROOT};

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::{json, Value};
use town::word::{Tense, Word};

// ── keys: a key event becomes an intention ──────────────────────────────────
#[test]
fn a_key_becomes_an_intention() {
    let (lua, keys) = resident("keys", json!({}), json!({}));

    assert_eq!(
        say(&lua, &keys, json!({"kind":"key","tense":"past","body":{"at":"leader","press":"f"}})),
        Some(json!({"kind":"menu","tense":"future","body":{"what":"all"}}))
    );

    // the same key, a different surface → a different intention
    let tmux_o = say(&lua, &keys, json!({"kind":"key","body":{"at":"tmux","press":"o"}})).unwrap();
    assert_eq!(tmux_o, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"session"}}));

    // a digit in town-mode jumps to a favourite
    let one = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"1"}})).unwrap();
    assert_eq!(one["kind"], "place");
    assert_eq!(one["body"]["slot"], 1);

    // outer depth walks mac windows, even when sessions are interleaved in the place trail
    let fwd = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"i"}})).unwrap();
    assert_eq!(fwd["kind"], "place");
    assert_eq!(fwd["body"]["step"], -1);
    assert_eq!(fwd["body"]["kind"], "window");

    // ⌃b i inside the terminal still flips sessions only
    let tmux_i = say(&lua, &keys, json!({"kind":"key","body":{"at":"tmux","press":"i"}})).unwrap();
    assert_eq!(tmux_i, json!({"kind":"place","tense":"future","body":{"step":-1,"kind":"session"}}));

    // the same key inside Chrome walks its tabs
    let chrome_o = say(&lua, &keys, json!({"kind":"key","body":{"at":"chrome","press":"o"}})).unwrap();
    assert_eq!(chrome_o, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"tab"}}));

    // lowercase hjkl moves focus; uppercase HJKL is HS-owned (the "outer" motion), so town never
    // routes it — a surface key, like the registers.
    let mv = say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"h"}})).unwrap();
    assert_eq!(mv, json!({"kind":"move","tense":"future","body":{"dir":"h"}}));
    assert_eq!(say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"H"}})), None);

    // an unmapped key means nothing
    assert_eq!(say(&lua, &keys, json!({"kind":"key","body":{"at":"leader","press":"x"}})), None);
}

/// The keymap's substrate (~/.cache/town/keys), as the sandbox captured it: the lines with a
/// prefix, each as { keys, label } for hints or { key, act, aware } for binds.
fn keymap_lines(lua: &Lua, prefix: &str) -> Vec<Value> {
    let w = effects(lua).into_iter().find(|e| e["kind"] == "write" && e["path"].as_str().unwrap_or("").ends_with("/keys"))
        .expect("the keymap writes its substrate at load");
    w["content"].as_str().unwrap().lines().filter(|l| l.starts_with(prefix)).map(|l| {
        let f: Vec<&str> = l.split('\t').collect();
        if f[0] == "hint" { json!({ "keys": f[2], "label": f[3] }) }
        else { json!({ "key": f[1], "act": f[2], "aware": f.get(3).map(|a| *a == "aware").unwrap_or(false) }) }
    }).collect()
}

// ── keys: the keymap describes itself (the leader hint is the map) ───────────
#[test]
fn the_keymap_describes_itself() {
    let (lua, _) = resident("keys", json!({}), json!({}));
    let items = keymap_lines(&lua, "hint\tleader\t");   // the substrate written at load: the ? card
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
    // Caps ⏎ zooms the inner pane; Caps ⇧⏎ goes straight to mac maximize.
    assert!(items.iter().any(|i| i["label"] == "zoom" && i["keys"] == "return"));
    assert!(items.iter().any(|i| i["label"] == "maximize" && i["keys"] == "S-return"));
}

// ── keys: town owns the whole keymap; the surface binds the chords it's handed ─────
#[test]
fn the_keymap_wires_the_surface() {
    let (lua, _) = resident("keys", json!({}), json!({}));
    let binds = keymap_lines(&lua, "bind\t");
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
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"window"}})).unwrap()["body"]["app"].clone()
    };
    let fwd = |lua: &Lua, p: &Table| {
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":-1,"kind":"window"}})).unwrap()["body"]["app"].clone()
    };
    assert_eq!(back(&lua, &place), "Bravo"); // back from Charlie
    assert_eq!(back(&lua, &place), "Alpha");
    assert_eq!(fwd(&lua, &place), "Bravo"); // forward again — nothing lost
}

#[test]
fn windows_of_one_app_have_separate_places() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |win_id: i64, title: &str| json!({"kind":"place","tense":"present","body":{
        "kind":"window","app":"Chrome","winId":win_id,"title":title
    }});
    let back = json!({"kind":"place","tense":"future","body":{"step":1,"kind":"window"}});

    say(&lua, &place, win(10, "First"));
    say(&lua, &place, win(20, "Second"));
    assert_eq!(say(&lua, &place, back.clone()).unwrap()["body"]["winId"], 10);
    say(&lua, &place, win(10, "Renamed")); // focus echo with a changed title keeps its id
    assert_eq!(say(&lua, &place, back), None);
}

#[test]
fn window_and_session_flips_keep_independent_positions() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let focus = |kind: &str, name: &str| {
        if kind == "window" {
            json!({"kind":"place","tense":"present","body":{"kind":kind,"app":name}})
        } else {
            json!({"kind":"place","tense":"present","body":{"kind":kind,"name":name}})
        }
    };
    let step = |kind: &str, n: i32| json!({"kind":"place","tense":"future","body":{"kind":kind,"step":n}});
    say(&lua, &place, focus("window", "A"));
    say(&lua, &place, focus("session", "one"));
    say(&lua, &place, focus("window", "B"));
    say(&lua, &place, focus("session", "two"));
    assert_eq!(say(&lua, &place, step("window", 1)).unwrap()["body"]["app"], "A");
    assert_eq!(say(&lua, &place, step("session", 1)).unwrap()["body"]["name"], "one");
    assert_eq!(say(&lua, &place, step("window", -1)).unwrap()["body"]["app"], "B");
    assert_eq!(say(&lua, &place, step("session", -1)).unwrap()["body"]["name"], "two");
}

// ── tmux: a motion is a word, and the table turns it into a tmux command. Nothing synthesizes a
// keystroke for tmux to match any more — the command runs in our client's context, and our client
// shadows your session, so "current pane" is the one you are looking at. ──
#[test]
fn a_motion_becomes_the_tmux_command_for_it() {
    let (lua, tmux) = resident("tmux", json!({}), json!({}));
    let motion = |verb: &str, dir: &str| json!({ "kind": "transport", "tense": "future",
        "body": { "verb": verb, "dir": dir } });

    let w = say(&lua, &tmux, motion("point", "h")).unwrap();
    assert_eq!(w["kind"], "work");
    assert_eq!(w["body"]["at"], "tmux");
    let cmd = w["body"]["cmd"].as_str().unwrap().to_string();
    assert!(cmd.starts_with("if -F '#{m:*vim*"), "whoever occupies the pane is asked first: {cmd}");
    assert!(cmd.contains("send-keys M-h"), "a vim pane gets the key");
    assert!(cmd.contains("select-pane -L"), "otherwise tmux moves");
    assert!(cmd.contains("select-pane -t '{right}'"), "and at the left edge it wraps");

    let cell = say(&lua, &tmux, motion("cell", "l")).unwrap();
    assert!(cell["body"]["cmd"].as_str().unwrap().contains("swap-pane -t '{right-of}'"));
    assert_eq!(say(&lua, &tmux, motion("zoom", "z")).unwrap()["body"]["cmd"], "resize-pane -Z");
    assert_eq!(say(&lua, &tmux, motion("tab", "next")).unwrap()["body"]["cmd"], "next-window");

    // flip never reaches tmux unless the pane is vim: the session trail is town's own, so there
    // is nothing to fork a shell for
    let (lua2, t2) = resident("tmux", json!({ "vim": { "active": "0" } }), json!({}));
    assert_eq!(say(&lua2, &t2, motion("flip", "o")).unwrap(),
        json!({ "kind": "place", "tense": "future", "body": { "step": 1, "kind": "session" } }));
    assert_eq!(say(&lua2, &t2, motion("flip", "i")).unwrap()["body"]["step"], -1);

    let (lua3, t3) = resident("tmux", json!({ "vim": { "active": "1" } }), json!({}));
    let w = say(&lua3, &t3, motion("flip", "o")).unwrap();
    assert_eq!(w["body"]["cmd"], "send-keys M-o", "a vim pane gets the key, for its buffers");
    assert_eq!(w["body"]["at"], "tmux");

    // a motion the table does not name says nothing rather than guessing
    assert_eq!(say(&lua, &tmux, motion("point", "x")), None);
    assert_eq!(say(&lua, &tmux, motion("nonsense", "h")), None);
}

// ── tmux: what town does NOT care about passes, and our own move is not where you are. ──
#[test]
fn a_line_from_the_joined_tmux_says_where_you_went() {
    let (lua, tmux) = resident("tmux", json!({}), json!({}));
    let line = |l: &str| json!({ "kind": "tmux", "tense": "past", "body": l });

    let w = say(&lua, &tmux, line("%client-session-changed client-18228 $38 retool")).unwrap();
    assert_eq!(w, json!({ "kind": "place", "tense": "present",
        "body": { "kind": "session", "name": "retool" } }));
    // …and we follow you onto it, or everything we ask would describe a session you are not in
    let follow = talked(&lua).pop().expect("the link follows your client");
    assert_eq!(follow["body"]["cmd"], "switch-client -t '=retool'");

    // a session name with a space survives whole
    let w = say(&lua, &tmux, line("%client-session-changed client-1 $2 my work")).unwrap();
    assert_eq!(w["body"]["name"], "my work");

    // our own move is not where YOU are — but it does change what we are describing, so ask
    let w = say(&lua, &tmux, line("%session-changed $37 ours")).unwrap();
    assert!(w["body"]["cmd"].as_str().unwrap().starts_with("display-message -p 'town|"));
    // so does a pane change, and so does a session coming or going
    assert!(say(&lua, &tmux, line("%window-pane-changed @3 %21")).is_some());
    assert!(say(&lua, &tmux, line("%sessions-changed")).is_some());

    // the subscription still catches a command that changes in place, moving no pane
    let w = say(&lua, &tmux, line("%subscription-changed vim $7 - - - : claude")).unwrap();
    assert_eq!(w, json!({ "kind": "vim", "tense": "present", "body": { "active": "0" } }));

    // the rest of the protocol is not ours to care about
    assert_eq!(say(&lua, &tmux, line("%window-renamed @35 zsh")), None);
    assert_eq!(say(&lua, &tmux, line("")), None);
}

// ── tmux: a reply that names itself. `source-file` answers with one block per line in the file,
// so nothing can match a reply to its command by position — the answer carries its own label and
// everything town needs from the terminal arrives in one line. ──
#[test]
fn one_labelled_line_carries_the_whole_terminal() {
    let (lua, tmux) = resident("tmux", json!({}), json!({}));
    let line = |l: &str| json!({ "kind": "tmux", "tense": "past", "body": l });

    // the connection coming up: ask, and set the backstop subscription
    let w = say(&lua, &tmux, json!({ "kind": "tmux", "tense": "past", "body": null })).unwrap();
    assert_eq!(w["body"]["at"], "tmux");
    assert!(w["body"]["cmd"].as_str().unwrap().starts_with("display-message -p 'town|"));
    let said = talked(&lua);
    assert!(said.iter().any(|t| t["body"]["cmd"].as_str().unwrap_or("").starts_with("refresh-client -B")));

    // the answer: where you are, what occupies the pane, and what exists — in one line
    let w = say(&lua, &tmux, line("town|retool|nvim|retool,infra,notes")).unwrap();
    assert_eq!(w, json!({ "kind": "place", "tense": "present",
        "body": { "kind": "session", "name": "retool" } }));
    let also = talked(&lua);
    let vim = also.iter().find(|t| t["kind"] == "vim").expect("the pane's occupant");
    assert_eq!(vim["body"]["active"], "1");
    let sessions = also.iter().find(|t| t["kind"] == "sessions").expect("what exists");
    assert_eq!(sessions["body"]["names"], json!(["retool", "infra", "notes"]));

    // and it is positional in nothing: an unrelated block between does not disturb it
    say(&lua, &tmux, line("%begin 1 2 1"));
    say(&lua, &tmux, line("some other command's output"));
    say(&lua, &tmux, line("%end 1 2 1"));
    let w = say(&lua, &tmux, line("town|infra|zsh|retool,infra")).unwrap();
    assert_eq!(w["body"]["name"], "infra");
    assert_eq!(talked(&lua).iter().filter(|t| t["kind"] == "vim").last().unwrap()["body"]["active"], "0");
}

// ── tmux: entering a session is ONE command, and its failure is the answer. switch-client exits
// nonzero when the session is gone, which is how the trail hears the place is no more — nothing
// has to ask first, and nothing blocks the runtime waiting to be told. ──
#[test]
fn entering_a_session_heals_the_trail_when_it_is_gone() {
    let (lua, tmux) = resident("tmux", json!({}), json!({}));
    let enter = json!({ "kind": "place", "tense": "future", "body": { "kind": "session", "name": "work" } });

    let w = say(&lua, &tmux, enter).expect("entering a session is work");
    assert_eq!(w["kind"], "work");
    assert_eq!(w["tense"], "future");
    assert_eq!(w["body"]["about"], "session");
    assert_eq!(w["body"]["name"], "work");
    let cmd = w["body"]["cmd"].as_str().unwrap();
    assert!(cmd.contains("switch-client -t '=work'"), "exact match, not a prefix: {cmd}");
    assert!(!cmd.contains("has-session"), "one command — the failure is the answer");

    // it worked → raise the terminal too
    let ok = json!({ "kind": "work", "tense": "past",
        "body": { "about": "session", "name": "work", "code": 0 } });
    let w = say(&lua, &tmux, ok).unwrap();
    assert_eq!(w, json!({ "kind": "place", "tense": "future",
        "body": { "kind": "window", "app": "WezTerm" } }));

    // it failed → the session is no more, and the trail walks on
    let gone = json!({ "kind": "work", "tense": "past",
        "body": { "about": "session", "name": "work", "code": 1 } });
    let w = say(&lua, &tmux, gone).unwrap();
    assert_eq!(w, json!({ "kind": "place", "tense": "past",
        "body": { "kind": "session", "name": "work" } }));

    // another resident's work is not ours to answer
    let other = json!({ "kind": "work", "tense": "past", "body": { "code": 1, "where": "x:1" } });
    assert_eq!(say(&lua, &tmux, other), None);
}

// ── place: tabs share one mac window, so they are told apart by Chrome's id — not by app name
// (every tab folds into one place and o/i does nothing) and not by position (renumbers on a close
// or a drag). ──
#[test]
fn tabs_of_one_window_are_separate_places_and_walk_their_own_trail() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let tab = |id: i64| json!({"kind":"place","tense":"present",
        "body":{"kind":"tab","app":"Google Chrome","winId":7,"tabId":id}});
    let step = |kind: &str, n: i32| json!({"kind":"place","tense":"future","body":{"kind":kind,"step":n}});

    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    for app in ["WezTerm", "Google Chrome"] { say(&lua, &place, win(app)); }
    for id in [101, 102, 103] { say(&lua, &place, tab(id)); }   // tabs seen = [103, 102, 101]

    // back walks tabs by recency, not by tab position
    assert_eq!(say(&lua, &place, step("tab", 1)).unwrap()["body"]["tabId"], 102);
    assert_eq!(say(&lua, &place, step("tab", 1)).unwrap()["body"]["tabId"], 101);
    assert_eq!(say(&lua, &place, step("tab", -1)).unwrap()["body"]["tabId"], 102);

    // the tab cursor and the window cursor are independent, as window and session already are
    assert_eq!(say(&lua, &place, step("window", 1)).unwrap()["body"]["app"], "WezTerm");
    assert_eq!(say(&lua, &place, step("tab", -1)).unwrap()["body"]["tabId"], 103);
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
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"window"}})).unwrap()["body"]["app"].clone();

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
// `:bnext` over a stable buffer list. (A flip's own echo is dropped by the trail itself: a present
// fact whose key matches the cursor's place.) ──
#[test]
fn a_present_focus_reorders_the_trail_to_the_front() {
    let (lua, place) = resident("place", json!({}), json!({}));
    let win = |app: &str| json!({"kind":"place","tense":"present","body":{"kind":"window","app":app}});
    let back = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"window"}})).unwrap()["body"]["app"].clone();

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
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":-1}}));
    let back = |lua: &Lua, p: &Table|
        say(lua, p, json!({"kind":"place","tense":"future","body":{"step":1}}));

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
    let f = |step: i32| json!({"kind":"place","tense":"future","body":{"step":step}});

    assert_eq!(say(&lua, &place, f(1)), None);          // empty trail
    assert_eq!(say(&lua, &place, f(-1)), None);
    say(&lua, &place, win("Solo"));
    assert_eq!(say(&lua, &place, f(1)), None);          // single item
    assert_eq!(say(&lua, &place, f(-1)), None);

    for app in ["Alpha", "Bravo", "Charlie"] { say(&lua, &place, win(app)); } // all windows
    // a session-only flip when no session exists must no-op AND leave the cursor put
    assert_eq!(say(&lua, &place, json!({"kind":"place","tense":"future","body":{"step":1,"kind":"session"}})), None);
    assert_eq!(say(&lua, &place, f(1)).unwrap()["body"]["app"], "Bravo"); // cursor never moved
}

// ── favourites: remember via present, recall the same ───────────────────────
#[test]
fn favourites_persist_as_a_present_fact() {
    // present already holds the fact (as if folded from the past on boot)
    let present = json!({"favourites": {"1": {"kind":"session","name":"work"}}});
    let (lua, fav) = resident("favourites", present, json!({}));

    // jump recalls it → a future place to go there
    assert_eq!(
        say(&lua, &fav, json!({"kind":"place","tense":"future","body":{"slot":"1"}})),
        Some(json!({"kind":"place","tense":"future","body":{"kind":"session","name":"work"}}))
    );

    // save merges a new slot and re-talks the whole favourites fact (present → persists)
    let saved = say(&lua, &fav, json!({"kind":"favourites","tense":"future","body":{"slot":"2","place":{"kind":"app","name":"Linear"}}})).unwrap();
    assert_eq!(saved["kind"], "favourites");
    assert_eq!(saved["tense"], "present");
    assert_eq!(saved["body"]["1"], json!({"kind":"session","name":"work"})); // kept
    assert_eq!(saved["body"]["2"], json!({"kind":"app","name":"Linear"})); // added
}

// ── menu: wished, listed, shown, ended — all decided in town ────────────────
#[test]
fn a_menu_is_wished_listed_shown_and_ended() {
    let (lua, menu) = resident("menu", json!({}), json!({}));

    // wish for the apps menu with no index yet → nothing to show until the surface's index lands
    assert_eq!(say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"apps"}})), None);

    // the index lands → the menu by its choices, cut to apps, labels ready
    let show = say(&lua, &menu, json!({"kind":"places","tense":"present","body":{"places":[
        {"kind":"app","name":"Linear"}, {"kind":"window","app":"Slack"}, {"kind":"app","name":"Chrome"}]}})).unwrap();
    assert_eq!(show["kind"], "menu");
    assert_eq!(show["body"]["choices"][0]["label"], "Linear");

    // it ended on id 2 → go to Chrome
    assert_eq!(
        say(&lua, &menu, json!({"kind":"menu","tense":"past","body":{"id":"2"}})),
        Some(json!({"kind":"place","tense":"future","body":{"kind":"app","name":"Chrome"}}))
    );
    // nothing wished for now → an index refresh opens nothing
    assert_eq!(say(&lua, &menu, json!({"kind":"places","tense":"present","body":{"places":[{"kind":"app","name":"Linear"}]}})), None);

    // with an index in the present, a wish is answered at once
    let index = json!({"places": {"places": [{"kind":"app","name":"Linear"}]}});
    let (lua, menu) = resident("menu", index, json!({}));
    let show = say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"apps"}})).unwrap();
    assert_eq!(show["body"]["choices"][0]["label"], "Linear");
}

// ── menu: the universal picker searches every source at once ─────────────────
#[test]
fn the_universal_picker_merges_every_source() {
    let past = json!({"place": [
        {"kind":"window","app":"Chrome"},
        {"kind":"session","name":"work"}
    ]});
    let (lua, menu) = resident("menu", json!({}), past);

    // wish for everything; no index yet
    assert_eq!(say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"all"}})), None);

    // the surface says what exists → town folds in its own recent places in front
    let show = say(&lua, &menu, json!({"kind":"places","tense":"present","body":{"places":[
        {"kind":"window","app":"Chrome","title":""},
        {"kind":"app","name":"Linear"}]}})).unwrap();
    assert_eq!(show["kind"], "menu");
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

// ── menu: usage — choosing a place bumps a file-backed count + timestamp, so a later show
// ranks by frecency (habit weighted by recency), not raw habit alone ──
#[test]
fn choosing_a_place_records_its_usage_as_a_write_effect() {
    let (lua, menu) = resident("menu", json!({}), json!({}));
    say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"apps"}}));
    say(&lua, &menu, json!({"kind":"places","tense":"present","body":{"places":[{"kind":"app","name":"WezTerm"}]}}));

    let chose = say(&lua, &menu, json!({"kind":"menu","tense":"past","body":{"id":"1"}}));
    assert_eq!(chose, Some(json!({"kind":"place","tense":"future","body":{"kind":"app","name":"WezTerm"}})));

    let w = effects(&lua).into_iter().rev().find(|e| e["kind"] == "write")
        .expect("choosing a place should bump its usage count");
    assert!(w["path"].as_str().unwrap().ends_with("/usage"));
    // "count\tlast" — a fresh pick's timestamp is some positive unix time, not asserted exactly
    assert!(w["content"].as_str().unwrap().contains("app:WezTerm\t1\t"));
}

#[test]
fn a_choices_score_reflects_recorded_usage_weighted_by_recency() {
    let (lua, menu) = resident("menu", json!({}), json!({}));
    // the sandbox clock is frozen at 0 — a negative `last` simulates elapsed time
    feed_file(&lua, "/usage", "app:WezTerm\t7\t-1000000\napp:Weather\t0\t0\napp:Finder\t2\t-100\n");

    say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"apps"}}));
    let show = say(&lua, &menu, json!({"kind":"places","tense":"present","body":{"places":[
        {"kind":"app","name":"Weather"}, {"kind":"app","name":"WezTerm"}, {"kind":"app","name":"Finder"}]}})).unwrap();
    let score: Vec<f64> = show["body"]["choices"].as_array().unwrap()
        .iter().map(|c| c["score"].as_f64().unwrap()).collect();
    // Weather: never picked → 0. WezTerm: 7 picks, but ~11.6 days old → ×0.5 = 3.5. Finder: only
    // 2 picks, but 100s ago (within the hour) → ×4 = 8 — fewer-but-recent outranks more-but-stale,
    // which is the whole point of frecency over a flat count.
    assert_eq!(score, vec![0.0, 3.5, 8.0]);
}

// sessions the surface gathered reach the picker — menu no longer shells tmux itself.
#[test]
fn sessions_from_the_surface_reach_the_picker() {
    let (lua, menu) = resident("menu", json!({}), json!({ "place": [] }));
    let live = json!([{ "kind": "session", "name": "alpha" }, { "kind": "session", "name": "bravo" }]);
    say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"all"}}));
    let show = say(&lua, &menu, json!({ "kind": "places", "tense": "present", "body": { "places": live } })).unwrap();
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
    let back = json!({ "kind": "place", "tense": "future", "body": { "step": 1 } });
    let fwd = json!({ "kind": "place", "tense": "future", "body": { "step": -1 } });
    let back_session = json!({ "kind": "place", "tense": "future", "body": { "step": 1, "kind": "session" } });
    let gone = |app: &str| json!({ "kind": "place", "tense": "past", "body": { "kind": "window", "app": app } });

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
        // a place that is no more: dropped. on the cursor → the flip carries on past it.
        ("gone Delta (under the cursor → carry on)", gone("Delta")),   // → Charlie
        ("back", back.clone()),                     // → Alpha
        ("gone Bravo (elsewhere → just dropped)", gone("Bravo")),
        ("forward", fwd.clone()),                   // → Charlie (Bravo no longer between)
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

    say(&lua, &menu, json!({"kind":"menu","tense":"future","body":{"what":"all"}}));
    let show = say(&lua, &menu, json!({ "kind": "places", "tense": "present", "body": { "places": live } })).unwrap();
    golden("menu_merge", &serde_json::to_string_pretty(&show["body"]["choices"]).unwrap());
}

// ── favourites (Caps 1-9): save pins a place; jump recalls it, or falls back to a default. ──
#[test]
fn favourites_flow_pinned() {
    let save = |slot: i32, app: &str|
        json!({ "kind": "favourites", "tense": "future", "body": { "slot": slot, "place": { "kind": "window", "app": app } } });
    let jump = |slot: i32| json!({ "kind": "place", "tense": "future", "body": { "slot": slot } });

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

// ── time: a word carries `at`; an intent and the fact that answers it are a gap. Gaps fold into
// a pace per kind; one far outside its kind's past is `slow`; a median well above the last
// open's is `slow` with regress. An unfitting fact doesn't answer; an unstamped word is nothing. ──
#[test]
fn time_is_the_gap_from_wanting_to_having() {
    let want = |at: u64| json!({ "kind": "place", "tense": "future", "body": { "kind": "session", "name": "work" }, "at": at });
    let have = |at: u64| json!({ "kind": "place", "tense": "present", "body": { "kind": "session", "name": "work" }, "at": at });
    let (lua, time) = resident("time", json!({}), json!({}));

    // a fact that doesn't fit the intent doesn't answer it; the one that fits does — even when a
    // later intent of the same kind (tmux raising the terminal) came between
    assert_eq!(say(&lua, &time, want(1000)), None);
    assert_eq!(say(&lua, &time, json!({ "kind": "place", "tense": "future", "body": { "kind": "window", "app": "WezTerm" }, "at": 1040 })), None);
    assert_eq!(say(&lua, &time, json!({ "kind": "place", "tense": "present", "body": { "kind": "window", "app": "Chrome" }, "at": 1010 })), None);
    let first = say(&lua, &time, have(1050)).expect("the first gaps fold at once, so the page fills");
    assert_eq!(first["kind"], "time");
    assert_eq!(first["body"]["place session"]["med"], 50);
    for i in 1..10u64 { say(&lua, &time, want(i * 1000)); say(&lua, &time, have(i * 1000 + 50)); }
    // an empty wish opens nothing to wait for; a real one does
    assert_eq!(say(&lua, &time, json!({ "kind": "place", "tense": "future", "body": {}, "at": 19000 })), None);
    assert_eq!(say(&lua, &time, json!({ "kind": "place", "tense": "present", "body": { "kind": "session", "name": "work" }, "at": 19900 })), None);
    assert_eq!(say(&lua, &time, want(20000)), None);
    let slow = say(&lua, &time, have(20900)).expect("an odd gap is said");
    assert_eq!(slow["kind"], "slow");
    assert_eq!(slow["body"]["kind"], "place session");
    assert_eq!(slow["body"]["ms"], 900);
    assert_eq!(slow["body"]["med"], 50);
    // unstamped words are nothing to the clock
    assert_eq!(say(&lua, &time, json!({ "kind": "place", "tense": "future", "body": {} })), None);
    // the fold: every 20 gaps, the pace per kind
    let mut fold = None;
    for i in 30..60u64 { say(&lua, &time, want(i * 1000)); if let Some(w) = say(&lua, &time, have(i * 1000 + 50)) { fold = Some(w); } }
    let fold = fold.expect("the pace is talked");
    assert_eq!(fold["kind"], "time");
    assert_eq!(fold["tense"], "present");
    assert_eq!(fold["body"]["place session"]["med"], 50);
    assert_eq!(fold["body"]["place session"]["max"], 900);

    // regress: the last open knew 50ms; now it's 400
    let last = json!({ "time": { "place session": { "med": 50, "max": 90, "n": 40 } } });
    let (lua, time) = resident("time", last, json!({}));
    let mut said = Vec::new();
    for i in 1..=16u64 {
        say(&lua, &time, want(i * 1000));
        if let Some(w) = say(&lua, &time, have(i * 1000 + 400)) { if w["kind"] == "slow" { said.push(w); } }
    }
    assert_eq!(said.len(), 1, "exactly one slow: the regress");
    assert_eq!(said[0]["body"]["regress"], true);
    assert_eq!(said[0]["body"]["med"], 50);
}
