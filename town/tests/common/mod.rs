//! Shared test harness. Loads a resident with the real vocabulary (lib.lua) under a HERMETIC
//! sandbox: `present`/`past` are stubbed from fixtures, and every side effect (os.execute,
//! io.popen, io.open, os.time, math.random) becomes a deterministic recording fake — so a resident
//! test never touches the real machine, and effects (shell commands, file writes) become golden.

#![allow(dead_code)] // shared across test binaries; each uses a subset

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use mlua::{Function, Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::{json, Value};

pub const ROOT: &str = env!("CARGO_MANIFEST_DIR");

/// A dependency-free expect-test: compare `actual` against tests/snapshots/<name>.snap. Set
/// `UPDATE=1` to (re)write the snapshot; commit the .snap. A drift fails with a diff hint.
pub fn golden(name: &str, actual: &str) {
    let path = format!("{ROOT}/tests/snapshots/{name}.snap");
    if std::env::var("UPDATE").is_ok() {
        std::fs::create_dir_all(format!("{ROOT}/tests/snapshots")).unwrap();
        std::fs::write(&path, actual).unwrap();
        return;
    }
    let expected = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| panic!("no snapshot at {path} — run `UPDATE=1 cargo test` to create it"));
    assert!(
        actual == expected,
        "snapshot `{name}` drifted — re-run with UPDATE=1 if intended.\n\
         first difference around:\n{}",
        first_diff(&expected, actual)
    );
}

fn first_diff(a: &str, b: &str) -> String {
    let at = a.char_indices().zip(b.chars()).find(|((_, x), y)| x != y).map(|((i, _), _)| i);
    let at = at.unwrap_or(a.len().min(b.len()));
    let lo = at.saturating_sub(80);
    format!("  expected: …{}…\n  actual:   …{}…", snippet(a, lo, at + 80), snippet(b, lo, at + 80))
}

fn snippet(s: &str, lo: usize, hi: usize) -> String {
    s.chars().skip(lo).take(hi - lo).collect()
}

// Hermetic sandbox: effects land in `EFFECTS`, io.popen/io.open reads serve canned `WORLD` text
// (feed_popen/feed_file), time + RNG pinned so even the random-theme path snapshots.
fn sandbox(lua: &Lua) {
    lua.load(
        r#"
        EFFECTS = {}                        -- {kind="exec"|"write", cmd|path, content?}, in order
        WORLD = { popen = {}, files = {} }  -- canned: popen[cmd_substr]=text, files[path]=text

        local function record(e) EFFECTS[#EFFECTS + 1] = e end
        local function canned(map, key)     -- first entry whose key is a substring of `key`
          for k, v in pairs(map) do if tostring(key):find(k, 1, true) then return v end end
          return nil
        end

        os.execute = function(cmd) record{ kind = "exec", cmd = cmd }; return true end
        os.time = function() return 0 end
        math.randomseed = function() end
        do
          local seq, i = { 0.13, 0.41, 0.72, 0.28, 0.94, 0.55, 0.07, 0.66 }, 0
          math.random = function(a, b)
            i = i % #seq + 1; local r = seq[i]
            if a and b then return a + math.floor(r * (b - a + 1)) end
            if a then return 1 + math.floor(r * a) end
            return r
          end
        end

        io.popen = function(cmd)
          local text = canned(WORLD.popen, cmd) or ""
          return {
            lines = function() return text:gmatch("[^\r\n]+") end,
            read  = function() return text end,
            close = function() return true end,
          }
        end
        io.open = function(path, mode)
          if mode and mode:find("w") then
            local buf = {}   -- accumulate the writes; a "write" effect is the WHOLE file, on close
            return {
              write = function(_, s) buf[#buf + 1] = s; return true end,
              close = function() record{ kind = "write", path = path, content = table.concat(buf) }; return true end,
            }
          end
          local text = canned(WORLD.files, path)
          if not text then return nil end
          return {
            read  = function() return text end,
            lines = function() return text:gmatch("[^\r\n]+") end,
            close = function() return true end,
          }
        end
        "#,
    )
    .set_name("sandbox")
    .exec()
    .unwrap();
}

/// Load lib + a resident under the sandbox, with `present`/`past` stubbed from fixtures.
pub fn resident(name: &str, present: Value, past: Value) -> (Lua, Table) {
    let lua = Lua::new();
    sandbox(&lua); // BEFORE loading — some residents (theme, k9s) do io at load time

    let p = present;
    lua.globals()
        .set(
            "present",
            // absent (or JSON null) → real Lua nil, NOT mlua's truthy null-sentinel, so residents'
            // `present(x) or default` works exactly as it does against the real engine.
            lua.create_function(move |lua, kind: String| match p.get(&kind) {
                Some(v) if !v.is_null() => lua.to_value(v),
                _ => Ok(LuaValue::Nil),
            })
            .unwrap(),
        )
        .unwrap();

    let q = past;
    lua.globals()
        .set(
            "past",
            lua.create_function(move |lua, kind: String| {
                lua.to_value(q.get(&kind).unwrap_or(&json!([])))
            })
            .unwrap(),
        )
        .unwrap();

    let lib = std::fs::read_to_string(format!("{ROOT}/lib.lua")).unwrap();
    lua.load(&lib).set_name("lib").exec().unwrap();
    let src = std::fs::read_to_string(format!("{ROOT}/residents/{name}.lua")).unwrap();
    let spec: Table = lua.load(&src).set_name(name).eval().unwrap();
    (lua, spec)
}

/// Talk a word at a resident; get back the word it talks (normalized to kind/tense/body,
/// exactly as the engine would read it), or None.
pub fn say(lua: &Lua, spec: &Table, word: Value) -> Option<Value> {
    let talk: mlua::Function = spec.get("talk").unwrap();
    let res: LuaValue = talk.call(lua.to_value(&word).unwrap()).unwrap();
    match res {
        LuaValue::Nil => None,
        v => {
            let full: Value = lua.from_value(v).unwrap();
            Some(json!({
                "kind": full["kind"],
                "tense": full.get("tense").cloned().unwrap_or(json!("present")),
                "body": full.get("body").cloned().unwrap_or(Value::Null),
            }))
        }
    }
}

/// Fold a word sequence through every resident under the sandbox — the tokio engine's loop, but
/// synchronous. Facts fold into an evolving present/past the residents read; each word goes to its
/// listeners; talkbacks + captured effects (writes, commands) come back as `{present, talkbacks,
/// effects}`. First-level dispatch only — the real log already carries talkbacks as their own
/// facts, so no recursion (and no loop risk).
pub fn replay(words: &[Value]) -> Value {
    let lua = Lua::new();
    sandbox(&lua);

    let present: Rc<RefCell<serde_json::Map<String, Value>>> = Rc::new(RefCell::new(Default::default()));
    let past: Rc<RefCell<HashMap<String, Vec<Value>>>> = Rc::new(RefCell::new(HashMap::new()));

    let p = present.clone();
    lua.globals()
        .set("present", lua.create_function(move |lua, kind: String| match p.borrow().get(&kind) {
            Some(v) if !v.is_null() => lua.to_value(v),
            _ => Ok(LuaValue::Nil), // real nil, not the truthy null-sentinel
        }).unwrap())
        .unwrap();
    let q = past.clone();
    lua.globals()
        .set("past", lua.create_function(move |lua, kind: String| {
            lua.to_value(&Value::Array(q.borrow().get(&kind).cloned().unwrap_or_default()))
        }).unwrap())
        .unwrap();
    lua.globals().set("reopen", lua.create_function(|_, ()| Ok(())).unwrap()).unwrap();

    lua.load(&std::fs::read_to_string(format!("{ROOT}/lib.lua")).unwrap()).set_name("lib").exec().unwrap();

    // load every resident, indexed by the kinds it listens for
    let mut listeners: Vec<(HashSet<String>, Function)> = Vec::new();
    let mut files: Vec<_> = std::fs::read_dir(format!("{ROOT}/residents"))
        .unwrap()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("lua"))
        .collect();
    files.sort();
    for path in files {
        let src = std::fs::read_to_string(&path).unwrap();
        let spec: Table = lua.load(&src).set_name(path.to_str().unwrap()).eval().unwrap();
        let kinds: HashSet<String> = spec
            .get::<Table>("listen")
            .map(|t| t.sequence_values::<String>().filter_map(Result::ok).collect())
            .unwrap_or_default();
        if let Ok(talk) = spec.get::<Function>("talk") {
            listeners.push((kinds, talk));
        }
    }
    lua.load("EFFECTS = {}").exec().unwrap(); // drop load-time self-heal effects (theme/k9s)

    let mut talkbacks: Vec<Value> = Vec::new();
    for w in words {
        let kind = w["kind"].as_str().unwrap_or("").to_string();
        let tense = w.get("tense").and_then(Value::as_str).unwrap_or("present");
        if tense == "present" && !kind.is_empty() {
            present.borrow_mut().insert(kind.clone(), w["body"].clone());
            past.borrow_mut().entry(kind.clone()).or_default().push(w["body"].clone());
        }
        for (kinds, talk) in &listeners {
            if kinds.contains(&kind) {
                let heard = lua.to_value(w).unwrap();
                match talk.call::<LuaValue>(heard) {
                    Ok(said) if !said.is_nil() => {
                        let out: Value = lua.from_value(said).unwrap();
                        talkbacks.push(json!({
                            "kind": out["kind"],
                            "tense": out.get("tense").cloned().unwrap_or(json!("present")),
                            "body": out.get("body").cloned().unwrap_or(Value::Null),
                        }));
                    }
                    Ok(_) => {} // said nothing
                    Err(e) => eprintln!("replay: resident errored on '{kind}': {e}"),
                }
            }
        }
    }

    json!({ "present": Value::Object(present.borrow().clone()), "talkbacks": talkbacks, "effects": effects(&lua) })
}

/// The side effects a resident performed, in order — `{kind:"exec"|"write", ...}`.
#[allow(dead_code)]
pub fn effects(lua: &Lua) -> Vec<Value> {
    let e: LuaValue = lua.globals().get("EFFECTS").unwrap();
    lua.from_value(e).unwrap()
}

/// Feed canned output for an io.popen whose command CONTAINS `cmd_substr`.
#[allow(dead_code)]
pub fn feed_popen(lua: &Lua, cmd_substr: &str, text: &str) {
    let world: Table = lua.globals().get("WORLD").unwrap();
    let popen: Table = world.get("popen").unwrap();
    popen.set(cmd_substr, text).unwrap();
}

/// Feed canned content for an io.open(path, "r") whose path CONTAINS `path_substr`.
#[allow(dead_code)]
pub fn feed_file(lua: &Lua, path_substr: &str, text: &str) {
    let world: Table = lua.globals().get("WORLD").unwrap();
    let files: Table = world.get("files").unwrap();
    files.set(path_substr, text).unwrap();
}
