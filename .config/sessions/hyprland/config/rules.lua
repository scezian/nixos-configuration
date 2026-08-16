-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ WINDOW & LAYER RULES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- ───────── Layer rules (OSD / overlays) ─────────
hl.layer_rule({ name = "no-anim-volume-osd",     match = { namespace = "^(volume_osd)$" },     no_anim = true })
hl.layer_rule({ name = "no-anim-brightness-osd", match = { namespace = "^(brightness_osd)$" }, no_anim = true })
hl.layer_rule({ name = "no-anim-hyprpicker",     match = { namespace = "hyprpicker" },          no_anim = true })
hl.layer_rule({ name = "no-anim-qsdock",         match = { namespace = "qsdock" },              no_anim = true })
hl.layer_rule({
    name = "session-lock-blur",
    match = { namespace = "ext-session-lock" },
    blur = true,
    ignore_alpha = 0.2,
})

-- ───────── Window rules ─────────

-- CS2 — combined into one rule (Lua rules are single objects, no need for two
-- separate lines targeting the same class like the old windowrule = lines were)
hl.window_rule({
    name = "cs2-immediate",
    match = { class = "^(cs2)$" },
    immediate = true,
    keep_aspect_ratio = true,
})

-- App Launcher
-- VERIFY: I could not confirm the exact Lua field shape for `size` (string vs
-- {w, h} table) and `animation` against the live wiki today — spot-check these
-- two fields against `hl.window_rule` docs before relying on them.
hl.window_rule({
    name = "app-launcher",
    match = { title = "^(app-launcher)$" },
    float = true,
    center = true,
    size = "1200 600",
    animation = "slide",
})

-- MASTER QUICKSHELL CONTAINER (kept commented out, mirrors the original .conf)
-- hl.window_rule({
--     name = "qs-master",
--     match = { title = "^(qs-master)$" },
--     float = true,
--     no_shadow = true,
--     no_border = true,
--     no_initial_focus = true,
-- })
