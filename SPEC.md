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
| At rest | A die is settled once slower than `0.1` units/s and rad/s for `0.4 s`. Results are read only when every thrown die is settled | BUILT |
| Cocked die | If the best face is more than `10°` from straight up, that die alone gets a small hop, up to `3` times, then is re-thrown on its own | BUILT |
| Landed on another die | If a resting die's lowest corner is more than `0.15` above the felt, it's lying on another die and is re-thrown on its own | BUILT |
| Safety nets | A die that leaves the table is re-thrown. A die moving continuously for `10 s` is re-thrown; the timer is per die and restarts on every throw or hop | BUILT |

## 6. Shake to roll & the hand

| Feature | Spec | Status |
|---|---|---|
| Arming | **Roll** arms a roll; button becomes **Throw**. Accelerometer is ignored unless armed. Disarms automatically once dice settle and the result is logged | BUILT |
| Shake detection | Gravity removed via the phone's gravity sensor (or a smoothed estimate if absent). Movement over `12 m/s²` counts as shaking. Needs `2` separate jolts or `0.35 s` of strong movement (a single bump or tilt doesn't throw). Throws when movement stays low for `0.25 s` | VERIFY ON DEVICE |
| Throw without shaking | Tapping **Throw** while armed throws at normal strength | BUILT |
| The hand (cup) | When armed, dice tumble into an invisible cup above the near half of the table as real physics objects. Shaking kicks them harder and more often the harder you shake; pinned dice get extra kicks. On release each die launches from where it ended up and keeps half its motion | VERIFY ON DEVICE |
| Cup containment | Thick sealed walls, top speed `9` inside the cup, any escaped die is put back in the middle | BUILT |

## 7. Picking dice (parking)

For games where only some of a set's dice are thrown at a time, e.g. one Risk set holding attack and defend dice.

| Feature | Spec | Status |
|---|---|---|
| Per-set option | "Pick dice before each throw" switch in the set editor. When off, every throw uses all dice | BUILT |
| Pick up | Main button reads **Pick up**. Dice laid out four per row (a d100's two dice share a row), with name tags above labelled dice | BUILT |
| Tap / long-press | **Tap** picks a die for this throw (lifts and brightens); tap again to put back. **Long-press** (`0.5 s`) locks a die: picked automatically every throw, orange ring, until long-pressed again. A d100 gets one oval ring around both dice. Locks last for the session, per set, and reset if the set is edited | VERIFY ON DEVICE |
| Sitting out | Unpicked dice wait greyed in a row along the near edge. Only thrown dice are read, shown, totalled and logged | BUILT |

## 8. Showing results

| Feature | Spec | Status |
|---|---|---|
| Result bar | Matching dice grouped, total shown when more than one die, e.g. `d6: 5 6 3 5` / `Total: 19`. Labels show as `Attack (d6): 5`; a d100 shows its parts, `48 (40 + 8)` | BUILT |
| Lifted dice | After settling, thrown dice glide up and line up under the result bar, face-on to the camera, result upright. Up to 5 per row (4 when a d100 is present so pairs stay together). Rows always fit between result bar and buttons. Lifting happens after the result is read, so it can't change it | BUILT |

## 9. Dice sets, drawer & editor

| Feature | Spec | Status |
|---|---|---|
| A set | Name (max `40` chars), pick-dice option, list of dice. Each die: type and face style, colour, optional label (max `24` chars) | BUILT |
| Dice limit | Max `20` physical dice per set. A d100 counts as 2 (max 10 d100s). "+ d100" disabled when only one place is left; switching a die to d100 in a full set is refused with an explanation | BUILT |
| Drawer | Set-name button (bottom left) slides up a sheet listing sets as cards: name, colour dots, summary (e.g. "8d6"), "· pick dice" where relevant. Current set outlined. Tap a card to pull the set out; tap outside or Close to dismiss | BUILT |
| Editor | Name, pick-dice switch, a row per die (colour swatch, type + style, label, remove), quick-add buttons per type. New die takes the previous die's colour. Save disabled until there's a name and at least one die. Delete asks for confirmation. Saving puts the set on the table | BUILT |
| Example sets | First launch only. **Fireball:** 8 orange d6. **Risk:** 3 red d6 "Attack" + 2 ivory d6 "Defend", pick dice on. **RPG set:** one of each type in purple, pick dice on | BUILT |
| Remembers last set | App reopens on the last-used set | BUILT |

## 10. Roll history

| Feature | Spec | Status |
|---|---|---|
| The log | Last `50` rolls, newest first; oldest dropped when a new roll goes over. Fixed in code (not a setting) and applied on load too, so the saved file never holds more than 50 | BUILT |
| Each entry | Set name, time ("14:32", "Yesterday 14:32", or "11 Oct 14:32"), one chip per die in the die's colour with value and label, total. Mixed rolls show the type on each chip | BUILT |
| Clear history | Asks "Clear all N rolls? This can't be undone." first | BUILT |
| Plain data | Each roll stored as structured data (time, set, total, each die's type, value, colour, label, d100 parts) so game rules can be layered on later without a rewrite | BUILT |

## 11. Storage

Files in the app's private folder (`user://`):

| File | Holds |
|---|---|
| `dice_sets.json` | Every set, plus the last-used set |
| `roll_history.json` | Up to 50 rolls |
| `settings.json` | Sound on/off |

| Feature | Spec | Status |
|---|---|---|
| Safe saving | Each save writes a temporary file then swaps it in, so a crash mid-save can't damage data | BUILT |
| Damaged data | Everything loaded is checked: unknown die types, bad colours, overlong text, impossible results and too many dice are cleaned or skipped; totals recalculated. An unreadable file is kept aside as `*.corrupt.json`, never silently overwritten | BUILT |

## 12. Sound

| Feature | Spec | Status |
|---|---|---|
| Effects | Generated in code (no audio files or licences): soft thud on felt, wooden knock on the rim, sharp click between dice, softer click against the hand while shaking. Harder hits louder; slight pitch variation; max `5` sounds per `50 ms` so big rolls don't become noise | VERIFY ON DEVICE |
| Sound on/off | Speaker button top right. Muting stops anything playing. Choice saved; on for a fresh install | BUILT (confirmed on device) |

## 12a. Start menu & quick roll

| Feature | Spec | Status |
|---|---|---|
| Start menu | Shown after the splash every launch, over the splash art: **Continue: <current dice>**, Quick roll, Dice sets, History, Settings. The table loads behind it | BUILT |
| Quick roll | One-tap **1d6**, **2d6**, **1d20**, plus **Custom** (the editor without name or saving; its button reads Roll). Quick rolls are never saved as sets and show as "Quick roll" in the history | BUILT |
| Settings | Bottom sheet; currently Sound effects. Kept in sync with the table's speaker button. Future options (haptics, fast roll, text size, backup) go here | BUILT |
| Warm-up throw | A silent, unlogged practice throw runs behind the menu to warm up physics and rendering, to avoid a stutter on the first real roll | VERIFY ON DEVICE |

## 13. Screen, visuals & controls

| Feature | Spec | Status |
|---|---|---|
| Main screen | Menu button (top left), result bar and sound button at top; table in the middle; bottom bar with current set name, History, and main button (Roll / Pick up / Throw / Rolling…) | BUILT |
| Scene | Woven green felt, wood-grain rim, soft shadows, top-down camera tilted slightly towards the player | BUILT |
| Back button | Android Back closes, in order: a confirmation, the editor, a sheet, then cancels picking/arming, then returns to the start menu; Back on the menu leaves the app | VERIFY ON DEVICE |
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

## 15. Android build & branding

| Feature | Spec | Status |
|---|---|---|
| Export | Android preset for 64-bit ARM, package `com.btgog.bagofdice`, debug-signed, one-click install from the Godot editor. No special permissions. ETC2/ASTC texture compression enabled | BUILT (confirmed on device) |
| App icon | Leather dice bag with dice on felt. Adaptive icon (picture shrunk inside the safe zone, felt mirrored to fill the margin) plus a 192×192 legacy icon. Files in `assets/` | VERIFY ON DEVICE |
| Splash screen | Top-down felt tray with the dice bag. Fills the screen (cover); on phones taller than 9:16 the sides of the wooden frame are trimmed. Shown at least `1.2 s`. Alternative available: fit to screen with wood-coloured bands | VERIFY ON DEVICE |
| Release signing | Only needed to share beyond your own phone or publish | OPEN |

## 16. Tests

In the project (`tests/`):

| Test | Checks |
|---|---|
| Fairness test (`fairness_test.tscn`) | Thousands of throws per die type, chi-square per die |
| Set storage test (`store_test.gd`) | 29 checks |
| History test (`history_test.gd`) | 17 checks |

| Feature | Spec | Status |
|---|---|---|
| Tests not yet in the project | Nine more tests exist only in Claude's temporary workspace and will be lost after the session unless moved into `tests/`: set create/roll/edit/delete flow, picking, the shaking cup, the shake detector, re-rolling while dice are shown, throwing straight from the hand, late re-throw timing, the d100 limit, the sound switch. Plus a one-command "run everything" script | OPEN |

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
2. Move the nine temporary tests into `tests/` with a run-everything script
3. Confirm the `VERIFY ON DEVICE` items on the phone, especially shake feel, keyboard in the editor, Back gesture, icon and splash, and the first-roll pause
