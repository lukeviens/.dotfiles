//! Shared test harness. Loads a resident with the real vocabulary (lib.lua) under a HERMETIC
//! sandbox: `present`/`past` are stubbed from fixtures, and every side effect (os.execute,
//! io.popen, io.open, os.time, math.random) becomes a deterministic recording fake — so a resident
//! test never touches the real machine, and effects (shell commands, file writes) become golden.

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::{json, Value};

pub const ROOT: &str = env!("CARGO_MANIFEST_DIR");

// Install the hermetic sandbox. Recorded effects land in the global `EFFECTS`; io.popen/io.open
// reads serve canned text from `WORLD` (populate via feed_popen / feed_file). Time and RNG are
// pinned so even the random-theme path is snapshotable.
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
            lua.create_function(move |lua, kind: String| {
                lua.to_value(p.get(&kind).unwrap_or(&Value::Null))
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
