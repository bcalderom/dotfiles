-- Hyprland compositor configuration.
-- https://wiki.hypr.land/Configuring/Start/

-- Monitors
hl.monitor({
    output = "desc:AU Optronics 0x369F",
    mode = "preferred",
    position = "0x0",
    scale = 1,
})
hl.monitor({
    output = "desc:ViewSonic Corporation VX2768-2KPC W5H211040271",
    mode = "2560x1440@120.01",
    position = "1920x0",
    scale = 1,
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Programs
local terminal = "alacritty"
local fileManager = "dolphin"
local menu = "rofi -show drun"
local browser = "brave"

-- Autostart
hl.on("hyprland.start", function()
    hl.exec_cmd([[bash -lc 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP; systemctl --user restart hypr-lid.service']])
    hl.exec_cmd("hypridle")
    hl.exec_cmd([[bash -lc 'sleep 0.5; waybar']])
    hl.exec_cmd("swaync")
    hl.exec_cmd(browser, { workspace = "1 silent" })
    hl.exec_cmd(terminal, { workspace = "2 silent" })
end)

-- Environment
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("DE", "generic")

-- Look, feel, layouts, and input
hl.config({
    general = {
        gaps_in = 1,
        gaps_out = 1,
        border_size = 1,
        col = {
            active_border = "rgb(fffbf5)",
            inactive_border = "rgba(595959aa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    master = { new_status = "master" },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
    },
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = { natural_scroll = false },
    },
})

hl.curve("myBezier", {
    type = "bezier",
    points = { { 0.05, 0.9 }, { 0.1, 1.05 } },
})
hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

-- Keybindings
local mainMod = "SUPER"

hl.bind(mainMod .. " + return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd([[bash -lc 'pgrep -x waybar >/dev/null && pkill -x waybar; waybar &']]))
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("hyprlock"))

hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "d" }))

hl.bind("SUPER + N", hl.dsp.exec_cmd("swaync-client -t"))
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("swaync-client -d"))
hl.bind("SUPER + M", hl.dsp.exec_cmd("swaync-client -C"))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    hl.bind(mainMod .. " + ALT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

local mediaFlags = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), mediaFlags)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), mediaFlags)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), mediaFlags)
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), mediaFlags)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 10%+"), mediaFlags)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"), mediaFlags)

-- Ignore maximize requests from all applications.
hl.window_rule({
    name = "windowrule-1",
    match = { class = ".*" },
    suppress_event = "maximize",
})
