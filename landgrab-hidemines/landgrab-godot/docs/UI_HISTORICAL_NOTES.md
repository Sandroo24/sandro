# Landgrab - historical grand-strategy UI pass (v1)

STATUS: implemented with static checks only. **Nothing was opened in Godot and no web export was made** (no Godot in my environment).
Backup of the script before this pass: `main.gd.bak_before_hist` (kept in my working folder, not in the ZIP; the ZIP's `main.gd.bak_before_ui` is the previous author's).
No gameplay rule, balance number, networking code, message format, server address or `NET_VER` / `PROTO_VERSION` was touched.

## Visual identity
Antique atlas / campaign chart: dark navy "ink" panels framed in brass, parchment text, antique gold accent, forest green (good), burgundy (bad / selected), warm brown ink.
Palette constants (top of main.gd): `ACC` antique gold, `UI_TEXT` parchment, `UI_MUTED` vellum, `UI_GOOD` forest, `UI_BAD` burgundy-red, `UI_NAVY`, `UI_INK`, `UI_BRASS`, `UI_BURGUNDY`.

## Files changed / added
| file | purpose |
|---|---|
| `main.gd` | all code changes below |
| `fonts/GFSBaskerville.otf`, `fonts/Lora-Variable.ttf`, `fonts/OFL-LICENSE.txt` | bundled open-license fonts (SIL OFL 1.1). Browsers cannot use system fonts, so they must ship with the game. Baskerville = headings / nation names on the map, Lora = body and numbers |
| `ui/cursor_arrow.png`, `ui/cursor_cross.png`, `ui/cursor_hand.png` | 32x32 brass-pointer cursor, reticle (used while a warship is selected) and a pointer with a gold lozenge |
| `docs/UI_HISTORICAL_NOTES.md` | this report |

## What changed in main.gd
- **Panels**: `_panel()` now uses `HistBox` (new inner class): navy fill, brass outer line, fine inner line, cut corners, two small gems, soft shadow. Same padding class as before (9/7 px) so the HUD stays compact.
- **Typography**: `_make_theme()` loads the bundled fonts (falls back to a system serif if they are not imported). ALL-CAPS headings (LEADERBOARD, ATTACKS, LANDGRAB ...) automatically use Baskerville (`_small_label`).
  HUD stat titles use Baskerville, values Lora semi-bold. Tooltips are small parchment cards with dark ink text. Text fields (lobby) are ink-dark with a brass line, gold when focused.
- **Buttons / cards**: brass primary buttons with dark text, navy buttons with a brass hairline, build cards navy with brass border, selected card burgundy with gold border and glow.
- **Toast** (`say()`): good / bad / info tint the frame edge forest / burgundy / brass.
- **Lobby**: deep navy background, 40 px Baskerville title with a gilt rule (`HistRule`), parchment / brass controls (it uses the same helpers). The previous mobile keyboard / paste work was not touched.
- **Map labels**: nation names in Baskerville (parchment, gold for you, green for allies) with a warm dark-ink outline, troop numbers in Lora semi-bold.
- **Territory rendering (shader, look only)**: engraved dark-ink borders between nations (stronger), parchment rim toward free land, warm coast rim, antique-gold outline for the selected nation, warm lift for the hovered nation,
  a faint warm antique grade over the chart, and a brass frame line + deeper navy vignette around the chart.
- **National colours** (visual only, `HUMAN_COLS`, your colour, bot hue saturation): antique gold, azure, rose, ochre, ivory, sage, violet, vermilion; bots slightly less saturated.
- **Cursor** (`_setup_cursor`, `_apply_cursor`, `SoftCursor`): see below.

## Cursor
Custom hardware cursor through `Input.set_custom_mouse_cursor` for ARROW (hotspot 2,2 = the needle tip), CROSS (hotspot 16,16 = reticle centre) and POINTING_HAND. The image has a cream halo + dark ink outline + brass body, so it reads on blue, sand and green territory (checked on a mock-up sheet, not in the game).
It never captures input. **Fallback**: press **F7** to switch to a game-drawn cursor (a Control on a top CanvasLayer with `mouse_filter = IGNORE`, OS cursor hidden) - use it if a browser shows no custom cursor. F7 again goes back. Phones / tablets (mobile browsers) get no custom cursor.
The choice is not saved between sessions.

## Completed / partial / not started
- Completed (code written, untested): palette, panels, buttons, cards, tooltips, text fields, toast, lobby look, map labels, shader borders / selection / grade, national colours, fonts, cursor + fallback.
- Partial: layout / overlap review - I did not change any anchors or sizes (the previous compaction pass `UI_COMPACT_NOTES.md` already set them); fonts are a little wider than the old sans, so check the 10 px card text and the hover bar for clipping.
- Not started: end-of-match panel and right-click menu bespoke styling (they use the shared helpers, so they inherit the new look but were not individually reviewed), saving the cursor choice, a parchment texture on panels, icons redrawn in an engraved style.

## Tests you still need to do
1. Open in Godot 4 (project says 4.7): wait for the one-time import of `fonts/` and `ui/`; run (F5). Send me any red error line (most likely places: `HistBox._draw`, `_make_theme`, `_setup_cursor`).
2. Look at: lobby, HUD (top-left), leaderboard, attack list, bottom bar and its popups, toast messages, right-click menu, end screen. Check nothing is clipped and text is readable at 1280x720, 1920x1080, 1024x600.
3. Cursor: in the editor window, in a desktop browser (Chrome / Firefox / Safari) after a web export; check the tip hits what you click; press F7 to test the fallback.
4. Web export (below) and a performance check with F3 on a late-game match (panels now draw a few more primitives).

## Open in Godot 4 and export for itch.io
1. Godot 4.x (the project is saved with 4.7 features): Project Manager > Import > pick `landgrab-godot/project.godot` > Import & Edit. Let the editor import the new fonts / PNGs (progress bar bottom right).
2. Project > Export... The `Web` preset already exists (`export_presets.cfg`, "export all resources", so fonts and cursor PNGs are included). Install the Web export templates if the editor asks (Editor > Manage Export Templates).
3. Export Project... > file name `index.html` in an empty folder (untick "Export With Debug").
4. Zip the *contents* of that folder (index.html, .js, .wasm, .pck ...) so `index.html` sits at the root of the ZIP.
5. itch.io > Create new project > Kind: HTML > upload the ZIP > tick "This file will be played in the browser" > set viewport 1280x720 > tick "Mobile friendly" if you want phones > Save.
6. If the browser shows a normal arrow instead of the brass pointer, press F7 in the game for the drawn cursor.
