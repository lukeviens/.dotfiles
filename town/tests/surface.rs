//! The tmux surface must invoke the town binary with a REAL path. Regression guard: the config
//! once read `TOWN="$TOWN"` — self-referential, so it expanded to empty and every
//! `run-shell "$TOWN …"` bind (edge-crossing, the o/i trail, the session hook) ran ` talk …` and
//! failed with "talk: command not found". This pins the one contract: TOWN names a real town.

use std::path::{Path, PathBuf};

fn tmux_conf() -> Option<PathBuf> {
    // the surface lives beside the crate in the dotfiles (~/.config/tmux). absent → nothing to guard.
    let p = Path::new(env!("CARGO_MANIFEST_DIR")).join("../tmux/tmux.conf");
    p.exists().then_some(p)
}

#[test]
fn the_tmux_surface_names_a_real_town_binary() {
    let Some(conf) = tmux_conf() else { return };
    let text = std::fs::read_to_string(&conf).unwrap();

    // the one TOWN= definition (the town CLI, one place).
    let def = text
        .lines()
        .find(|l| l.trim_start().starts_with("TOWN="))
        .expect("tmux.conf must define TOWN=");
    let val = def
        .trim_start()
        .trim_start_matches("TOWN=")
        .split_whitespace()
        .next()          // drop any trailing `# comment`
        .unwrap_or("")
        .trim_matches('"');

    assert!(!val.is_empty(), "TOWN is empty — every $TOWN bind would run a blank command");
    assert!(!val.contains("$TOWN"), "TOWN is self-referential ({val}) → expands to empty; use a real path");
    assert!(val.ends_with("/town"), "TOWN should name the town binary, got: {val}");

    // if it's been built at least once, the path must actually point at it (catches a typo'd path).
    let path = val.replace("$HOME", &std::env::var("HOME").unwrap());
    if Path::new(&path).parent().is_some_and(Path::exists) {
        assert!(Path::new(&path).is_file(), "TOWN's dir exists but no binary at {path}");
    }

    // and the binds must actually use it — else the var is dead and this guard is moot. it now
    // arrives via the generated transport file, so accept either the source-file wiring or a literal.
    assert!(
        text.contains("town-transport.conf") || text.contains("run-shell \"$TOWN"),
        "tmux.conf neither source-files the transport nor uses $TOWN; the surface↔town contract drifted"
    );
}
