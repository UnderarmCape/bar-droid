# DRAFT (not posted): beyond-all-reason/Beyond-All-Reason, the pregame texts on a tall screen

For BAR's repository (the official Android port). The change: [bar-pregame-upright.patch](bar-pregame-upright.patch)
(`git apply` in BAR's checkout; made against release test-31836-b250a16). Found and tested on 2026-11-12.

**Title:** Start position tutorial and victory condition text: readable on a tall (portrait) screen

**Body:**

Before a game starts, two widgets write over the map:

- `luaui/widgets/map_start_position_suggestions.lua` draws its tutorial ("Recommended start positions and roles are
  indicated within the circles. To disable this, ...") centred at 61 % of the screen's height, its font sized by the
  height (`resMult = vsy / 1440`) and wrapped at `tutorialMaxWidthChars` (100) characters. On a tall screen (a phone
  held upright: 936 x 2013 here) the font is 1.4 times its 1440p size and 100 characters make lines of about 1,500
  pixels: they run off both edges.
- `luaui/widgets/gui_game_type_info.lua` draws "Victory condition: ..." a fixed `60 * widgetScale` above its anchor
  (55 % of the height in draft games). On a landscape screen that is above the tutorial; on a tall one the anchor is
  higher and the offset relatively smaller, and the line lands inside the tutorial: the two texts over each other.

The change:

- the tutorial is wrapped to the screen's width as well (the characters that fit 90 % of it, measured with its own
  font, at most `tutorialMaxWidthChars` as before), and wrapped again when the screen is resized;
- the victory line's offset is at least 7.5 % of the screen's height (`math.max(widgetScale * 60, vsy * 0.075)`), the
  "own commander" line under it moved with it.

On a 1080p or 1440p landscape screen the tutorial keeps its 100 characters; the victory line moves up 18 pixels at
1080p and 35 at 1440p (still above the tutorial, as before).

**Tested** on the BAR Droid dev phone (Galaxy S23 Ultra, the game upright at 936 x 2013, the draft pregame of an 8v8
replay): the release's pool files of both widgets swapped for the patched ones (the copies trimmed of comment lines to
their originals' byte sizes, as the engine reads a pool file only up to the size the package lists): "Victory
condition: Kill all enemy Commanders" whole above the tutorial, the tutorial in four lines inside the screen (before:
two lines off both edges, the victory line through the first); both widgets loaded without errors. BAR's files put
back after (their md5s checked).

_This change was written with the help of an AI assistant (Claude Code) for the BAR Droid Android port._
