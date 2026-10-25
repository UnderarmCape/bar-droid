"""Minimal GNU-patch-like applier (unified diffs, -p1, offsets and fuzz up to 2 context lines, new files).
Windows has no GNU patch, and `git apply` rejects patches that need fuzz (Termux's virglrenderer patches do).
  python apply-patch.py <patch> <tree-root>
"""
import os, re, sys

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def parse(text):
    files, lines, i = [], text.split("\n"), 0
    cur = None
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- ") and i + 1 < len(lines) and lines[i + 1].startswith("+++ "):
            old, new = line[4:].split("\t")[0].strip(), lines[i + 1][4:].split("\t")[0].strip()
            cur = {"old": old, "new": new, "hunks": []}
            files.append(cur)
            i += 2
            continue
        if line.startswith("+++ "):          # header without a "---" line (GNU patch accepts these)
            cur = {"old": None, "new": line[4:].split("\t")[0].strip(), "hunks": []}
            files.append(cur)
            i += 1
            continue
        m = HUNK.match(line)
        if m and cur is not None:
            old_n = int(m.group(2)) if m.group(2) is not None else 1
            new_n = int(m.group(4)) if m.group(4) is not None else 1
            body, i = [], i + 1
            o, n = old_n, new_n
            while (o > 0 or n > 0) and i < len(lines):
                l = lines[i] if lines[i] != "" else " "
                tag = l[:1]
                if tag == "\\":
                    i += 1
                    continue
                body.append((tag, l[1:]))
                if tag in " -": o -= 1
                if tag in " +": n -= 1
                i += 1
            cur["hunks"].append({"start": int(m.group(1)), "body": body})
            continue
        i += 1
    return files


def strip1(p):
    p = p.replace("\\", "/")
    return p.split("/", 1)[1] if "/" in p else p


def find(src, block, near):
    if not block:
        return near
    best = None
    for pos in range(0, len(src) - len(block) + 1):
        if src[pos:pos + len(block)] == block and (best is None or abs(pos - near) < abs(best - near)):
            best = pos
    return best


def apply_hunk(src, hunk):
    body = hunk["body"]
    for fuzz in range(0, 3):
        lead = 0
        while lead < fuzz and lead < len(body) and body[lead][0] == " ":
            lead += 1
        trail = 0
        while trail < fuzz and trail < len(body) - lead and body[len(body) - 1 - trail][0] == " ":
            trail += 1
        core = body[lead:len(body) - trail]
        old = [t for tag, t in core if tag in " -"]
        new = [t for tag, t in core if tag in " +"]
        pos = find(src, old, max(0, hunk["start"] - 1 + lead))
        if pos is not None:
            return src[:pos] + new + src[pos + len(old):], fuzz, pos - (hunk["start"] - 1 + lead)
    raise SystemExit("hunk does not apply:\n" + "\n".join(tag + t for tag, t in body[:12]))


def main():
    patch, root = sys.argv[1], sys.argv[2]
    for f in parse(open(patch, encoding="utf-8", errors="surrogateescape").read()):
        target = f["new"] if f["new"] != "/dev/null" else f["old"]
        rel = strip1(target)
        path = os.path.join(root, rel)
        src = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n") if os.path.exists(path) else [""]
        for h in f["hunks"]:
            src, fuzz, offset = apply_hunk(src, h)
            if fuzz or offset:
                print(f"  {rel}: hunk at {h['start']} applied with offset {offset}, fuzz {fuzz}")
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="\n") as out:
            out.write("\n".join(src))
        print("  patched", rel)


if __name__ == "__main__":
    main()
