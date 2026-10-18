# Bag of Dice — Feature & Spec List

A mobile dice roller where every result comes from a real 3D physics throw: the face that lands up is the result. Players build their own dice sets, shake the phone to roll, pick which dice to throw, and keep a log of the last 50 rolls.

- **Engine:** Godot 4.7.2 (standard edition), GDScript with static typing, Jolt Physics, Mobile renderer
- **Target:** Android phones, portrait only
- **Status as of:** 14 Oct 2026. Basic operation confirmed on a real device (Honor BRP-NX1): rolling, adding dice, mute.

**Status key**

- `BUILT`: done and tested
- `VERIFY ON DEVICE`: works on the Mac and the app runs on the phone, but this specific behaviour hasn't been explicitly confirmed on the device yet
- `OPEN`: not done yet
- `OUT OF SCOPE`: deliberately not built

Values in `code` style are the current settings in the code.

---

## 1. Platform & technology

| Feature | Spec | Status |
|---|---|---|
| Engine & language | Godot 4.7.2, GDScript with static typing throughout | BUILT |
| Physics & rendering | Jolt Physics at `120` steps per second; Mobile renderer | BUILT |
| Screen | Portrait only. Layout designed at `540 × 960` and scaled to the phone; taller phones get extra table space. Desktop / wide windows not supported (decision) | BUILT |
| Offline & private | No login, accounts, backend, sync, network access, ads or analytics. Everything stored on the phone | BUILT |

## 2. Dice

All dice are generated in code from their face directions, so every shape is symmetric with its centre of mass exactly in the middle.

| Feature | Spec | Status |
|---|---|---|
| Types | d4, d6, d8, d10, d12, d20, d100. A d100 is rolled as two d10s: tens (00–90) and units (0–9); 00 + 0 reads as 100 | BUILT |
| Reading the result | The face pointing most nearly straight up is the result. The d4 is read from the corner pointing up | BUILT |
| Numbering | Opposite faces add up the standard way (1↔6 on a d6, 1↔20 on a d20). On d10, d12 and d20, 6 and 9 carry a dot ("6." "9.") | BUILT |
| Face styles | Chosen per die in the set editor; natural look is the default. **d6:** pips (standard layout) or numbers. **d10:** 0–9 (0 counts as 10) or 1–10. Other types: numbers only | BUILT |
| Size | All dice scaled to `0.8` of the original design. The d20 is slightly larger than the d6, as in real sets | BUILT |
| Look | Bevelled edges, satin plastic finish, numbers and pips built into the die mesh. Black ink on light dice, white on dark. 10 colours: ivory, black, red, orange, yellow, green, teal, blue, purple, pink | VERIFY ON DEVICE |

## 3. Table & physics

| Feature | Spec | Status |
|---|---|---|
| Table | Flat felt table `9 × 15` units (a d6 edge is 0.8) with a low wooden rim, plus invisible walls and ceiling so dice can't escape. No tilt; phone orientation never affects the table | BUILT |
| Drawer | Along the near edge, past a thin low divider rail, a shallow felt drawer (`2.7` deep, felt a touch darker and `0.06` lower) where dice wait out of play. The side rims run unbroken past it, so table and drawer read as one tray. Dice are placed there by code and the play area's invisible wall keeps thrown dice out. One slot per die of the set, up to 7 per row in 1–3 rows: dice sitting out fill slots from the back right, dice set aside mid-roll fill them from the front left, so nothing in the drawer ever moves | VERIFY ON DEVICE |
| Surface feel | Friction: dice `0.9`, felt `1.0`. Bounce: dice `0.15` + felt `0.1` (Godot adds them: 0.25). Gravity `20` | VERIFY ON DEVICE |
| Tunnelling guard | Continuous collision detection on every die so fast dice can't pass through walls | BUILT |

## 4. Throwing & fairness

| Feature | Spec | Status |
|---|---|---|
| Throw | Each die gets a uniformly random starting orientation; speed `10–17` units/s towards a random point around the middle of the table; upward lift `3–6`; random spin `15–30` rad/s plus forward tumble `12–22` rad/s | BUILT |
| Shake strength | Scales throw speed from `0.8×` (gentle) to `1.25×` (hard). Never affects orientation, so it cannot favour any face | BUILT |
| Fairness test | Headless test throwing every die type thousands of times on the real table code, chi-square check per die. Latest: 3,000 throws per type, all pass. A separate run through the full shake-and-throw path (960 d6) also passed | BUILT |

## 5. Settling & reading results

| Feature | Spec | Status |
|---|---|---|
| At rest | A die is settled once slower than `0.1` units/s and rad/s for `0.4 s`. Results are read only when every thrown die is settled (or, in Count where they land and Clear the table, when a die's result is locked before a re-throw) | BUILT |
| Readable or cocked | Each type has its own limit: half the angle between neighbouring face directions, times a fraction (`0.5` for every type, set per type in one table in `die.gd`). Limits: d4 `27.4°` (read from its corners), d6 `22.5°`, d8 `17.6°`, d10 `13.0°`, d12 `15.9°`, d20 `10.5°`. Within the limit the die is read with no hop, even if it leans on the rim or another die. Past it, it's cocked. Decided from tilt and position only, never the value shown | BUILT |
| Hop | A cocked die alone gets a gentle hop (mostly lift `3.5`, little spin `0.12`), up to `3` times, then is re-thrown on its own. In testing, no hop landed a die beyond the two faces it was leaning between, and about 3 in 4 hops freed the die | VERIFY ON DEVICE |
| Easing flat | A readable die that's tilted eases flat onto the face it was read from while other dice are still being sorted out. Only the visible die moves, never the physics body, so the result can't change | VERIFY ON DEVICE |
| Debug tools | Debug builds only. **Debug landing** at the bottom of Settings forces a die to lean on the rim or land on another die on every throw (resets when the app restarts). While it's on, every hop or re-throw gets a numbered tag over the die and a line in a panel under the result bar: the rule, tilt against the limit, lowest corner height and what the die touches | BUILT |
| Landed on another die | If a resting die's lowest corner is more than `0.15` above the felt, it's lying on another die and goes to the bank for a full re-throw | BUILT |
| Safety nets | A die that leaves the table goes to the bank. A die moving continuously for `10 s` goes to the bank; the timer is per die and restarts on every throw or hop | BUILT |
| Re-throw modes | Only a full re-throw (on another die, still cocked after its hops, left the table, moving too long) triggers the mode; hops never do. Whether a die is re-thrown depends only on how it landed, never on its value. Global mode in Settings, overridable per set; quick rolls use the global mode. Default **Clear the table** | BUILT |
| The bank | A die that needs a full re-throw comes off the table straight away into the bank: frozen, no longer solid, held in a row above the near end. Hops still happen in place. Only when every die on the table has stopped and been read is the whole bank thrown together, from where it's held; dice that land badly again go back into the bank, so every roll finishes. The mode's step (counting, or moving dice into the drawer) happens just before each bank throw | VERIFY ON DEVICE |
| Re-roll by hand | Settings switch, off by default. When on, once the table has settled the banked dice come back to the player's hand as a fresh cast: the bar reads "Re-roll 1 die: shake, flick or tap to throw" and shaking, swiping, flicking, tapping or Throw throws them, as for a normal throw. Back, the menu and the sets and history buttons can't abandon a roll waiting on a hand re-roll. Off: the bank is thrown automatically | VERIFY ON DEVICE |
| Clear the table | Before a re-throw, every settled die that's flat on the felt and readable is read, its result locked, and it slides into the drawer in a low arc, lying with its counted result on top (frozen and no longer solid). The problem dice are re-thrown onto the empty table. When the roll ends, every thrown die lifts to the result row together | VERIFY ON DEVICE |
| Count where they land | Before a re-throw, every settled clean die is read and its result locked. Counted dice stay on the table as normal physics objects and are slightly dimmed while the re-throw happens. A knocked counted die is never re-read or re-thrown for landing badly; if it leaves the table it's thrown back but keeps its result. When the dice lift, a counted die turns to show its recorded result, so the result bar, lifted dice and history always agree | VERIFY ON DEVICE |
| Live table | Nothing is locked: everything stays in play and is read only when every die is settled and clean, so a knocked die is read again where it ends up. After `3` bank throws in one roll, the remaining problem dice are handled as in Clear the table, so every roll finishes | VERIFY ON DEVICE |
| Re-throw aim | Count where they land and Live table aim re-throws at open space: `32` candidate landing points scored by distance from the nearest die on the table (dice sitting out included) and from the walls, one of the best `4` picked at random, launched from whichever of `12` directions keeps its path clearest of the dice, at a gentler `3.5–5.5` units/s. Orientation and spin as random as a normal throw. Looks only at where dice lie, never their values. In testing a re-throw at a group of 8 settled dice hit the group 2 times in 60, against 47 in 60 for a normal throw. Clear the table uses the normal throw (the table is empty). All in one constants block in `dice_roller.gd` | BUILT |
| Escalation | If the same die has to be re-thrown a second time for landing on other dice, the rest of that roll is handled as in Clear the table. Results already locked stay locked | BUILT |
| Re-rolling note | During a full re-throw the result bar reads "Re-rolling 1 die" / "Re-rolling 2 dice" | VERIFY ON DEVICE |
| Sitting-out dice | Dice not picked for a throw wait in the drawer, frozen: never moved, read, counted or lifted in any mode, and re-throws never aim near them | BUILT |

## 6. Shake to roll & the hand

| Feature | Spec | Status |
|---|---|---|
| Arming | **Roll** arms a roll; button becomes **Throw**. Accelerometer is ignored unless armed. Disarms automatically once dice settle and the result is logged | BUILT |
| Shake detection | Gravity removed via the phone's gravity sensor (or a smoothed estimate if absent). Movement over `12 m/s²` counts as shaking. Needs `2` separate jolts or `0.35 s` of strong movement (a single bump or tilt doesn't throw). Throws when movement stays low for `0.25 s` | VERIFY ON DEVICE |
| Throw without shaking | Tapping **Throw** while armed throws at normal strength | BUILT |
| The hand (cup) | When armed, dice tumble into an invisible cup above the near half of the table as real physics objects. Shaking (or swiping side to side) kicks them harder and more often the harder you shake: up to `11` units/s, `22` kicks per die per second, with spin, speed cap `13`, bouncy cup walls (`0.5`); pinned dice get extra kicks. On release each die launches from where it ended up and keeps half its motion | VERIFY ON DEVICE |
| Cup containment | Thick sealed walls, top speed `9` inside the cup, any escaped die is put back in the middle | BUILT |

## 7. Picking dice (parking)

For games where only some of a set's dice are thrown at a time, e.g. one Risk set holding attack and defend dice.

| Feature | Spec | Status |
|---|---|---|
| Per-set option | "Pick dice before each throw" switch in the set editor. When off, every throw uses all dice | BUILT |
| Pick up | Main button reads **Pick up**. Dice laid out four per row (a d100's two dice share a row), with name tags above labelled dice | BUILT |
| Tap / long-press | **Tap** picks a die for this throw (lifts and brightens); tap again to put back. **Long-press** (`0.5 s`) locks a die: picked automatically every throw, orange ring, until long-pressed again. A d100 gets one oval ring around both dice. Locks last for the session, per set, and reset if the set is edited | VERIFY ON DEVICE |
| Sitting out | Unpicked dice wait greyed in the drawer. Only thrown dice are read, shown, totalled and logged | BUILT |

## 8. Showing results

| Feature | Spec | Status |
|---|---|---|
| Result bar | Matching dice grouped, total shown when more than one die, e.g. `d6: 5 6 3 5` / `Total: 19`. Labels show as `Attack (d6): 5`; a d100 shows its parts, `48 (40 + 8)` | BUILT |
| Lifted dice | After settling, thrown dice glide up and line up under the result bar, face-on to the camera, result upright. Up to 5 per row (4 when a d100 is present so pairs stay together). Rows always fit between result bar and buttons. Lifting happens after the result is read, so it can't change it. A die with a locked result (Count where they land, Clear the table) shows that result, whatever face it was knocked onto. In Clear the table, dice set aside in the drawer during a re-throw lift with the rest when the roll ends | BUILT |

## 9. Dice sets, drawer & editor

| Feature | Spec | Status |
|---|---|---|
| A set | Name (max `40` chars), pick-dice option, list of dice. Each die: type and face style, colour, optional label (max `24` chars) | BUILT |
| Dice limit | Max `20` physical dice per set. A d100 counts as 2 (max 10 d100s). "+ d100" disabled when only one place is left; switching a die to d100 in a full set is refused with an explanation | BUILT |
| Scrolling lists | Settings, the drawer, the editor and the history scroll by dragging anywhere, including on a switch or button; a drag never presses what it started on | BUILT |
| Drawer | Set-name button (bottom left) slides up a sheet listing sets as cards: name, colour dots, summary (e.g. "8d6"), "· pick dice" where relevant. Current set outlined. Tap a card to pull the set out; tap outside or Close to dismiss | BUILT |
| Duplicate | **Duplicate** button at the top of the editor turns the set being edited into a new unsaved copy named "<name> (copy)"; Save adds it, Cancel discards it | BUILT |
| Editor | Name, pick-dice switch, a row per die (colour swatch, type + style, label, remove), quick-add buttons per type. New die takes the previous die's colour. Save disabled until there's a name and at least one die. Delete asks for confirmation. Saving puts the set on the table | BUILT |
| Example sets | First launch only. **Fireball:** 8 orange d6. **Risk:** 3 red d6 "Attack" + 2 ivory d6 "Defend", pick dice on. **RPG set:** one of each type in purple, pick dice on | BUILT |
| Remembers last set | App reopens on the last-used set | BUILT |
| Re-throw choice | Each set follows the global re-throw mode (Table default) or has its own: Live table, Count where they land or Clear the table. New sets and the example sets use Table default; Duplicate copies the choice. Changing only this choice keeps the set's long-press locks; any other edit still resets them. Quick rolls always use the global mode. **Re-throws** menu in the editor (under the pick-dice switch): "Table default (Clear the table)" (naming the current global mode), Live table, Count where they land, Clear the table. Drawer cards add a note such as "· count where they land" only when a set has its own mode | BUILT |

## 10. Roll history

| Feature | Spec | Status |
|---|---|---|
| The log | Last `50` rolls, newest first; oldest dropped when a new roll goes over. Fixed in code (not a setting) and applied on load too, so the saved file never holds more than 50 | BUILT |
| Each entry | Set name, time ("14:32", "Yesterday 14:32", or "11 Oct 14:32"), one chip per die in the die's colour with value and label, total. Mixed rolls show the type on each chip | BUILT |
| Copy a roll | **Copy** button on each entry copies it as plain text, e.g. `Risk (14:32): Attack (d6): 6  5, Defend (d6): 4  (total 15)`; the button briefly reads "Copied" | BUILT |
| Clear history | Asks "Clear all N rolls? This can't be undone." first | BUILT |
| Plain data | Each roll stored as structured data (time, set, total, each die's type, value, colour, label, d100 parts) so game rules can be layered on later without a rewrite. Each roll also records the re-throw mode it actually used (`live`, `count` or `clear`, never "default"), and each die whether its result was locked before a re-throw (`locked`) and how many full re-throws it needed (`rethrows`). Not shown in the history screen. Older entries without these load as normal | BUILT |

## 11. Storage

Files in the app's private folder (`user://`):

| File | Holds |
|---|---|
| `dice_sets.json` | Every set, plus the last-used set |
| `roll_history.json` | Up to 50 rolls |
| `settings.json` | Sound, vibration, fast-roll, tap-to-roll and menu-button switches, tips seen, and the global re-throw mode |

| Feature | Spec | Status |
|---|---|---|
| Safe saving | Each save writes a temporary file then swaps it in, so a crash mid-save can't damage data | BUILT |
| Re-throw modes | `settings.json` holds the global mode (`live`, `count` or `clear`); missing or unknown means `clear`. Each set may hold `rethrow_mode` (`default`, `live`, `count`, `clear`); missing or unknown means `default` (Table default), so older files need no migration and a set is never rejected over this field | BUILT |
| Damaged data | Everything loaded is checked: unknown die types, bad colours, overlong text, impossible results and too many dice are cleaned or skipped; totals recalculated. An unreadable file is kept aside as `*.corrupt.json`, never silently overwritten | BUILT |

## 12. Sound

| Feature | Spec | Status |
|---|---|---|
| Effects | Generated in code (no audio files or licences): soft thud on felt, wooden knock on the rim, sharp click between dice, softer click against the hand while shaking. Harder hits louder; slight pitch variation; max `5` sounds per `50 ms` so big rolls don't become noise | VERIFY ON DEVICE |
| Sound on/off | **Sound effects** switch in Settings. Muting stops anything playing. Choice saved; on for a fresh install | BUILT |

## 12a. Start menu & quick roll

| Feature | Spec | Status |
|---|---|---|
| Start menu | Shown after the splash every launch, over the splash art: **Continue: <current dice>**, Quick roll, Dice sets, History, Settings. The table loads behind it | BUILT |
| Quick roll | One-tap **1d6**, **2d6**, **1d20**, plus **Custom** (the editor without name or saving; its button reads Roll). Quick rolls are never saved as sets and show as "Quick roll" in the history | BUILT |
| Settings | Scrolling bottom sheet with switches for **Sound effects**, **Vibration**, **Fast roll**, **Tap or swipe to roll** and **Menu button on table** (off by default; Back always returns to the menu), the **Re-throws** choice, **Re-roll by hand**, plus **Show tips again**. All saved | BUILT |
| Re-throws choice | Three options, the chosen one outlined in orange, each with one line: **Live table** "Everything stays in play until all dice stop."; **Count where they land** "Dice that landed cleanly keep their result, like at a real table."; **Clear the table** "Settled dice are counted and removed before a re-roll." Below: "You can override this for individual dice sets in the set editor." | VERIFY ON DEVICE |
| Vibration | Short buzz when dice hit the table, rim or each other (`8–30 ms`, stronger for harder hits), at most one per `60 ms`. Not while shaking in the hand or during the warm-up throw. On by default. On Android 13+ buzzes are sent as media vibrations through the Android API, so they still play when the phone's touch vibration is off (Godot's built-in vibrate counts as touch feedback and gets dropped) | BUILT (confirmed on device) |
| Fast roll | Off by default. While dice roll, the physics plays out `1.75×` faster (same steps, more per frame, so results are unaffected), and results lift in `0.3 s` instead of `0.6 s` | VERIFY ON DEVICE |
| Tap or swipe to roll | On by default (switch in Settings). A quick tap on the table does what the main button does: Roll / Pick up, then Throw. A quick upward flick (at least `90 px` within `0.6 s`) throws held dice, harder for faster flicks (`400–2500 px/s` maps to throw power 0–1, like shake strength; never affects which face lands). Drags, long presses and taps while picking or rolling don't roll. While holding the dice, swiping side to side rattles them (faster swipes rattle harder) and a flick up at the end throws; lifting the finger without a flick keeps them in hand. Hints read "Tap to roll" / "Shake or swipe to rattle, flick or tap to throw" | VERIFY ON DEVICE |
| First-run tips | Until the first throw: over the table, "Tap the table to pick up the dice" with an animated tap ripple, then while holding the dice "Shake the phone, or flick up to throw" with an animated flick. Never block input. Text-only "Press Roll" / "press Throw" versions when Tap or swipe is off. Remembered once done; **Show tips again** in Settings brings them back | VERIFY ON DEVICE |
| Warm-up throw | A silent, unlogged practice throw runs behind the menu to warm up physics and rendering, to avoid a stutter on the first real roll | VERIFY ON DEVICE |

## 12b. Free & Pro

One-time **Pro** unlock (`bag_of_dice_pro`, non-consumable). Real Google Play Billing is not built yet: everything runs on a fake store behind a billing interface, so the real store can be added later as one new provider. Rolling, fairness, history, quick roll, picking dice and all settings are free and never gated.

| Feature | Spec | Status |
|---|---|---|
| Limits in one place | `scripts/pro/pro_config.gd`: free saved sets `3` (example sets count), free colours ivory, black, red, blue, green; Pro adds orange, yellow, teal, purple, pink; fake price `$3.99` | BUILT |
| Entitlements | Autoload `Entitlements` is the only source of truth: `is_pro()`, `pro_changed`, `can_add_set()`, `can_duplicate_set()`, `is_colour_available()`, `purchase_pro()`, `restore_purchases()`. Built around product ids so more one-time products can be added later | BUILT |
| Cached status | `user://entitlements.json` (`owned`, `confirmed_at`), safe-saved. Loaded at startup so the app works offline; the store's answer wins when it gives one, and a store error keeps the cache. Missing, damaged or wrongly shaped file = free (damaged kept as `.corrupt.json`) | BUILT |
| Billing interface | `BillingProvider`: connect, query product (localised price text), purchase (SUCCESS / CANCELLED / PENDING / ALREADY_OWNED / ERROR), query owned, acknowledge | BUILT |
| Fake store | `FakeBillingProvider`: every outcome, adjustable delay, offline mode, pending resolvable to success or failure, "owned" kept in `user://fake_store.json` so restore works across restarts. The only provider until the real one exists | BUILT |
| Double tap | A second Buy while a purchase is under way (or once owned) does nothing | BUILT |
| Grandfathered sets | Sets existing when the Pro update first runs stay usable for free; recorded in the sets file so a damaged status file can't grandfather more | OPEN |
| Developer panel | Debug builds only: Pro on/off, next outcome, delay, resolve pending, reset fake store | OPEN |
| Gating | Set limit, Duplicate (Pro badge), Pro colours (lock badge) with an upgrade sheet; never mid-roll | OPEN |
| Upgrade screen, restore, tier display | Price from the store, loading / unavailable / purchasing / pending / success / error states; Restore purchases; "Free" or "Pro (thank you!)" in Settings; small start-menu entry | OPEN |
| Losing Pro | Nothing deleted: sets beyond the limit locked (deletable, not usable), Pro colours kept on existing dice, last-used locked set falls back | OPEN |
| Free example colours | New installs: Fireball red, RPG set blue | OPEN |

## 13. Screen, visuals & controls

| Feature | Spec | Status |
|---|---|---|
| Main screen | Result bar at top (plus a menu button at top left if turned on in Settings); table and its drawer in the middle, framed to fit between the result bar and the buttons on any phone shape (the camera backs away on wider 16:9 screens); bottom bar with current set name, History, and main button (Roll / Pick up / Throw / Rolling…) | BUILT |
| Scene | Woven green felt, wood-grain rim, soft shadows, top-down camera tilted slightly towards the player | BUILT |
| Back button | Android Back closes, in order: a confirmation, the editor, a sheet, then cancels picking/arming, then returns to the start menu; Back on the menu leaves the app. One press counts once (Android delivers it twice) | BUILT (confirmed on device) |
| Text entry | Set names and labels use the phone keyboard. Whether the keyboard covers the field being typed into is unconfirmed | VERIFY ON DEVICE |

## 14. Performance

| Measured on the Mac, 20-die roll | Before | Now |
|---|---|---|
| Draw calls per frame, 20d6 | 178 | 58 |
| Draw calls per frame, 20d20 | 458 | 58 |
| Physics time per step | — | ≈ 1.5 ms |

| Feature | Spec | Status |
|---|---|---|
| How | Each die's numbers/pips are part of its own mesh, so a die is drawn as two pieces whatever its type; cheaper shadow settings | BUILT |
| First-roll hitch | First roll after launch has a one-off ~60 ms warm-up pause on the Mac | VERIFY ON DEVICE |
| Low-power idle | After `3 s` with no touch and nothing moving, the app draws only `10` frames a second and runs `30` physics steps a second (instead of the screen's full rate and `120`), to save battery and keep the phone cool. A touch, a held finger, a key or any activity switches straight back to full speed, and every state change (picking up, throwing) does so before any dice move. Always full speed while dice are thrown, while they're held ready to shake (shaking needs every sensor reading) and while a first-run tip is animating | VERIFY ON DEVICE |

## 15. Android build & branding

| Feature | Spec | Status |
|---|---|---|
| Export | Android preset for 64-bit ARM, package `com.btgog.bagofdice`, debug-signed, one-click install from the Godot editor. Only permission: vibrate (granted automatically at install). ETC2/ASTC texture compression enabled | BUILT (confirmed on device) |
| App icon | Leather dice bag with dice on felt. Adaptive icon (picture shrunk inside the safe zone, felt mirrored to fill the margin) plus a 192×192 legacy icon. Files in `assets/` | VERIFY ON DEVICE |
| Splash screen | Top-down felt tray with the dice bag. Fills the screen (cover); on phones taller than 9:16 the sides of the wooden frame are trimmed. Shown at least `1.2 s`. Alternative available: fit to screen with wood-coloured bands | VERIFY ON DEVICE |
| Release signing | Only needed to share beyond your own phone or publish | OPEN |

## 16. Tests

All in `tests/`. Run everything on the Mac with `tests/run_all.sh` (about 3 minutes; `--quick` skips the fairness test), or on a USB-connected phone with `tests/run_on_device.sh` (about 7 minutes). The phone run uses a separate test copy of the app (**Bag Of Dice Tests**, `com.btgog.bagofdice.tests`, export preset "Bag Of Dice Tests" with the `device_tests` feature), so the real app and its data are never touched; each test writes its results to a file inside that copy, which the script reads back over USB. App tests use throwaway `test_*.json` data files and refuse to run without them, so they never touch real sets, history or settings. Tests are excluded from the Android build.

| Test | What it checks |
|---|---|
| Set storage (`store_test.gd`) | 29 checks: first run, save/reload, cleaning bad data, d100 counting, corrupt file, delete |
| Roll history (`history_test.gd`) | 17 checks: 50-roll cap, newest first, reload, oversized/damaged files, clear, time display |
| Shake detector (`shake_detector_test.gd`) | 12 checks: shakes throw; bump, tilt, flip and disarmed shaking don't; with and without gravity sensor |
| Re-throw timing (`rethrow_timing_test.gd`) | A die re-thrown late in a roll gets the full time limit |
| Start menu (`start_menu_test.gd`) | Opens on menu, silent warm-up, quick and custom rolls not saved, sets/settings/Back |
| Set flow (`set_flow_test.gd`) | Create, roll, edit, delete a set; saved file matches; 20d6 rolls |
| d100 limit (`d100_limit_test.gd`) | d100 counts as 2 in the editor and on the table |
| Pick dice (`pick_dice_test.gd`) | Tap, untap, long-press lock, only picked dice thrown and logged, lock remembered, Back |
| Throw from hand (`throw_from_hand_test.gd`) | Throw button after settling and straight away; all dice land |
| Shake cup (`shake_cup_test.gd`) | 5 shakes: every die moves, none escapes, stopping the shake throws |
| Re-roll (`reroll_test.gd`) | 10 re-rolls mid-lift and after lift; all dice land |
| Sound switch (`sound_switch_test.gd`) | On by default, muting silences a roll, remembered next launch |
| Entitlements (`entitlements_test.gd`) | 23 checks: default free, cache, damaged/wrong-shape files, store answer vs cache, every purchase outcome, pending → declined / confirmed, acknowledgement, restore (none / restored / unavailable) across restarts, double tap, colour and set helpers |
| Settings & extras (`settings_extras_test.gd`) | Vibration and fast-roll switches applied and saved, fast roll only while rolling, Duplicate (and Duplicate + Cancel), copying a roll as text |
| Core rules (`core_rules_test.gd`) | 19 checks: project settings (Jolt at 120 steps, gravity 20, portrait 540×960, Mobile renderer, splash time); every die's faces and opposite sums; both d10 styles; d100 tens/units; ink colour; dice and table physics settings; throw speed, lift and shake-strength scaling; the at-rest rule; both safety nets; the hop limit; result bar wording; 00 + 0 = 100 |
| Sound & vibration (`feedback_test.gd`) | 14 checks: silent settling, every hit kind plays, harder is louder, 5 sounds per 50 ms, muting stops sounds, sound off; vibration skips soft hits and the hand, 60 ms gap, 8–30 ms by strength, vibration off |
| App flows (`app_flow_test.gd`) | 27 checks: the drawer (table and roller agree, sitting-out dice in it, thrown dice never in it, table and drawer fit on 20:9 and 16:9 screens); 1d6/1d20 quick rolls; Back order (clear question, history, editor, drawer, held dice, table to menu); history chips (plain or typed, labels, d100 parts, colours) and clearing; editor rules (Save needs a name and a die, new die's colour, 40-character names, delete confirmation); drag-scrolling the drawer, history and editor; lifted dice layout and facing; debug overlay only while a debug landing is on; low-power idle and waking; a damaged settings file |
| Drag scroll (`drag_scroll_test.gd`) | Dragging from a switch scrolls the Settings list without flipping it; a plain tap still flips it |
| Readability (`readability_test.gd`) | Every type reads a die inside its limit and refuses one past it; d4 limit; a d6 leaning on the rim inside its limit is read with no hop and eases flat without changing its result; past the limit it's hopped; hop outcomes over many forced ambiguous landings (fewer on the phone) |
| Re-throw modes (`rethrow_mode_test.gd`) | 21 checks: global default and damaged values, sets without the field or with junk, Table default following the global mode, a set's own mode, quick rolls using the global mode, Duplicate, locks kept on a mode-only edit, effective mode in history, old history entries |
| Re-throw behaviour (`rethrow_behaviour_test.gd`) | 23 checks: the bank (a die needing a re-throw leaves the table at once, the bank is thrown only when the table is still and read, banked dice go together); Clear the table lifts settled dice before the re-throw and the re-thrown dice join; Count where they land keeps counted dice dynamic, marked, and their results when knocked, never re-throwing them; Live table re-reads knocked dice, cascade cap, every roll finishes; escalation keeps locked results; parked dice untouched in every mode; re-throws aimed at open space vs normal ones at a group of settled dice (fewer trials on the phone) |
| Re-throw screens (`rethrow_app_test.gd`) | 17 checks: Re-roll by hand (saved, the bank comes back to the hand, Back and the menu can't abandon it, throwing finishes the roll); Settings choice, descriptions and tip; editor menu and its "Table default (…)" name following the global mode; drawer note; "Re-rolling" note; a knocked counted die shows its recorded face and the bar, lifted dice and history agree; Clear the table slides dice into the drawer mid-roll and lifts them with the rest at the end |
| Fairness (`fairness_test.tscn`) | Thousands of throws per die type, chi-square per die. Also run once per re-throw mode with 4 dice per table and a die forced onto another in 30% of rolls, so re-throws really happen (Mac only; too slow for the phone) |
| Re-throw diagnosis (`rethrow_diagnosis.tscn`) | Not pass/fail and not in the run-all scripts: hundreds of real rolls, reporting why dice were hopped or re-thrown, how flat accepted dice lie, parked-dice contact and which rim lean angles hold |

## 17. Out of scope

| Feature | Spec | Status |
|---|---|---|
| Game rules | No Risk battle resolution, D&D modifiers, advantage etc. Players compare results in the history | OUT OF SCOPE |
| Tilting table | No table tilt or live physics driven by phone movement (shaking only throws) | OUT OF SCOPE |
| Online features | No logins, cloud, sync, ads or analytics | OUT OF SCOPE |
| Desktop | No support for wide windows; mobile only | OUT OF SCOPE |

---

## Open items summary

1. Release signing (only if sharing/publishing the app)
2. Confirm the `VERIFY ON DEVICE` items on the phone, especially shake feel, keyboard in the editor, Back gesture, icon and splash, and the first-roll pause
3. Free & Pro, remaining steps: developer panel, gating and limit sheets, upgrade screen / restore / tier display, downgrade behaviour and grandfathering
4. Real Google Play Billing provider and plugin, Play Console product setup (needs a developer account)
5. Re-throw modes: built and tested on the Mac. Confirm on a phone: the feel of Clear the table lifting dice mid-roll, the dimmed counted dice and whether the dim is enough, the Re-throws choice in Settings and the editor menu, and that aimed re-throws look natural
6. The visible dice have rounded edges but their collision shapes are sharp, so a leaning die looks about 0.03 above the felt. Left as is unless it bothers the player
