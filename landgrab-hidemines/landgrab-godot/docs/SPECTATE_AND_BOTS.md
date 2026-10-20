# Spectator mode + smarter bots (this round)
Status: written and statically checked only (balanced brackets, tab indentation, no shadowed variables, no duplicate functions). **NOT run in Godot** -
Godot is not available in my environment. Backup of the file you sent: `main.gd.bak_before_naval` (unchanged, in this folder).

## Spectate
- Lobby screen: new button **"Spectate (watch the bots play)"** under Join game. It leaves the online lobby, starts an OFFLINE match where every nation
  is an AI (`SPEC_NATIONS = 32` nations, change the constant at the top of `main.gd`), skips the spawn countdown and starts the match at once.
- Top-centre panel: speed buttons **1x 2x 4x 8x** (`sim_speed`, offline only) and **Leave** (back to the lobby).
- Click any nation to make the HUD follow it (`my_slot` changes; the rules never use `my_slot`). If the followed nation dies the HUD follows the biggest one.
- You cannot issue commands: `validate()` already refuses human commands for AI nations; the build bar, hotkeys and right-click menu are also hidden/disabled.
- The match end screen says which nation won; "Back to lobby" leaves spectate mode.

## Bots (all inside `bot_think` / `bot_build`, deterministic: `sim_rng` + the same `submit()` commands as a human)
- **Economy planner**: ranks needs and saves for important ones. Troop capacity first (new village, or upgrade village -> city -> duchy), a first port if coastal,
  stations next to cities (rails pay gold), 2 warships, port upgrades, a few mines. New buildings go deep inside their own land (not on the border); ports on the coast.
- **Defence**: when attacked they counter-attack the strongest attacker (25-50% of troops), keep at least half of their troops at home, and warships hunt enemy transports.
- **Attack**: free land first while small; otherwise the best neighbour = most beatable (troop ratio), revenge on attackers, finishing nearly dead nations (<40 tiles),
  thinly defended land. Attack size 20-35% (30-50% if troops are stuck at the cap). Boat landings when land targets run out.
- **Diplomacy**: ask a much stronger neighbour for an alliance (max 2 allies); drop an alliance after a while once they are the stronger side, so the map never freezes.

## Please test (first run)
1. No parser errors. 2. Lobby shows the Spectate button; pressing it starts the match with the panel at the top. 3. Watch at 4x: bots build villages/ports/stations,
   upgrade to cities, send boats and warships, form/break alliances. 4. Click nations to follow. 5. "Leave" returns to the lobby and normal Join still works.
Tell me what looks wrong (bot too passive/aggressive, too slow, etc.): the numbers are in `bot_think` (0.15 skip, 0.2-0.35 ratios, 0.5 out-limit) and `bot_build` (values 100/85/60/55/40).

## Fix (port bug)
Bots never built ports because a village always scored higher than a port and bots "save up" for anything above 80, so they kept saving for villages.
Now each extra village is worth less than the one before it, and a coastal bot buys its first port right after its first village (value 160 beats any village).
