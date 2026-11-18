# DRAFT (not posted): beyond-all-reason/RecoilEngine issues

**Before posting:** check the engine's current master still sets `isDirty = true` at the top of
`CArchiveScanner::ScanDirs` (it does on the tags 2026.07.04 and 2026.09.03; the patch applies to both as it is).

**Title:** Every VFS.ScanAllDirs rewrites ArchiveCache and runs the 1 s pool-file check, even when nothing changed

**Body:**

`CArchiveScanner::ScanDirs` sets `isDirty = true` before it scans, so `ScanAllDirs` always ends in `WriteCacheData`:
the whole ArchiveCache file written again (5 MB with BAR's pool) and, once the pool holds 10,000 files or more, the
existence check of random pool files, which runs until `MAX_POOL_VERIFICATION_TIME` (1 s) unless every file was checked
first. Where a stat is slow, every scan costs that second on the thread that called it. On Android (BAR's port, which
runs the engine in a proot container, where each stat is a trapped system call) it is 1.1 s a scan with BAR's 20,745
pool files:

```
[~ScopedOnceTimer][CArchiveScanner::ScanAllDirs] 1103ms
```

three times at each lobby start, once more each time Chobby's download handler gets a download's answer (it rescans for
the archive), so a missing map with no network froze the lobby ~4.5 s (Chobby tries four times). The scan itself, a
couple of stats per archive, takes ~15 ms there.

The attached patch leaves `isDirty` to what the scan changes: `ScanArchive` already sets it for a new or changed
archive; the patch adds a cached archive (or broken archive) not found on disk this time (its `updated` still false,
which `WriteCacheData` drops) and a new or changed `replaces` entry. The cache file's content is the same as before;
it is written when an archive is added, changed or removed. Measured on the engine with the patch (2026.07.04 and
2026.09.03, arm64): every scan 14-29 ms after the first start; a map moved out of `maps/` and back: the cache written at
each of those two starts (31 archives, then 32 again, the same size as before), fast again after.

What it leaves out: the pool check now runs only when the cache is written (an archive added, changed or removed),
not at every scan. Stale pool entries come from deleted pool files, which come with a removed or changed archive,
so they are still cleaned.

Patch: [recoil-archivecache-rewrite.patch](recoil-archivecache-rewrite.patch) (BAR Droid's phone engine carries the
same change behind its build flag: bardroid/sim 1b9350a, bardroid/sim-2026.09.03 a0365a7).

_This report was written with the help of an AI assistant (Claude); the timings were measured by running the engine._
