"""The user guide (docs/GUIDE.md) as one web page: build/guide-site/index.html with its pictures in img/.

A small Markdown reader of its own (no libraries): headings (#..####, each with an id for the contents), paragraphs,
lists (- and 1., nested by two spaces), tables, pictures on their own line (![caption](guide/img/x.jpg) as a figure),
> notes (a "> **Tip:**" line is a tip box), --- rules, ``` code, and inline **bold**, *italic*, `code` and [links](url).
Links to other .md files of the repository go to its GitHub page. The page follows the Artifact page contract (no
<html> of its own, its title and style first, colours as tokens for both themes).

    python -I tools/guide-html.py [--repo-url https://github.com/UnderarmCape/bar-droid/blob/main]
"""
import html
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "GUIDE.md")
OUT = os.path.join(ROOT, "build", "guide-site")
REPO_URL = "https://github.com/UnderarmCape/bar-droid/blob/main"
if "--repo-url" in sys.argv:
    REPO_URL = sys.argv[sys.argv.index("--repo-url") + 1].rstrip("/")

slugs = {}


def slug(text):
    s = re.sub(r"<[^>]+>", "", text)
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-") or "section"
    n = slugs.get(s, 0)
    slugs[s] = n + 1
    return s if n == 0 else "%s-%d" % (s, n + 1)


def link_target(url):
    if re.match(r"^[a-z]+:", url) or url.startswith("#"):
        return url
    if url.endswith(".md") or ".md#" in url:  # (another document of the repository: its GitHub page)
        path = os.path.normpath(os.path.join("docs", url)).replace("\\", "/")
        return "%s/%s" % (REPO_URL, path)
    return url


def inline(text):
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", lambda m: "<code>%s</code>" % m.group(1), out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"<em>\1</em>", out)

    def a(m):
        href = link_target(html.unescape(m.group(2)))
        ext = ' target="_blank" rel="noopener"' if href.startswith("http") else ""
        return '<a href="%s"%s>%s</a>' % (html.escape(href), ext, m.group(1))

    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", a, out)
    return out


def image_src(src):
    # (the guide's own pictures: docs/guide/img/x.jpg, written as guide/img/x.jpg from docs/GUIDE.md)
    return "img/" + os.path.basename(src)


def convert(md):
    lines = md.replace("\r", "").split("\n")
    body, toc = [], []
    i = 0
    para = []

    def flush():
        if para:
            body.append("<p>%s</p>" % inline(" ".join(para)))
            para.clear()

    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if not s:
            flush()
            i += 1
            continue
        if s.startswith("```"):
            flush()
            code = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            body.append('<div class="scroll"><pre><code>%s</code></pre></div>' % html.escape("\n".join(code)))
            continue
        m = re.match(r"^(#{1,4})\s+(.*)$", s)
        if m:
            flush()
            level, text = len(m.group(1)), m.group(2).strip()
            if level == 1:
                body.append('<h1 class="doc-title">%s</h1>' % inline(text))
            else:
                sid = slug(text)
                if level <= 3:
                    toc.append((level, sid, inline(text)))
                body.append('<h%d id="%s">%s<a class="anchor" href="#%s" aria-label="Link to this section">#</a></h%d>'
                            % (level, sid, inline(text), sid, level))
            i += 1
            continue
        if re.match(r"^-{3,}$", s):
            flush()
            body.append("<hr>")
            i += 1
            continue
        m = re.match(r"^!\[([^\]]*)\]\(([^)\s]+)\)$", s)
        if m:
            flush()
            cap = m.group(1)
            body.append('<figure><img src="%s" alt="%s" loading="lazy"><figcaption>%s</figcaption></figure>'
                        % (html.escape(image_src(m.group(2))), html.escape(cap), inline(cap)))
            i += 1
            continue
        if s.startswith(">"):
            flush()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            text = " ".join(quote)
            kind = "tip" if re.match(r"^\*\*(Tip|Pro tip)", text) else "warn" if re.match(r"^\*\*(Warning|Careful|Note)", text) else "note"
            body.append('<aside class="callout %s"><p>%s</p></aside>' % (kind, inline(text)))
            continue
        if s.startswith("|") and i + 1 < len(lines) and re.match(r"^\|?\s*:?-{2,}", lines[i + 1].strip()):
            flush()
            head = [c.strip() for c in s.strip("|").split("|")]
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            t = ['<div class="scroll"><table><thead><tr>']
            t += ["<th>%s</th>" % inline(h) for h in head]
            t.append("</tr></thead><tbody>")
            for r in rows:
                t.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            body.append("".join(t))
            continue
        if re.match(r"^(\s*)([-*]|\d+\.)\s+", line):
            flush()
            stack = []  # (indent, tag)
            items = []
            while i < len(lines):
                l = lines[i]
                m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", l)
                if not m:
                    if l.strip() and stack and len(l) - len(l.lstrip()) > stack[-1][0]:  # (a list item's next line)
                        items[-1] += " " + inline(l.strip())
                        i += 1
                        continue
                    break
                ind = len(m.group(1))
                tag = "ol" if m.group(2)[0].isdigit() else "ul"
                if not stack or ind > stack[-1][0]:
                    stack.append((ind, tag))
                    items.append("<%s>" % tag)
                else:
                    while stack and ind < stack[-1][0]:
                        items.append("</li></%s>" % stack.pop()[1])
                    items.append("</li>")
                items.append("<li>" + inline(m.group(3)))
                i += 1
            while stack:
                items.append("</li></%s>" % stack.pop()[1])
            # (an item opened right after another's text: "<li>a<ul>" is the nested list inside it)
            body.append("".join(items).replace("<ul></li>", "<ul>").replace("<ol></li>", "<ol>"))
            continue
        para.append(s)
        i += 1
    flush()
    return "\n".join(body), toc


STYLE = r"""
/* Layout: a fixed contents column beside one reading column (stacked, contents folded, on a phone) */
:root {
  --bg: #f3f4f2; --surface: #ffffff; --fg: #1b1f22; --muted: #5b6468; --line: #d9ddd8;
  --accent: #a26a00; --accent-soft: #fff2d1; --code: #eceeea; --tip: #e6f2ea; --tip-line: #2f7d4f;
  --warn: #fbeee4; --warn-line: #b65a1f;
  --head: "Rajdhani", "Barlow Semi Condensed", "Segoe UI", system-ui, sans-serif;
  --body: "Inter", "Segoe UI", system-ui, -apple-system, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, Consolas, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #121518; --surface: #1a1e22; --fg: #e4e7e4; --muted: #9aa3a6; --line: #2c3337;
  --accent: #f2b542; --accent-soft: #2e2512; --code: #23292d; --tip: #15261c; --tip-line: #55b47c;
  --warn: #2b1d14; --warn-line: #e08a4c; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #121518; --surface: #1a1e22; --fg: #e4e7e4; --muted: #9aa3a6; --line: #2c3337;
  --accent: #f2b542; --accent-soft: #2e2512; --code: #23292d; --tip: #15261c; --tip-line: #55b47c;
  --warn: #2b1d14; --warn-line: #e08a4c; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font: 16px/1.65 var(--body); }
.wrap { display: grid; grid-template-columns: 17rem minmax(0, 1fr); gap: 2.5rem; max-width: 76rem; margin: 0 auto;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 1.5rem 4rem; }
nav.toc { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 1rem); align-self: start;
  max-height: calc(100vh - 2rem); overflow-y: auto; font-size: 0.9rem; }
nav.toc summary { font: 600 0.8rem/1 var(--head); letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted);
  cursor: pointer; padding: 0.4rem 0; }
nav.toc ol { list-style: none; margin: 0.4rem 0 0; padding: 0; }
nav.toc li.l3 { padding-left: 0.9rem; font-size: 0.85rem; }
nav.toc a { display: block; padding: 0.22rem 0.5rem; border-radius: 4px; color: var(--fg); text-decoration: none; }
nav.toc a:hover, nav.toc a:focus-visible { background: var(--accent-soft); color: var(--accent); outline: none; }
nav.toc li.l3 a { color: var(--muted); }
main { min-width: 0; max-width: 46rem; }
.doc-title { font: 700 2.6rem/1.1 var(--head); margin: 0.2rem 0 0.4rem; text-wrap: balance; }
h2, h3, h4 { font-family: var(--head); line-height: 1.2; text-wrap: balance; scroll-margin-top: 1rem; }
h2 { font-size: 1.9rem; font-weight: 700; margin: 3.2rem 0 0.8rem; padding-top: 1.2rem; border-top: 2px solid var(--line); }
h3 { font-size: 1.35rem; font-weight: 700; margin: 2rem 0 0.5rem; }
h4 { font-size: 1.05rem; font-weight: 700; margin: 1.5rem 0 0.3rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); }
.anchor { margin-left: 0.4rem; color: var(--line); text-decoration: none; font-weight: 400; }
h2:hover .anchor, h3:hover .anchor { color: var(--accent); }
p, li { max-width: 68ch; }
a { color: var(--accent); }
code { font: 0.88em var(--mono); background: var(--code); padding: 0.1em 0.35em; border-radius: 3px; }
pre { background: var(--code); padding: 0.9rem 1rem; border-radius: 6px; margin: 0; }
pre code { background: none; padding: 0; }
.scroll { overflow-x: auto; margin: 1rem 0; }
table { border-collapse: collapse; width: 100%; font-size: 0.93rem; font-variant-numeric: tabular-nums; }
th, td { text-align: left; vertical-align: top; padding: 0.5rem 0.7rem; border-bottom: 1px solid var(--line); }
th { font: 600 0.8rem/1.3 var(--head); letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted);
  border-bottom: 2px solid var(--line); }
td:first-child { font-weight: 600; white-space: nowrap; }
figure { margin: 1.4rem 0; }
figure img { display: block; max-width: min(100%, 26rem); height: auto; border-radius: 8px; border: 1px solid var(--line); }
figure img[src*="unfolded"], figure img[src*="sideways"], figure img[src*="wide"] { max-width: 100%; }
figcaption { font-size: 0.88rem; color: var(--muted); margin-top: 0.45rem; max-width: 60ch; }
.callout { margin: 1.2rem 0; padding: 0.7rem 1rem; border-left: 4px solid var(--accent); background: var(--accent-soft);
  border-radius: 0 6px 6px 0; }
.callout p { margin: 0; }
.callout.tip { border-color: var(--tip-line); background: var(--tip); }
.callout.warn { border-color: var(--warn-line); background: var(--warn); }
hr { border: 0; border-top: 1px solid var(--line); margin: 2rem 0; }
.kicker { font: 600 0.8rem/1 var(--head); letter-spacing: 0.12em; text-transform: uppercase; color: var(--accent); }
.lede { color: var(--muted); font-size: 1.05rem; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
@media (max-width: 860px) {
  .wrap { grid-template-columns: minmax(0, 1fr); gap: 0.5rem; }
  nav.toc { position: static; max-height: none; border: 1px solid var(--line); border-radius: 8px; padding: 0.3rem 0.8rem;
    background: var(--surface); }
  .doc-title { font-size: 2rem; }
}
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior: smooth; } }
"""


def main():
    with open(SRC, encoding="utf-8") as f:
        md = f.read()
    body, toc = convert(md)
    toc_html = "".join('<li class="l%d"><a href="#%s">%s</a></li>' % (lvl, sid, re.sub(r"<a [^>]*>|</a>", "", text))
                       for lvl, sid, text in toc)
    page = ("<title>BAR Droid Guide</title>\n"
            '<meta name="claude:viewport-fit-sides" content="cover">\n'
            '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
            '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600&family=JetBrains+Mono'
            '&family=Rajdhani:wght@600;700&display=swap">\n'
            "<style>%s</style>\n"
            '<div class="wrap">\n'
            '<nav class="toc" aria-label="Contents"><details open><summary>Contents</summary><ol>%s</ol></details></nav>\n'
            "<main>\n%s\n</main>\n</div>\n"
            "<script>\n"
            "// On a phone the contents start folded; on a wide screen they stay open beside the text\n"
            "(function () { var d = document.querySelector('nav.toc details');\n"
            "  if (d && window.matchMedia('(max-width: 860px)').matches) { d.open = false; }\n"
            "  document.querySelectorAll('nav.toc a').forEach(function (a) { a.addEventListener('click', function () {\n"
            "    if (window.matchMedia('(max-width: 860px)').matches) { d.open = false; } }); }); })();\n"
            "</script>\n") % (STYLE, toc_html, body)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, "img"))
    with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    used = set(re.findall(r'src="img/([^"]+)"', page))
    missing = []
    for name in sorted(used):
        src = os.path.join(ROOT, "docs", "guide", "img", name)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(OUT, "img", name))
        else:
            missing.append(name)
    print("guide-html: %s (%d KB), %d sections, %d pictures%s" % (
        os.path.join(OUT, "index.html"), len(page.encode("utf-8")) // 1024, len(toc), len(used),
        (", MISSING: " + ", ".join(missing)) if missing else ""))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
