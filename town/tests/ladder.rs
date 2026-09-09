//! Sweeps hammerspoon/ladder.lua's `plan` — Caps-mode's one depth-ladder decision (register +
//! direction + depth + which surface is frontmost → what hjkl does and where that is). Pure Lua,
//! no hs.* calls, so it loads directly with no sandbox — this is what makes mode.lua's dispatch
//! testable at all; the version before this file existed had zero coverage of this logic.

mod common;
use common::ROOT;

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::{json, Value};

fn ladder() -> Lua {
    let lua = Lua::new();
    let src = std::fs::read_to_string(format!("{ROOT}/../hammerspoon/ladder.lua")).unwrap();
    let m: Table = lua.load(&src).set_name("ladder").eval().unwrap();
    lua.globals().set("ladder", m).unwrap();
    lua
}

#[derive(Default)]
struct Ctx {
    in_term: bool,
    in_vim: bool,
    in_chrome: bool,
}

fn plan(lua: &Lua, register: &str, dir: Option<&str>, at_depth: i64, dmax: i64, ctx: Ctx) -> Value {
    let m: Table = lua.globals().get("ladder").unwrap();
    let f: mlua::Function = m.get("plan").unwrap();
    let ctx_table = lua.create_table().unwrap();
    ctx_table.set("inTerm", ctx.in_term).unwrap();
    ctx_table.set("inVim", ctx.in_vim).unwrap();
    ctx_table.set("inChrome", ctx.in_chrome).unwrap();
    let dir_val: LuaValue = match dir {
        Some(s) => LuaValue::String(lua.create_string(s).unwrap()),
        None => LuaValue::Nil,
    };
    let out: LuaValue = f.call((register, dir_val, at_depth, dmax, ctx_table)).unwrap();
    lua.from_value(out).unwrap()
}

fn term(in_vim: bool) -> Ctx { Ctx { in_term: true, in_vim, ..Ctx::default() } }
fn chrome() -> Ctx { Ctx { in_chrome: true, ..Ctx::default() } }

#[test]
fn point_depth0_defers_to_the_pane_occupant() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "point", Some("h"), 0, 2, term(true)),
        json!({"act": "wez", "verb": "point", "dir": "h", "where": "nvim"})
    );
    assert_eq!(
        plan(&lua, "point", Some("h"), 0, 2, term(false)),
        json!({"act": "wez", "verb": "point", "dir": "h", "where": "tmux"})
    );
}

#[test]
fn point_depth0_in_chrome_cycles_tabs_instead() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "point", Some("h"), 0, 1, chrome()),
        json!({"act": "chrome-cycle", "step": -1, "where": "chrome"})
    );
    assert_eq!(
        plan(&lua, "point", Some("l"), 0, 1, chrome()),
        json!({"act": "chrome-cycle", "step": 1, "where": "chrome"})
    );
}

#[test]
fn point_depth0_elsewhere_focuses_the_mac_window() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "point", Some("h"), 0, 1, Ctx::default()),
        json!({"act": "onkey", "dir": "h", "where": "mac window"})
    );
}

#[test]
fn point_middle_rung_is_tmux_windows_regardless_of_vim() {
    let lua = ladder();
    for in_vim in [true, false] {
        assert_eq!(
            plan(&lua, "point", Some("h"), 1, 2, term(in_vim)),
            json!({"act": "wez", "verb": "tab", "dir": "prev", "where": "tmux tabs"}),
            "in_vim={in_vim}"
        );
    }
}

#[test]
fn point_outer_rung_is_always_the_mac_window() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "point", Some("h"), 2, 2, term(true)),
        json!({"act": "onkey", "dir": "h", "where": "mac window"})
    );
}

#[test]
fn edge_middle_rung_exists_only_in_a_vim_pane() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "edge", Some("h"), 1, 2, term(true)),
        json!({"act": "wez", "verb": "edge-pane", "dir": "h", "where": "tmux pane"}),
        "vim present: the middle rung is the forced tmux-pane resize"
    );
    assert_eq!(
        plan(&lua, "edge", Some("h"), 1, 2, term(false)),
        json!({"act": "mac", "reg": "edge", "dir": "h", "where": "mac window"}),
        "no vim: depth 0 already reached the pane directly, so the middle rung is just the outer one early"
    );
}

#[test]
fn edge_depth0_and_outer_match_point_and_cell_shapes() {
    let lua = ladder();
    assert_eq!(
        plan(&lua, "edge", Some("h"), 0, 2, term(true)),
        json!({"act": "wez", "verb": "edge", "dir": "h", "where": "nvim"})
    );
    assert_eq!(
        plan(&lua, "edge", Some("h"), 2, 2, term(true)),
        json!({"act": "mac", "reg": "edge", "dir": "h", "where": "mac window"})
    );
    assert_eq!(
        plan(&lua, "edge", Some("h"), 0, 1, Ctx::default()),
        json!({"act": "mac", "reg": "edge", "dir": "h", "where": "mac window"}),
        "outside the terminal, edge has always acted on the mac window at any depth"
    );
}

#[test]
fn cell_never_gets_a_middle_rung_and_never_claims_vim() {
    let lua = ladder();
    // swap-pane never defers to vim, unlike point/edge — the label must say "tmux", not "nvim",
    // even while sitting in a vim pane (this was a real bug caught earlier this session).
    assert_eq!(
        plan(&lua, "cell", Some("h"), 0, 2, term(true)),
        json!({"act": "wez", "verb": "cell", "dir": "h", "where": "tmux"})
    );
    for at_depth in [1, 2] {
        assert_eq!(
            plan(&lua, "cell", Some("h"), at_depth, 2, term(true)),
            json!({"act": "mac", "reg": "cell", "dir": "h", "where": "mac window"}),
            "at_depth={at_depth}"
        );
    }
    assert_eq!(
        plan(&lua, "cell", Some("h"), 0, 1, Ctx::default()),
        json!({"act": "mac", "reg": "cell", "dir": "h", "where": "mac window"})
    );
}

#[test]
fn locate_only_mode_omits_the_direction_and_still_labels_correctly() {
    // mode.lua's badge repaint calls plan with no `d` — only `where` is read, never `dir`/`step`.
    let lua = ladder();
    let p = plan(&lua, "point", None, 1, 2, term(false));
    assert_eq!(p["where"], json!("tmux tabs"));
    assert_eq!(p["dir"], Value::Null);
}
