# Mobile models (engine branch)

Mobile versions of every S3O model in BAR's game (units, wrecks, raptors, scavengers, event skins, rocks: 2,044 in
`test-31836`), made on the laptop and drawn by the engine branch in place of BAR's own (`BarDroidModelOverrideDir`,
`rts/Rendering/Models/BarDroidModelOverride.cpp`). Drawing only: BAR's model is parsed as always and gives every size,
bound and collision volume; the mobile file replaces the pieces' vertices and triangles that are uploaded and drawn.
BAR's files and the game archive are never touched (online play; docs/ENGINE-SIM.md "Mobile models").

The models are BAR's art (CC-BY-NC-ND); BAR's developers cleared Kailil to ship phone-made derivatives (CLAUDE.md,
"Rules of the road"). The generated files stay out of git (`C:\Tools\BARANDROID\engine-sim\mobile-models\`); this folder
holds the tools.

```
tools\mobile-models\build.bat                                     # mobile_models.exe (w64devkit, meshoptimizer 0.23)
python -I tools\mobile-models\extract.py --out C:\Tools\BARANDROID\engine-sim\mobile-models --adb <adb.exe>
                                                                  # BAR's models and unit textures off the phone's byar:test
cd C:\Tools\BARANDROID\engine-sim\mobile-models
.\mobile_models.exe build --src src --out out --qa                # every model (~3.5 min on 32 threads) + out\report.tsv
.\mobile_models.exe render --a src\objects3d\units\armcom.s3o --b out\objects3d\units\armcom.s3o [--c ... --lod c] --tex src\unittextures --png x.png [--size 320] [--zoom 1.6]
powershell -File tools\mobile-models\push.ps1 [-Device R5CW22GVC3D] [-Remove]   # out\objects3d -> files/bar/bardroid-models
```

## What the cut does

`mobile_models.cpp`, per piece (pieces move apart, so each is cut on its own):

1. **Hidden triangles out**: triangles no camera can see from 320 directions (facing away, as the engine culls S3O back
   faces, or behind the piece's own front faces; what hides them moves with them in every animation).
2. **Half-edge collapses** (a vertex moved onto a neighbour: every kept vertex is one of BAR's, with its own normal and
   texture coordinates), cheapest change of shape first (Garland-Heckbert quadrics; open borders and texture seams
   kept straight by extra planes), each checked before it is made:
   - the surface stays manifold; no triangle turns over in space or on the texture, or far (50°) from where it pointed;
   - texture islands stay whole: corners that move along a seam take the matching vertex at the other end; an island
     may grow over another only where the texture's colours match;
   - the new triangles, 12 points each, against BAR's surface: within `--dist` (1.5 elmos, and 3 % of the model's
     radius), mean colour difference under `--color` (0.04 of RGB + the team-colour mask), at most 5 % of the points
     more than 0.15 off;
   - and back: BAR's points merged away stay within reach of the new surface, and BAR's **outlines** (seams whose two
     sides differ in colour: panel edges, the team colour's) within half that distance of the new seams.
3. A **coarse level** for units small on the screen (`BarDroidModelLodPixels`): the same cut continued with 4 elmos /
   7 % of the radius and looser colours, over the same vertices.
4. meshoptimizer's vertex cache order, then fetch order; BAR's vertices 0 and 1 first in every piece (the engine aims
   weapons and effects from vertex 0 towards vertex 1).

The file is an S3O (any S3O viewer shows the fine level) with two marks in fields the engine never reads: the header's
collision data points at `BDMOBIL1` + the FNV-1a 64 hash of BAR's file it was made from (the engine draws it only for
that very file) + flags; a piece's collision data at `BDL1` + count + its coarse triangles.

`--qa` renders BAR's model and the mobile one from five views (192 px, the coarse level at 64 px) and writes the mean
colour difference, the outline pixels only one covers and the share of pixels more than 0.1 off to `report.tsv`.
