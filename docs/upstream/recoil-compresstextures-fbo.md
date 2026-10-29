# DRAFT (not posted): beyond-all-reason/RecoilEngine issues

**Before posting:** check it on the current engine release (seen on 2026.07.04 and 2026.09.01), and look at how the
two textures are created (`CTextureRenderAtlas::CreateAtlasTexture`, the projectile drawer's perlin texture): the
likely cause is a generic `GL_RGBA` internal format turned into a compressed one when `CompressTextures` is on.

**Title:** CompressTextures = 1 breaks the unit icon atlas and the projectile perlin texture (FBO "None/Unsupported
textures/buffers attached")

**Body:**

With `CompressTextures = 1` in springsettings.cfg, two textures the engine renders into are created compressed and
their FBOs fail:

```
Warning: FBO-TEXTURE-RENDER-ATLAS: None/Unsupported textures/buffers attached!
CTextureRenderAtlas::CreateAtlasTexture()[1] atlas=IconsAtlas_0 atlasRendered=0
Warning: FBO-PROJECTILE-DRAWER-PERLIN: None/Unsupported textures/buffers attached!
```

Unit icons then draw as black squares (the icon atlas is never rendered; it fails again each time it is rebuilt), and
the perlin noise texture the projectile drawer renders is missing. Seen on Windows (NVIDIA RTX 4090 laptop, engine
2026.09.01, BAR byar:test) and on Linux arm64 (Mesa Freedreno, Adreno 740, engine 2026.07.04). With
`CompressTextures = 0` (the default) both are fine.

Why it matters: `CompressTextures = 1` is the one client setting that brings BAR into an 8 GB phone (the engine's GPU
memory, which is RAM on a phone and cannot be swapped, drops from ~2.75 to ~2.45 GB in a 1v1 skirmish; with it the
game ran 3-10 minutes in every try, without it Android's low-memory killer ended it while loading in every try). If
render targets kept an uncompressed format whatever `CompressTextures` says, phones with less memory could use it.

Steps: `CompressTextures = 1`, start any skirmish, look for the lines above in infolog.txt, zoom out until units are
icons.

_This report was written with the help of an AI assistant (Claude); the failure was reproduced by running the engine._
