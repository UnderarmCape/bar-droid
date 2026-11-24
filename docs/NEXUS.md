# Nexus Mods page description

Paste the block below into the Nexus Mods page's description (it is Nexus BBCode). Before you paste it, fill in:

- `{IMG_BASE}`: the web address of the folder that holds the guide's pictures (the files made into `docs/guide/img/`), with no slash at the end. Every picture below is one that `docs/guide/pictures.txt` makes.
- `{GUIDE_URL}`: the web address of the full guide (the web page `python -I tools\guide-html.py` makes from `docs/GUIDE.md`). The web version is
  published at https://claude.ai/artifact/Rfyx83QDHcCBHTUikuTGvd (`python -I tools\guide-html.py` makes it); it is
  private until its owner shares it from the page's Share menu. Once this repository is public, `docs/GUIDE.md` on
  GitHub works too.
- `{RELEASES_URL}`: the web address of the GitHub Releases page with the APK (or the Nexus Files tab, if the APK is uploaded there).

```
[center][size=6][b]BAR Droid: Beyond All Reason on Android[/b][/size]

[img]{IMG_BASE}/upright-overview.jpg[/img][/center]

Play [url=https://www.beyondallreason.info/]Beyond All Reason[/url], the free real-time strategy game, on a Snapdragon Android phone: BAR's own lobby, online games with PC players, skirmish against the AI and spectating, at about 30 fps.
The app runs BAR's real engine on the phone and downloads the game from BAR's own servers. It adds a touch dock, gamepad controls, mouse and keyboard support and a layout editor.

[size=4][b]Requirements[/b][/size]
[list]
[*]A Qualcomm Snapdragon 8 Gen 2, 8 Gen 3, 8s Gen 3 or 8 Elite phone (Adreno 7xx or 8xx GPU)
[*]12 GB of RAM (8 GB phones play in a low-memory mode)
[*]About 6 GB of free storage
[*]Not for phones with Mali, Xclipse or Tensor GPUs
[/list]

[size=4][b]Getting started[/b][/size]
[list=1]
[*]Download the APK from [url={RELEASES_URL}]the Releases page[/url] and open it on the phone (allow installing when Android asks).
[*]Open [b]Beyond All Reason[/b] and tap [b]Install / Update[/b]: about 4 GB from BAR's servers, around 12 minutes on home Wi-Fi.
[*]Tap [b]Play vs AI[/b] for a skirmish, or [b]Lobby[/b] to log in and play online.
[*]Drag to pan, pinch to zoom, tap to select, long press to send units.
[*]Upright, use the touch dock at the bottom: the build grid, the orders, metal and energy, your groups.
[*]Hold three fingers on the screen to move and size panels in the layout editor.
[/list]

[center][img]{IMG_BASE}/sideways-overview.jpg[/img]

[img]{IMG_BASE}/dock-unfolded-commander.jpg[/img]

[img]{IMG_BASE}/editor-upright.jpg[/img]

[size=5][b][url={GUIDE_URL}]Read the full guide[/url][/b][/size]
From your first game to the layout editor, the gamepad and every setting.[/center]

[size=4][b]Credits[/b][/size]
Beyond All Reason and its game content are by the Beyond All Reason team: [url=https://www.beyondallreason.info/]beyondallreason.info[/url]. BAR's game, maps and engine are not in the app: they download from BAR's own servers.

BAR Droid is a fan project, not made by the Beyond All Reason team.
```
