# Mobile RTS touch UX: patterns for porting a PC RTS (BAR / TA-style) to Android touch screens and foldables

Research date: 2026-11-22. Most sources are developer pages (Feral Interactive, Creative Assembly, Android Developers), reviews (Gamezebo, Pocket Gamer, GamePressure, 148apps), and UX references (NN/g, Game Accessibility Guidelines). Apple's HIG Gestures page did not render for the fetch tool, so Apple guidance is only cited through secondary sources (see Gaps). Where a finding comes only from a search-result snippet, the bullet says so.

## How do well-regarded mobile RTS/strategy games handle selection, orders, camera, building, queueing and help?

### Takeaway
The best-documented touch schemes come from Feral's Total War ports, Creative Assembly's ROME II touch mode and Company of Heroes mobile. They tell gestures apart by where the drag starts (on a selected unit it draws an order path, on terrain it pans the camera), by a hold before dragging (box select or drawing a path), or by a spring-loaded thumb hold (box select). They add-select by plain taps instead of modifier keys, use unit cards and select-by-type buttons for units off screen, and give hover replacements (tap-and-hold tooltips, a drag-to-preview command wheel). Reviews say these schemes work. Every port still turns fiddly with large groups in busy fights.

### Cited Findings

**Selection**
- Total War ROME II touch mode: tapping an unselected friendly unit adds it to the selection, tapping a selected unit removes it, and tapping terrain or sky clears the selection. Add/remove needs no modifier key. — [Total War encyclopedia, Touch Controls](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- ROME II box select is a two-hand quasimode. You hold the bottom-left of the screen (typically with the left thumb) and drag the box with a second finger ("Press & Drag"). — [Total War encyclopedia, Touch Controls](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- ROME II: double-tapping a friendly unit or its unit card moves the camera to it and does not select it. Three-finger squeeze groups the selected units, three-finger splay ungroups them (like the G key), and a three-finger right-to-left swipe acts as Escape. — [Total War encyclopedia, Touch Controls](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- Total War: EMPIRE mobile (Feral): you tap units on the battlefield or on the Card Bar, and each further tap adds to the selection. After an order is given, the next tap clears the selection. This "Automatic Deselection" behaviour can be changed in Options. — [Feral, EMPIRE mobile "Building an Empire"](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- ROME: Total War mobile's "Imperium Update" brought MEDIEVAL II's Positioning Mode, Melee Mode and Automatic Deselection customisations back to ROME. Feral treats deselect-after-order as a player preference. — [Feral News, Imperium Update](https://feralinteractive.com/en/news/patch-romana-the-imperium-update-massive-control-improvements-rome-total-war-ios-android)
- Company of Heroes iPad: you tap a squad to select it and tap the ground to move it. Selecting a group takes a two-finger double-tap-and-drag (an emulated click-drag). Squads can be grouped into teams that are selected with one button. The reviewer still found gathering 25 soldiers "an absolute chore". — [Gamezebo CoH iPad review](https://www.gamezebo.com/2020/02/19/company-of-heroes-ipad-review-a-solid-port-that-plays-great-on-ipad/)
- War Legends (mobile RTS): each unit type has a button that selects all units of that type. Box select is touch-and-hold for a beat, then drag, which the reviewer said "works incredibly well". — [Pocket Gamer, War Legends hands-on](https://www.pocketgamer.com/war-legends/hands-on/)
- Rusted Warfare (Android, TA-like): one Google Play reviewer says multi-unit selection is mapped to pinch and would rather have pinch zoom. They ask for hold-one-finger-then-swipe-another to box select. Another reviewer wants more control customisation. This is user-review evidence only, from a search snippet. — [grand-screen.com review aggregation](https://grand-screen.com/games/rusted-warfare-rts-strategy/reviews/)
- Construct RTS devlog (Scirra, browser/touch RTS): a tap selects or moves, a one-finger drag draws a selection box, and two fingers pinch or pan. A drag never issues a move command. — [Construct RTS devlog #5](https://www.construct.net/en/blogs/ashleys-blog-2/rts-devlog-input-gestures-1602)

**Orders and queueing**
- ROME II battle: dragging from the selection along a path issues a sequence of waypoint moves, so the drawn path is the queue. If the swipe crosses an enemy, it becomes an attack order. Adding a second finger during the drag adds resize or rotate to the formation. On the campaign map, adding more fingers cancels the order sequence. — [Total War encyclopedia, Touch Controls](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- EMPIRE mobile: tap a destination or target to move or attack, double-tap to charge, and tap-and-hold to draw a movement path. A two-finger drag lays units along a line, and the game slows down while you draw it. In Positioning Mode you tap-and-hold the selected units, then drag a box whose length and depth set the formation. Halt, move speed and combat behaviour buttons sit above the Card Bar at all times. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- ROME: Total War iPad: on both the campaign and battle maps you order units by drawing a path onto the target. Feral says freeform finger drawing gives more precision than the desktop controls. — [Feral, Building ROME: touch controls](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)
- Company of Heroes mobile: you tap-and-hold directly on a target, then pick the ability (for example a grenade), and the squad moves into range itself. — [Feral CoH mobile FAQ](https://feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios)
- CoH iPad: an active pause lets you queue moves in bulk and then watch them play out. — [Gamezebo](https://www.gamezebo.com/2020/02/19/company-of-heroes-ipad-review-a-solid-port-that-plays-great-on-ipad/)

**Command presentation (panel vs wheel)**
- CoH mobile offers two control methods that you switch in Options. The Command Panel works like a desktop RTS, with abilities bottom-right and tap-and-hold for a description. The Command Wheel is mobile-native: you tap-and-hold the squad, drag over an ability to read it, and release to choose it. Dragging back to the centre and releasing cancels. — [Feral CoH mobile FAQ](https://feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios)
- One review found the wheel worked better than the panel. It also said the gesture combinations take time to learn and are easily forgotten in the action. This is from a search-result summary. — [iPhone Life CoH review](https://iphonelife.com/content/company-heroes-game-review)

**Camera**
- ROME II: a one-finger drag on terrain or enemy units grabs the ground and pans. A one-finger drag over sky or outfield rotates. A two-finger twist rotates around the midpoint between the fingers, and pinch or spread zooms. A flick starts camera momentum, which a tap stops. Double-tapping the ground moves the camera there. On the campaign map, a two-finger drag anywhere rotates. — [Total War encyclopedia, Touch Controls](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- EMPIRE mobile: "drags, pinches and twists" pan, zoom and rotate. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- ROME iPad: pinch, spread, rotate and pan follow the standard iPad gestures, so they behave as players expect. — [Feral, Building ROME](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)
- Construct RTS: with two fingers down, movement of the midpoint pans and the change in finger distance zooms. Zoom is anchored at the midpoint and eases toward its target each tick. Starting a pinch cancels a selection box that one finger had begun. Lifting one finger leaves a pan-only pointer. — [Construct RTS devlog #5](https://www.construct.net/en/blogs/ashleys-blog-2/rts-devlog-input-gestures-1602)

**Layout**
- War Legends keeps its UI on the far left and right edges and only expands it when needed, so the battlefield stays clear. — [Pocket Gamer](https://www.pocketgamer.com/war-legends/hands-on/)
- MDN's mobile game guidance: making the play field bigger is better than covering half the screen with button images. This is from a search snippet. — [MDN, Mobile touch controls](https://developer.mozilla.org/en-US/docs/Games/Techniques/Control_mechanisms/Mobile_touch)
- Tiny Troopers developer Kim Soares dislikes virtual sticks on mobile and settled on a one-tap scheme after many iterations. He calls phone screen size the biggest challenge. This is from a search snippet; the page returned 403 to the fetch. — [AWN, Building RTS games for mobile](https://www.awn.com/blog/building-real-time-strategy-games-mobile-devices)
- CoH mobile locks orientation during play and allows changing it only on the Main Menu, so the notch never covers the interface. — [Feral CoH mobile FAQ](https://feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios)
- Feral redesigned EMPIRE mobile's panels, dividers and large buttons to tile "regardless of the screen's aspect ratio". — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)

**Help and discoverability**
- ROME II: holding the top-left of the screen enters a tooltip mode that shows UI tooltips without selecting anything. This is a spring-loaded replacement for mouse hover. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- ROME iPad: taps, holds and swipes operate the UI, and tap-and-hold is reserved for tooltips and info panels. Testers new to Total War found it hard to learn the mechanics and the touch controls at the same time, so Feral added Advisor help. — [Feral, Building ROME](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/); [search summary of the same dev diary](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)
- EMPIRE mobile: "First Time Help" gives context-sensitive tutorials over the first few turns, and an in-game manual is linked from across the UI. Advisors were made less chatty to save screen space and gather their notes into a turn-start Advisor's Report with links. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)

**Designed-for-touch RTS (simplification route)**
- C&C Rivals: the team built it on PC, but a lead designer says every decision was made for a touch interface. A reviewer notes that mouse precision is not needed because play reduces to tapping hexes, and that the scale (unit count, map size) is smaller than in earlier C&C games. These come from search snippets. — [C&C Rivals blog interview](https://cncrivals.blogspot.com/2022/02/part-2-interview-with-lead-gameplay.html); [gamecloud review](https://gamecloud.net.au/?p=59560)
- Rivals combat designer Greg Black says other mobile strategy games lacked direct unit control and economy management, and that Rivals kept both. — [EA interview, Greg Black](https://www.ea.com/news/greg-black-command-and-conquer)

### Inferences
- Disambiguating by where a drag starts (ROME II: from a selected unit it draws orders, from terrain it pans, from sky it rotates) is the strongest shipped answer to "one finger means pan or order". It needs no mode button. In BAR terms: a drag that starts on a selected unit or its card draws a line-move or formation, and any other drag pans.
- A tap that adds to or removes from the selection (ROME II, EMPIRE) replaces Shift/Ctrl-click without a sticky modifier. Clearing on tapping empty ground, or Automatic Deselection, needs to be an option, because Feral found that players differ.
- Unit cards and select-by-type buttons (EMPIRE Card Bar, War Legends) do the job that box select struggles with in large fights (the CoH "25 soldiers chore"). For BAR, with hundreds of units, select-all-of-type and saved groups as big dock buttons matter more than a good box select.
- Slowing or pausing the game while an order is drawn (EMPIRE slow-down, CoH active pause) is a single-player tool. BAR online cannot pause, so this has to be skirmish or offline only. Online games must rely on pre-planning tools (queued paths, a ghost preview) instead.

### Gaps
- I found no official Rusted Warfare control documentation; the only evidence is user reviews.
- No detailed description of Age of Empires Mobile or Warcraft Rumble touch selection surfaced. GamesRadar's AoE Mobile piece was a headline-only hit ([GamesRadar](https://gamesradar.com/games/how-age-of-empires-mobile-is-scaling-down-the-series-classic-historical-action-for-smaller-screens-we-built-this-rts-around-the-ethos-of-control)).
- I did not research Northgard's specific gestures. Reviews only say they are well thought out (GamePressure), that they glitch when moving across the map (Pocket Gamer snippet), and that long matches fit mobile poorly (148apps). — [GamePressure](https://www.gamepressure.com/editorials/the-best-mobile-games-2021-editors-choice/northgard-finally-a-good-mobile-rts/z14f7); [148apps](https://148apps.com/reviews/northgard-review); [Pocket Gamer](https://www.pocketgamer.com/northgard/review/)
- Bad North, Frozen Synapse, XCOM, Ultimate Admiral and Art of War 3 were not covered within the tool budget.
- The encyclopedia touch page's URL prefix "r2enc" and its asset path "empiredivided" (a ROME II campaign pack) point to Total War: ROME II's Windows touch mode. I inferred the game name; the page does not state it.

## What do Android/Material, Apple HIG and game-UX/accessibility guidance say about target size, mode errors, gesture conflicts, undo and feedback?

### Takeaway
Use touch targets of at least 48dp (Android), or 44pt (iOS), with about 8dp between them. Keep the active mode visible with at least two indicators, and prefer spring-loaded (held) modes when a mode slip would be costly. Edge swipes belong to the system: games can exclude side-edge regions for back only during gameplay, and they cannot exclude the bottom home gesture except through immersive mode. Haptics should be short and crisp (10-20 ms keyclicks), tied to how important the event is, and absent rather than buzzy. Accessibility guidance asks for large spaced controls, alternatives to held buttons and multi-finger gestures, adjustable sensitivity and speed, rearrangeable and resizable UI, and in-play reminders of the controls.

### Cited Findings

**Target size**
- Google's Android accessibility help: touch targets of at least 48dp, about 9 mm, with 8dp spacing (from search snippets). — [Google Accessibility Help, Touch target size](https://support.google.com/accessibility/android/answer/7101858?authuser=0); [Baseflow accessibility guidelines](https://baseflow.github.io/accessibility-guidelines/navigation/touch-targets.html)
- Apple recommends 44 x 44 pt (secondary sources). One critic argues that 44 conflates target size with the spacing needed against interference, and treats them as separate concerns. — [Siteimprove, touch target problem](https://www.siteimprove.com/blog/motor-impairments-and-mobile-ui-the-touch-target-problem); [Steven Hoober, "44 px: Why Apple is Wrong"](https://medium.com/@shoobe01/44-px-why-apple-is-wrong-6bd6f6846871)
- Avoid putting critical buttons at the screen edges, where cases and bezels make them hard to tap (generic UX guidance, from a search snippet). — [UXPin, touch devices](https://www.uxpin.com/studio/blog/responsive-design-touch-devices-key-considerations/)
- Game Accessibility Guidelines (basic): "Ensure interactive elements / virtual controls are large and well spaced, particularly on small or touch screens". Intermediate: make elements that need accuracy stationary. — [Game Accessibility Guidelines, full list](https://gameaccessibilityguidelines.com/full-list/)

**Mode errors**
- NN/g on modes: a mode means the same input gives different results. Mode slips come mainly from poor status visibility. Its fixes are: make the active mode highly visible with at least two visual indicators (for example a highlighted control plus a cursor change), label and explain each mode, avoid modes where an error is costly, show constructive messages when the system can infer that the user meant another mode, and use confirmation dialogs sparingly because people learn to click "Yes" reflexively. — [NN/g, Modes in User Interfaces](https://www.nngroup.com/articles/modes/)
- NN/g: spring-loaded modes (quasimodes), active only while something is held, prevent mode slips. They are harder to discover and less efficient for long stretches. — [NN/g](https://www.nngroup.com/articles/modes/)

**Gesture conflicts (Android)**
- Since Android 10, back is an inward swipe from the left or right edge. Apps can opt out in specific regions with `View.setSystemGestureExclusionRects()`. Games without a view hierarchy use `Window.setSystemGestureExclusionRects()` and must exclude areas only when needed, such as during gameplay. — [Android Developers, gesture navigation](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav)
- Home and quick-switch are bottom-edge swipes that apps cannot opt out of. `WindowInsets.getMandatorySystemGestureInsets()` reports their thresholds. A game that needs swipes near the home area can request immersive mode: this disables system gestures during play, and a swipe from the bottom brings them back. — [Android Developers, gesture navigation](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav)
- Android 13+ predictive back lets users preview the back destination before committing, on phones, large screens and foldables. — [Android Developers, gesture navigation](https://developer.android.com/develop/ui/views/touch-and-input/gestures/gesturenav)
- Generic guidance: a custom gesture should have a tappable fallback, such as a menu alongside swipe-to-delete. — [Universal Design Ireland, simple mobile gestures](https://universaldesign.ie/communications-digital/web-and-mobile-accessibility/web-accessibility-techniques/design-accessible-digital-content-introduction-and-index/design-accessible-navigation/use-simple-mobile-gestures-for-interaction)

**Accessibility (GAG)**
- Intermediate: "Avoid / provide alternatives to requiring buttons to be held down". — [GAG](https://gameaccessibilityguidelines.com/full-list/)
- Intermediate: ensure multiple simultaneous actions (for example click/drag or swipe) are not required, and keep them only as supplementary or alternative input. Also ensure all key actions can be done with digital presses, with gestures supplementary only. — [GAG](https://gameaccessibilityguidelines.com/full-list/)
- Basic: an option to adjust control sensitivity, remappable controls, and an option to adjust game speed. Intermediate: interfaces can be rearranged and resized. Advanced: precise timing is not essential. — [GAG](https://gameaccessibilityguidelines.com/full-list/)
- Basic: interactive tutorials, and no essential information conveyed by colour alone. Intermediate: reminders of the controls and current objectives during play, and contextual in-game help. — [GAG](https://gameaccessibilityguidelines.com/full-list/)

**Haptics (Android)**
- Android haptics principles: less is more, because too much vibration is annoying or numbing and leads users to turn haptics off. Use haptics to notify, to confirm a state change after a user action, or to add delight. — [Android Developers, haptics principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- Prefer clear or rich haptics. "Given the choice of buzzy haptics or no haptics for touch feedback, choose no haptics." — [Android Developers, haptics principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- Use the action-oriented `HapticFeedbackConstants`, which get platform fallbacks and stay consistent. Make frequent events very subtle and important ones stronger, and ramp ticks up as a drag approaches a snap target. Co-design haptics with sound and visuals, because out-of-sync haptics feel broken. Avoid legacy one-shot vibrations. A keyclick should last 10-20 ms, but the actuator can ring 20-50 ms longer. — [Android Developers, haptics principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)

**Foldables and large screens (Android)**
- Adaptive app quality, Tier 3 (baseline): runs full screen, not letterboxed or in compatibility mode, with basic keyboard, mouse, trackpad and stylus support. Tier 2: layouts optimized for all sizes. Tier 1: designed for the device, including foldable postures (tabletop, book), multitasking and stylus where applicable. — [Android adaptive app quality guidelines](https://developer.android.com/docs/quality-guidelines/large-screen-app-quality)
- Recommended test sizes include foldables with a 1:1 inner display (802x802 dp) and a 4:3 inner display (1024x768 dp), and an 8-inch tablet (1024x640 dp). — [Android adaptive app quality guidelines](https://developer.android.com/docs/quality-guidelines/large-screen-app-quality)

### Inferences
- An RTS "armed command" (attack-move, build ghost, line draw) is a mode in NN/g's sense, with costly slips such as an unintended attack-move or a mis-placed factory. NN/g's two-indicator rule suggests a highlighted dock button plus an on-map cue, such as a coloured ghost or cursor ring or a tinted screen border, whenever a command is armed.
- ROME II's bottom-left thumb hold is a quasimode that fits NN/g's slip-prevention advice. On Android, though, the left edge is the back gesture. Any edge-hold zone needs an exclusion rect during play, or it should sit inset from the edge.
- Haptics for a BAR port: a light tick on selection change, a slightly stronger confirm when an order or build is accepted, a distinct reject on an invalid placement, and nothing on every pan or zoom frame. This follows the frequency/importance rule.
- Z Fold7 note: the unfolded inner screen is close to Google's 1:1 test class and the cover screen is tall and narrow. The HUD needs two layouts (or a fluid one), and the game must survive fold/unfold without losing state. This is an inference from Google's tiering; I did not find a Fold-specific RTS case study.

### Gaps
- Apple's HIG Gestures page did not render (JS-only), so I have no verified Apple quotes on custom gestures, edge gestures or undo.
- I found no authoritative guidance on undo for real-time games. GAG has no undo or confirmation item.
- The Android gesture-nav page does not quote the exclusion-rect size cap, so check the `View.setSystemGestureExclusionRects` API reference before relying on large edge zones.
- I could not reach Celia Hodent ("The Gamer's Brain") or the Game UX Master Guide within the tool budget, so no citations from them.

## What specifically helps with pan-vs-draw conflicts, a mouse pointer left behind by a tap, orders to far-off targets, queue-mode visibility, and long tasks that need confirmation?

### Takeaway
Shipped games avoid a pan-or-draw mode toggle. They tell gestures apart by where the drag starts (ROME II), by a hold before the drag (EMPIRE, War Legends), by a second finger (ROME II formations, EMPIRE line), or by a held quasimode (ROME II box select). They decide tap versus drag on release, using a distance threshold (Construct: 30 px). Hover is replaced by explicit hold-to-inspect quasimodes. Off-screen units are reached through unit cards, select-by-type buttons and double-tap-to-jump. Queues are made visible by drawing the path itself.

### Cited Findings

**Pan vs draw**
- ROME II: the same one-finger drag pans on terrain, rotates on sky, and issues a waypoint path when it starts on the friendly selection. A second finger adds formation shape. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- EMPIRE mobile: tap-and-hold, then drag, draws a path (a time-based split). Tap-and-hold on the selected units enters Positioning Mode, and a two-finger drag lays a formation line. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- War Legends: hold for a beat, then drag, gives a box select; otherwise a drag pans. — [Pocket Gamer](https://www.pocketgamer.com/war-legends/hands-on/)
- Construct RTS: classify on pointer-up, not pointer-down. A pointer that moves more than `MAX_TAP_DIST` (30 px) becomes a drag; otherwise it is a tap. Track positions in client (screen) coordinates and convert to world coordinates only when needed. This avoids a feedback loop where panning changes the pointer's world position. — [Construct RTS devlog #5](https://www.construct.net/en/blogs/ashleys-blog-2/rts-devlog-input-gestures-1602)
- Construct RTS: when a second finger arrives, cancel any in-progress one-finger selection box and switch to pinch/pan. — [Construct RTS devlog #5](https://www.construct.net/en/blogs/ashleys-blog-2/rts-devlog-input-gestures-1602)
- ROME II campaign: adding more fingers cancels an order sequence, giving a built-in abort for a mis-drawn path. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)

**Hover replacement (the problem behind the left-behind pointer)**
- ROME II: holding the top-left of the screen enters tooltip mode, which inspects without selecting. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- CoH mobile: tap-and-hold an icon for its description. On the Command Wheel, dragging over an option previews it and releasing in the centre cancels, which is preview-before-commit with no hover. — [Feral CoH mobile FAQ](https://feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios)
- ROME iPad: tap-and-hold is reserved for tooltips and info panels. — [Feral, Building ROME](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)

**Far-off-screen targets**
- ROME II: double-tapping a unit card moves the camera to that unit, and double-tapping the ground moves the camera there. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts)
- EMPIRE: units can be selected from the Card Bar even when they are off screen. A Lists Panel holds regions, armies, fleets and agents, and the Advisor's Report links straight to points of interest. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- War Legends: select-all-of-type buttons; CoH: team buttons. — [Pocket Gamer](https://www.pocketgamer.com/war-legends/hands-on/); [Gamezebo](https://www.gamezebo.com/2020/02/19/company-of-heroes-ipad-review-a-solid-port-that-plays-great-on-ipad/)
- Construct RTS: zoom anchored at the pointer lets you zoom out, reposition and zoom back in on a new point. — [Construct RTS devlog #5](https://www.construct.net/en/blogs/ashleys-blog-2/rts-devlog-input-gestures-1602)

**Queue visibility, confirmation and long tasks**
- In ROME II and the ROME iPad port, the drawn path is the queued sequence, so the queue is visible as you make it. — [Total War encyclopedia](https://r2encv2.totalwar.com/en/manual/single-player/0005_enc_page_help_keyboard_shortcuts); [Feral, Building ROME](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)
- NN/g: keep modes visible with two indicators and use confirmations sparingly, as a last check. — [NN/g](https://www.nngroup.com/articles/modes/)
- EMPIRE slows the game during formation drawing; CoH uses active pause. GAG asks for adjustable game speed and no essential precise timing. — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire); [Gamezebo](https://www.gamezebo.com/2020/02/19/company-of-heroes-ipad-review-a-solid-port-that-plays-great-on-ipad/); [GAG](https://gameaccessibilityguidelines.com/full-list/)

### Inferences
- The left-behind pointer: on touch there is no hover, so any engine logic that reads the cursor position after a tap (hover highlights, tooltips, "unit under cursor" for the next command, edge scrolling) acts on a stale position. Shipped ports turn hover into explicit hold-to-inspect. For BAR this suggests parking or invalidating the emulated mouse after each tap-up, and turning off edge-scroll while the input is touch. Treat this as a design inference; I found no published post-mortem of this exact bug.
- Far targets in BAR: minimap tap-to-jump, plus minimap tap-to-order while a command is armed, follows the double-tap-to-jump pattern. Selecting by card or type (EMPIRE, War Legends) covers orders to units the player cannot see.
- Queue mode: when a sticky "queue" toggle replaces Shift, NN/g's two-indicator rule applies, for example a lit dock button plus queue numbers or a path line drawn on the map. ROME II's draw-the-path approach avoids a sticky queue mode entirely for movement.
- Long, costly orders (expensive builds, mass self-destruct, share or give): the ghost or preview is the main confirmation. Keep explicit confirmation dialogs for rare and irreversible actions only, or players learn to tap "Yes" reflexively (NN/g).

### Gaps
- I found no shipped-game source for minimap-tap orders on mobile, ping lists, or edge-panning while an armed command is held.
- I found no source on queue-mode indicators in a mobile RTS beyond drawn paths.

## How do mobile RTS games present a build menu with many items, and how does build placement work?

### Takeaway
The evidence is thin. CoH mobile nests construction inside its command wheel: one ability ("Build Defensive Structures") swaps the wheel to show all constructions, which are previewed by drag-over and committed on release. EMPIRE mobile's Card Bar lists every building site in a region for one-tap upgrades. I found no well-documented shipped example of ghost placement with confirm/rotate/line-build on touch.

### Cited Findings
- CoH mobile: dragging over some wheel abilities opens sub-options. For an Engineer, "Build Defensive Structures" changes the wheel to show all available constructions. Releasing over an option picks it, and releasing in the centre cancels. In Command Panel mode, abilities sit in a bottom-right panel with tap-and-hold for info. — [Feral CoH mobile FAQ](https://feralinteractive.com/en/faqs/companyofheroes/1.0.2/ios)
- EMPIRE mobile: the Card Bar shows every building site in a region, so an upgrade takes one tap. Recruitment is unified in one interface (land units in the capital, fleets in ports). — [Feral, EMPIRE mobile](https://feralinteractive.com/en/games/empiremobile/android-ios/building-an-empire)
- Mindustry (mobile, from an itch.io comment): you can change build direction both with a button and with the direction your finger travels while placing. This comment is not verified as Mindustry-specific beyond the page it sits on. — [anuke.itch.io Mindustry comments](https://anuke.itch.io/mindustry/comments?before=673)
- Generic placement guidance: GAG asks for accuracy-dependent elements to stay stationary and controls to be large and spaced. — [GAG](https://gameaccessibilityguidelines.com/full-list/)

### Inferences
- For BAR's long build lists, a two-level structure matching CoH's wheel (category, then item) keeps each page inside 48dp targets. On a phone this can be pages of big icons, and on the Fold7 inner screen one larger grid. Recents and favourites would cut it further, but I found no shipped source for those in an RTS.
- Placement with a 30 px tap/drag split: a tap places a ghost, a drag on the ghost moves it, and a drag that starts on the ghost's edge or a second finger draws a line or grid. Explicit confirm and cancel buttons near the thumb make placement reversible before it is committed. This extends the CoH preview-before-commit idea and ROME II's "start point decides the gesture" idea. Invalid spots should show a red ghost plus a reject haptic (two indicators, as NN/g advises).

### Gaps
- I found no documented examples of touch ghost-with-confirm, rotate buttons, or line/grid placement in a shipped mobile RTS (Rusted Warfare, Mindustry, AoE Mobile). Mindustry's GitHub or wiki and Rusted Warfare's in-game help would be the primary sources to check.
- I found no source on recents or favourites in RTS build menus on mobile.
- Pre-game and setup screens: the only finding is CoH locking orientation to the Main Menu, plus Feral's aspect-ratio-independent panels. Nothing specific on lobby or skirmish setup UX turned up.

## What commonly goes wrong in PC-to-mobile RTS ports?

### Takeaway
The recurring failures are these. Selecting and moving large groups becomes slow and fiddly in busy fights. Gesture vocabularies are learnable but forgotten under pressure. Players have to learn the game and the touch scheme at once. Camera movement glitches. Gesture assignments clash with what players expect (pinch for select instead of zoom). Customisation is missing. Long PC-length matches fit mobile sessions poorly.

### Cited Findings
- CoH iPad: controls turn fiddly in busy scenes. Gathering 25 soldiers was a chore that would take two clicks on PC, and the reviewer lost many units to it. The reviewer still judged it a solid port. — [Gamezebo](https://www.gamezebo.com/2020/02/19/company-of-heroes-ipad-review-a-solid-port-that-plays-great-on-ipad/)
- CoH mobile: the gesture combinations take time to learn and are easily forgotten when the action heats up (from a search-result summary). — [iPhone Life](https://iphonelife.com/content/company-heroes-game-review)
- ROME iPad: newcomers struggled to learn Total War and the touch controls at the same time, and Feral added Advisor help. — [Feral, Building ROME](https://www.feralinteractive.com/en/news/building-rome-the-touch-controls-of-rome-total-war-on-ipad/)
- Northgard mobile: the controls glitch a little when moving across the map (Pocket Gamer snippet). 148apps cites technical problems, design choices it did not like, and long matches that suit mobile poorly. — [Pocket Gamer](https://www.pocketgamer.com/northgard/review/); [148apps](https://148apps.com/reviews/northgard-review)
- Rusted Warfare users: pinch is used for multi-select when they want zoom, and they ask for more control customisation (user reviews). — [grand-screen.com](https://grand-screen.com/games/rusted-warfare-rts-strategy/reviews/)
- Feral plans no controller support for CoH mobile. — [TouchArcade](https://toucharcade.com/2023/09/06/company-of-heroes-mobile-controller-support-no-plans-feral-interactive-confirms)
- Unit selection has historically been the hardest part of moving PC RTS games off mouse and keyboard (said of AoE II's console port; search snippet). — [Tom's Guide](https://www.tomsguide.com/features/age-of-empires-ii-xbox-controller)
- C&C Rivals avoided the precision problem by shrinking scale and snapping play to hexes. The designer criticised other mobile strategy games for dropping direct control and economy. — [gamecloud](https://gamecloud.net.au/?p=59560); [EA, Greg Black](https://www.ea.com/news/greg-black-command-and-conquer)
- Feral backported control refinements (Positioning Mode, Melee Mode, deselection options) to ROME after launch, so the first-release scheme was not final. — [Feral News, Imperium Update](https://feralinteractive.com/en/news/patch-romana-the-imperium-update-massive-control-improvements-rome-total-war-ios-android)

### Inferences
- For a BAR port (hundreds of units, far bigger than CoH squads), the CoH lesson suggests that bulk tools carry the weight: select-all-of-type, saved groups and select-on-screen. Box precision matters less.
- Ship with deselect-after-order and gesture sensitivity as options, since Feral and GAG both point to preference variance. Plan for post-launch control iteration.
- Teach the controls separately from the game, through first-time contextual help and an always-reachable controls reminder (GAG intermediate). Kailil's "big buttons, no hint text" rule for the dock can sit alongside long-press tooltips (CoH, ROME), which show help only when asked.
- One-handed and left-handed play: GAG's remap, rearrange and resize items are the only sourced support. ROME II's left-thumb box-select hold is handedness-specific, so a mirrored layout option would be the inference.

### Gaps
- I found no GDC talk summary on mobile strategy UX within budget.
- I found no published left-handed or one-handed layout study for mobile RTS. Rovio's Battle Bay support page title shows that some games let players move and resize controls ([Rovio support](https://roviosupport.helpshift.com/hc/en/11-battle-bay/faq/2594-battle-controls)), but it is not RTS-specific.
