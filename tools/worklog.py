"""The project's work log: Kailil's messages to Claude and Claude's answers, with the time each side spent, read from
Claude Code's session transcripts (~/.claude/projects/*/*.jsonl). Kailil (2026-10-28): "make sure my back and forth
with you and feedback is logged so they can know the effort and time spent geting this up and running. i want the time
logging from now moving forward as well for statistics."

Writes docs/worklog/data/{sessions.json,messages.jsonl} (merged with what is there: Claude Code deletes transcripts
after a month, the log keeps them), docs/worklog/<day>.md and docs/WORKLOG.md. Rerun it at the end of every work
session. A BAR Droid session is one whose transcript names the project often enough (MARKERS, MIN_MARKERS).
Usage: python -I tools/worklog.py [--transcripts DIR] [--quiet]

Times:
- Claude's time: per session, the gaps between consecutive transcript entries, each gap up to IDLE_GAP_S.
- Kailil's time: his sittings, messages less than SITTING_GAP_S apart, each from LEAD_IN_S before its first
  message to its last one.
Redacted before anything is written: e-mail and IP addresses, user profile paths, and every line of
../worklog-redact.txt (beside the checkout; private terms such as network names, never committed)."""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "worklog")
DATA = os.path.join(OUT, "data")
REDACT_FILE = os.environ.get("BARDROID_WORKLOG_REDACT", os.path.join(os.path.dirname(ROOT), "worklog-redact.txt"))
MARKERS = ("barandroid", "bar-droid", "bardroid")
MIN_MARKERS = 100
IDLE_GAP_S = 10 * 60
SITTING_GAP_S = 30 * 60
LEAD_IN_S = 5 * 60
MESSAGE_CHARS = 4000
ANSWER_CHARS = 700


def parse_time(ts):
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))


def local(ts):
    return parse_time(ts).astimezone()


def load_redactions():
    terms = []
    if os.path.exists(REDACT_FILE):
        with open(REDACT_FILE, encoding="utf-8") as fh:
            terms = [t.strip() for t in fh if t.strip() and not t.startswith("#")]
    return sorted(terms, key=len, reverse=True)


REDACT = load_redactions()
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
PROFILE = re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"'`]+", re.I)
PASTE = re.compile(r"<pasted_content[^>]*>(.*?)</pasted_content[^>]*>", re.S)
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
COMMENT = re.compile(r"=== BEGIN ARTIFACT COMMENT (\w+) ===\n(.*?)\n=== END ARTIFACT COMMENT \1 ===", re.S)


def clean(text):
    comment = COMMENT.search(text) if text.startswith("[Artifact comment") else None
    if comment:  # a comment on one of Claude's pages, inside the app's wrapper: the comment alone
        text = "(comment on a page Claude made) " + "\n".join(
            line[2:] if line.startswith("> ") else line.lstrip(">") for line in comment.group(2).splitlines())
    text = PASTE.sub(lambda m: "[pasted text, %d characters]" % len(m.group(1)), text)
    text = REMINDER.sub("", text)
    text = EMAIL.sub("[e-mail]", text)
    text = IPV4.sub("[address]", text)
    text = PROFILE.sub("%USERPROFILE%", text)
    for term in REDACT:
        text = re.sub(re.escape(term), "[private]", text, flags=re.I)
    return text.strip()


def blocks_text(content):
    """(text, images) of a message's content: a string or a list of blocks."""
    if isinstance(content, str):
        return content, 0
    parts, images = [], 0
    for b in content or []:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "text":
            parts.append(b.get("text", ""))
        elif b.get("type") == "image":
            images += 1
    return "\n".join(parts), images


def is_human(entry):
    origin = entry.get("origin")
    return isinstance(origin, dict) and origin.get("kind") == "human"


def scan(path):
    """One transcript: (title, markers, entries) without parsing JSON unless the project is named often enough."""
    markers = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            # Claude's own entries only: the memory index every session is given names the project too.
            if '"type":"assistant"' in line:
                low = line.lower()
                markers += sum(low.count(m) for m in MARKERS)
    if markers < MIN_MARKERS:
        return None, markers, []
    title, entries = None, []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = list(fh)
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") in ("custom-title", "agent-name"):
            title = e.get("customTitle") or e.get("agentName") or title
        elif e.get("timestamp") and e.get("type") in ("user", "assistant", "attachment", "system"):
            entries.append(e)
    return title, markers, entries


def session_records(sid, entries, seen):
    """Kailil's messages (each with Claude's last answer before the next one), Claude's minutes, tool calls."""
    times, messages, tools, interrupts = [], [], 0, 0
    current = None
    for e in entries:
        uid = e.get("uuid")
        if uid in seen:
            continue
        seen.add(uid)
        times.append(parse_time(e["timestamp"]))
        t = e.get("type")
        if t == "assistant":
            text, _ = blocks_text(e.get("message", {}).get("content"))
            tools += sum(1 for b in e.get("message", {}).get("content") or []
                         if isinstance(b, dict) and b.get("type") == "tool_use")
            if text.strip() and current is not None:
                current["answer"] = text
            continue
        content = None
        if t == "user" and is_human(e):
            content = e.get("message", {}).get("content")
        elif t == "attachment":
            a = e.get("attachment") or {}
            if a.get("type") == "queued_command" and is_human(a):
                content = a.get("prompt")
        elif t == "user":
            text, _ = blocks_text(e.get("message", {}).get("content"))
            if text.startswith("[Request interrupted by user"):
                interrupts += 1
        if content is None:
            continue
        text, images = blocks_text(content)
        if not text.strip() and not images:
            continue
        current = {"id": uid, "session": sid, "time": e["timestamp"], "text": text, "images": images, "answer": ""}
        messages.append(current)
    times.sort()
    claude_s = sum(min((b - a).total_seconds(), IDLE_GAP_S) for a, b in zip(times, times[1:]))
    return messages, claude_s, tools, interrupts, times


def load_existing():
    sessions, messages = {}, {}
    try:
        with open(os.path.join(DATA, "sessions.json"), encoding="utf-8") as fh:
            sessions = json.load(fh)
    except (OSError, ValueError):
        pass
    try:
        with open(os.path.join(DATA, "messages.jsonl"), encoding="utf-8") as fh:
            for line in fh:
                m = json.loads(line)
                m["text"], m["answer"] = clean(m["text"]), clean(m["answer"])  # today's redactions on old records
                messages[m["id"]] = m
    except (OSError, ValueError):
        pass
    return sessions, messages


def commits_by_day():
    git = shutil.which("git")
    if not git:
        return {}
    try:
        out = subprocess.run([git, "-C", ROOT, "log", "--format=%aI"], capture_output=True, text=True,
                             check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return {}
    days = defaultdict(int)
    for line in out.split():
        days[datetime.datetime.fromisoformat(line).astimezone().date().isoformat()] += 1
    return days


def sittings(times):
    """[(start, end)] of Kailil's sittings from his message times."""
    out = []
    for t in sorted(times):
        if out and (t - out[-1][1]).total_seconds() <= SITTING_GAP_S:
            out[-1][1] = t
        else:
            out.append([t - datetime.timedelta(seconds=LEAD_IN_S), t])
    return out


def hours(seconds):
    return "%.1f" % (seconds / 3600.0)


def quote(text, limit):
    text = text.strip()
    if len(text) > limit:
        text = text[:limit].rstrip() + " … (%d more characters)" % (len(text) - limit)
    return "\n".join("> " + line if line.strip() else ">" for line in text.splitlines())


def write_markdown(sessions, messages):
    by_day = defaultdict(list)
    for m in messages:
        by_day[local(m["time"]).date().isoformat()].append(m)
    kailil_times = [parse_time(m["time"]) for m in messages]
    sit = sittings(kailil_times)
    kailil_by_day = defaultdict(float)
    for a, b in sit:
        a, b = a.astimezone(), b.astimezone()
        while a.date() < b.date():  # a sitting past midnight counts on both days
            midnight = (a + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
            kailil_by_day[a.date().isoformat()] += (midnight - a).total_seconds()
            a = midnight
        kailil_by_day[b.date().isoformat()] += (b - a).total_seconds()
    claude_by_day = defaultdict(float)
    for s in sessions.values():
        for day, sec in s.get("claude_by_day", {}).items():
            claude_by_day[day] += sec
    commits = commits_by_day()
    days = sorted(set(by_day) | set(claude_by_day))
    words = sum(len(m["text"].split()) for m in messages)
    images = sum(m["images"] for m in messages)
    tz = datetime.datetime.now().astimezone().strftime("UTC%z")
    tz = tz[:-2] + ":" + tz[-2:]

    os.makedirs(OUT, exist_ok=True)
    for day in days:
        lines = ["# Work log, %s" % day, "",
                 "Kailil's messages to Claude and Claude's answer to each (its last words before his next message),"
                 " local time (%s). Generated by `tools/worklog.py`; [all days](../WORKLOG.md)." % tz, ""]
        for m in sorted(by_day.get(day, []), key=lambda m: m["time"]):
            title = sessions.get(m["session"], {}).get("title") or m["session"][:8]
            pics = " · %d screenshot%s" % (m["images"], "s" if m["images"] > 1 else "") if m["images"] else ""
            lines += ["### %s · %s%s" % (local(m["time"]).strftime("%H:%M"), title, pics), "",
                      "**Kailil:**", "", quote(m["text"], MESSAGE_CHARS) or "> (screenshots only)", ""]
            if m.get("answer"):
                lines += ["**Claude:**", "", quote(m["answer"], ANSWER_CHARS), ""]
        with open(os.path.join(OUT, day + ".md"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    total_claude = sum(claude_by_day.values())
    total_kailil = sum(kailil_by_day.values())
    lines = [
        "# Work log",
        "",
        "The effort behind BAR Droid: every message Kailil sent Claude (Claude Code) while building it, Claude's"
        " answers, and the time each side spent. Generated from Claude Code's session transcripts by"
        " `python -I tools/worklog.py` (rerun after every work session; the data in `docs/worklog/data/` outlives"
        " the transcripts). Local time, %s." % tz,
        "",
        "## Totals",
        "",
        "| | |",
        "|---|---|",
        "| Days | %d (%s to %s) |" % (len(days), days[0] if days else "-", days[-1] if days else "-"),
        "| Claude Code sessions | %d |" % len(sessions),
        "| Kailil's messages | %d (%d words, %d screenshots) |" % (len(messages), words, images),
        "| Kailil's time | %s h in %d sittings |" % (hours(total_kailil), len(sit)),
        "| Claude's time | %s h |" % hours(total_claude),
        "| Claude's tool calls | %d |" % sum(s.get("tool_calls", 0) for s in sessions.values()),
        "| Kailil stopped Claude mid-answer | %d times |" % sum(s.get("interrupts", 0) for s in sessions.values()),
        "| Commits | %d |" % sum(commits.values()),
        "",
        "Kailil's time: his sittings, messages less than %d minutes apart, each from %d minutes before its first"
        " message (reading, testing on the phone, writing) to its last. Claude's time: the gaps between its"
        " transcript entries, each up to %d minutes; sessions that ran side by side add up."
        % (SITTING_GAP_S // 60, LEAD_IN_S // 60, IDLE_GAP_S // 60),
        "",
        "## By day",
        "",
        "| Day | Kailil's messages | Kailil h | Claude h | Commits |",
        "|---|---:|---:|---:|---:|",
    ]
    for day in days:
        lines.append("| [%s](worklog/%s.md) | %d | %s | %s | %d |" % (
            day, day, len(by_day.get(day, [])), hours(kailil_by_day.get(day, 0)), hours(claude_by_day.get(day, 0)),
            commits.get(day, 0)))
    lines += ["", "## Sessions", "", "| Session | From | To | Kailil's messages | Claude h |",
              "|---|---|---|---:|---:|"]
    for sid, s in sorted(sessions.items(), key=lambda kv: kv[1]["first"]):
        lines.append("| %s | %s | %s | %d | %s |" % (
            s.get("title") or sid[:8], local(s["first"]).strftime("%Y-%m-%d %H:%M"),
            local(s["last"]).strftime("%Y-%m-%d %H:%M"), s.get("messages", 0), hours(s.get("claude_s", 0))))
    with open(os.path.join(ROOT, "docs", "WORKLOG.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return len(messages), total_kailil, total_claude, len(days)


def transcripts_dir():
    """Claude Code's projects folder: CLAUDE_CONFIG_DIR, else the real profile (scripts/env.bat points HOME and
    USERPROFILE at the toolchain; HOMEDRIVE/HOMEPATH stay the user's)."""
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        return os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "projects")
    homes = [os.environ.get("HOMEDRIVE", "") + os.environ.get("HOMEPATH", ""), os.path.expanduser("~")]
    for home in homes:
        if home and os.path.isdir(os.path.join(home, ".claude", "projects")):
            return os.path.join(home, ".claude", "projects")
    return os.path.join(homes[-1], ".claude", "projects")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--transcripts", default=transcripts_dir())
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    sessions, messages = load_existing()
    files = glob.glob(os.path.join(args.transcripts, "*", "*.jsonl"))
    found = []
    for path in files:
        title, markers, entries = scan(path)
        if entries:
            found.append((entries[0]["timestamp"], os.path.basename(path)[:-6], title, entries))
    seen = set()
    for first, sid, title, entries in sorted(found):
        msgs, claude_s, tools, interrupts, times = session_records(sid, entries, seen)
        by_day = defaultdict(float)
        for a, b in zip(times, times[1:]):
            by_day[b.astimezone().date().isoformat()] += min((b - a).total_seconds(), IDLE_GAP_S)
        for m in msgs:
            m["text"], m["answer"] = clean(m["text"]), clean(m["answer"])
            messages[m["id"]] = m
        if not times:
            continue
        sessions[sid] = {"title": title, "first": times[0].isoformat(), "last": times[-1].isoformat(),
                         "messages": len(msgs), "claude_s": round(claude_s), "tool_calls": tools,
                         "interrupts": interrupts, "claude_by_day": {d: round(s) for d, s in by_day.items()}}
    # The same message twice within an hour (sent again in a new session, a queued message that also became a
    # turn): keep the first.
    unique, last_sent = [], {}
    for m in sorted(messages.values(), key=lambda m: m["time"]):
        t = parse_time(m["time"])
        before = last_sent.get(m["text"])
        last_sent[m["text"]] = t
        if before is not None and (t - before).total_seconds() < 3600:
            continue
        unique.append(m)
    for sid, s in sessions.items():
        s["messages"] = sum(1 for m in unique if m["session"] == sid)

    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "sessions.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(sessions, fh, indent=1, sort_keys=True)
        fh.write("\n")
    with open(os.path.join(DATA, "messages.jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        for m in unique:
            fh.write(json.dumps(m, ensure_ascii=False, sort_keys=True) + "\n")
    n, kailil_s, claude_s, days = write_markdown(sessions, unique)
    if not args.quiet:
        print("worklog: %d sessions, %d messages, %d days, Kailil %s h, Claude %s h -> docs/WORKLOG.md"
              % (len(sessions), n, days, hours(kailil_s), hours(claude_s)))
        if not REDACT:
            print("worklog: no %s (private terms to redact)" % REDACT_FILE, file=sys.stderr)


if __name__ == "__main__":
    main()
