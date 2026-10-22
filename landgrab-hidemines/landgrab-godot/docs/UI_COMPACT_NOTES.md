# UI compaction + responsive pass (static checks only - NOT run in Godot)

Backup before this pass: `main.gd.bak_before_ui` (project root). No gameplay, networking, protocol version or server address was touched.

## Causes of the clutter
Every panel used big fixed values: panel padding 14/11 + big shadow, 12 px screen margins, building cards 98x100 with 14 px text, HUD 196 px wide with 22 px numbers,
leaderboard 176 px, attack list 260 px, a 780 px lobby card with a 46 px title - and NO scaling for large windows (a 1080p full-screen window scaled the whole
UI up by 1.5x, so it ate the board).

## What changed (all in main.gd)
- Tokens: `UI_MARGIN` 12 -> 6; `_panel()` padding 8/6, small shadow; `_style_button()` padding 10/4.
- HUD 128 px wide, 16 px values, 3 px gaps; hover info bar, right-click menu (150 px, 26 px buttons), leaderboard (116 px, 11 px rows), attack list (190 px, 20 px buttons), zoom buttons, spectate bar, message box and end panel all smaller.
- Bottom bar: cards 64x62 (56x56 on narrow windows, 86x82 on touch), short names (`CARD_SHORT`), 10 px text, slider block 150 px with "Send N% per attack". The arrows on the Port / Launcher cards are centred by `_compact_ui()` (also used by the touch layout - it no longer has hard-coded arrow positions).
- Lobby: smaller title / card / preview / buttons / fields (fields stay 46 px tall in phone browsers).
- `_desktop_scale()`: on desktop and browsers (not touch) the UI scale follows the window only slowly (about 0.9x at 720p, 1.2x at 1080p, max 1.3x) through `content_scale_factor`, so a bigger window gives the BOARD the extra room instead of the UI. Runs on every window resize / fullscreen change. Touch devices keep `_touch_scale()`.
- In-map tooltip smaller.

## NOT tested - please check
1. Open in Godot 4 (F5): any red error in the Output panel? (send the line)
2. Window sizes 1280x720, 1920x1080, 1024x600 and fullscreen: nothing clipped / overlapping; hover bar, leaderboard and HUD should not touch.
3. Bottom bar: Port and Launcher arrows centred and clickable, popups open above their card, text readable (10 px) - if too small raise the fonts in `_make_card`.
4. Phone: touch layout still fingertip-sized (cards 86x82).
If the UI feels too small anywhere: `_desktop_scale()` (the 0.9 minimum / 1500 / 880) and the card size in `_compact_ui()`.
