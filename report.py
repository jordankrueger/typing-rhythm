#!/usr/bin/env python3
"""Typing Rhythm report (standard library only).

Reads ~/TypingRhythm/data/*.json, works out one row of numbers per day, compares
recent weeks with your own baseline, and writes daily.csv and report.html beside
this script.

    python3 ~/TypingRhythm/report.py
"""
import csv, glob, html, json, math, os, statistics, sys
from collections import defaultdict
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
HOLD_BIN, GAP_BIN = 5, 10
MIN_HOLDS_PER_DAY = 300          # days with less typing than this are skipped
BASELINE_DAYS = 56               # first 8 weeks of qualifying days form the baseline
RECENT_DAYS = 28                 # compared against the last 4 weeks

# measure: (label, unit, direction that would be a concern: +1 higher is worse, -1 lower is worse, 0 neutral)
MEASURES = {
    "hold_sd":       ("Hold-time variability", "ms", +1),
    "hold_median":   ("Typical hold time", "ms", +1),
    "hold_iqr":      ("Hold-time spread (middle half)", "ms", +1),
    "gap_median":    ("Typical gap between keys", "ms", +1),
    "speed_kpm":     ("Typing speed in bursts", "keys/min", -1),
    "backspace_pct": ("Backspace rate", "% of keys", +1),
    "pause_rate":    ("Pauses per 100 keys", "", 0),
}


def hist_quantile(hist, binw, q):
    total = sum(hist)
    if not total:
        return None
    target, run = q * total, 0
    for i, c in enumerate(hist):
        if run + c >= target and c:
            frac = (target - run) / c
            return (i + frac) * binw
        run += c
    return len(hist) * binw


def load_days():
    per_day = defaultdict(lambda: defaultdict(list))   # day -> keyboard_type -> buckets
    for path in sorted(glob.glob(os.path.join(DATA, "*.json"))):
        try:
            d = json.load(open(path))
        except (OSError, ValueError):
            continue
        for b in d.get("buckets", []):
            per_day[d["day"]][str(b.get("keyboard_type", 0))].append(b)
    return per_day


def day_row(buckets):
    holds = sum(b["holds"] for b in buckets)
    keys = sum(b["keys"] for b in buckets)
    if holds == 0:
        return None
    # combine running means / sums of squares across buckets
    n, mean, m2 = 0, 0.0, 0.0
    for b in buckets:
        nb = b["holds"]
        if not nb:
            continue
        delta = b["hold_mean"] - mean
        tot = n + nb
        mean += delta * nb / tot
        m2 += b["hold_m2"] + delta * delta * n * nb / tot
        n = tot
    hh = [sum(x) for x in zip(*[b["hold_hist"] for b in buckets])]
    gh = [sum(x) for x in zip(*[b["gap_hist"] for b in buckets])]
    bk, bms = sum(b["burst_keys"] for b in buckets), sum(b["burst_ms"] for b in buckets)
    q25, q75 = hist_quantile(hh, HOLD_BIN, .25), hist_quantile(hh, HOLD_BIN, .75)
    return {
        "keys": keys, "holds": holds,
        "hold_sd": math.sqrt(m2 / (n - 1)) if n > 1 else None,
        "hold_median": hist_quantile(hh, HOLD_BIN, .5),
        "hold_iqr": (q75 - q25) if q25 is not None else None,
        "gap_median": hist_quantile(gh, GAP_BIN, .5),
        "speed_kpm": bk / (bms / 60000) if bms > 0 else None,
        "backspace_pct": 100 * sum(b["backspace"] for b in buckets) / keys if keys else None,
        "pause_rate": 100 * sum(b["pauses"] for b in buckets) / keys if keys else None,
    }


def main():
    per_day = load_days()
    if not per_day:
        print("No data yet. Type normally for a few days, then run this again.")
        return
    totals = defaultdict(int)
    for kbs in per_day.values():
        for kb, bs in kbs.items():
            totals[kb] += sum(b["keys"] for b in bs)
    main_kb = max(totals, key=totals.get)

    rows = []
    for day in sorted(per_day):
        r = day_row(per_day[day].get(main_kb, []))
        if r and r["holds"] >= MIN_HOLDS_PER_DAY:
            r["day"] = day
            rows.append(r)

    with open(os.path.join(HERE, "daily.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["day", "keys", "holds"] + list(MEASURES))
        w.writeheader()
        for r in rows:
            w.writerow({k: (round(v, 2) if isinstance(v, float) else v) for k, v in r.items() if k in w.fieldnames})

    lines = []
    lines.append(f"Main keyboard (type {main_kb}): {len(rows)} days with enough typing "
                 f"(of {len(per_day)} days logged). Other keyboards are left out so a "
                 "keyboard switch doesn't look like a change in you.")
    comparison = []
    if len(rows) < BASELINE_DAYS + 14:
        need = BASELINE_DAYS + 14 - len(rows)
        lines.append(f"Still building your baseline: about {need} more typing days before "
                     "recent weeks can be compared with it.")
    else:
        base = rows[:BASELINE_DAYS]
        recent = rows[max(BASELINE_DAYS, len(rows) - RECENT_DAYS):]  # never overlaps the baseline
        for k, (label, unit, sign) in MEASURES.items():
            bv = [r[k] for r in base if r[k] is not None]
            rv = [r[k] for r in recent if r[k] is not None]
            if len(bv) < 20 or len(rv) < 7:
                continue
            mu, sd = statistics.mean(bv), statistics.pstdev(bv)
            z = (statistics.mean(rv) - mu) / sd if sd else 0.0
            concern = sign * z if sign else 0.0
            comparison.append((label, unit, mu, statistics.mean(rv), z, concern))
        lines.append(f"Baseline: {base[0]['day']} to {base[-1]['day']}. "
                     f"Recent: {recent[0]['day']} to {recent[-1]['day']}.")
        for label, unit, mu, rmu, z, concern in comparison:
            tag = "worth a look" if concern >= 2 else "watch" if concern >= 1 else "normal"
            lines.append(f"  {label:<32} baseline {mu:7.1f}  recent {rmu:7.1f}  ({z:+.2f})  {tag}")
        lines.append("Numbers in brackets show how far recent weeks sit from your baseline, in units "
                     "of your normal day-to-day swing. One odd stretch means little; sleep, caffeine, "
                     "illness, medication and a new keyboard all move these.")
    print("\n".join(lines))
    write_html(rows, lines, comparison)
    print("\nWrote daily.csv and report.html in", HERE)


def spark(rows, key, w=640, h=120):
    pts = [(i, r[key]) for i, r in enumerate(rows) if r[key] is not None]
    if len(pts) < 2:
        return "<p class='muted'>Not enough days yet.</p>"
    vals = [v for _, v in pts]
    lo, hi = min(vals), max(vals)
    if hi == lo:
        hi = lo + 1
    n = len(rows) - 1 or 1
    X = lambda i: 8 + i / n * (w - 16)
    Y = lambda v: 8 + (1 - (v - lo) / (hi - lo)) * (h - 16)
    dots = "".join(f"<circle cx='{X(i):.1f}' cy='{Y(v):.1f}' r='2.2'><title>{html.escape(rows[i]['day'])}: {v:.1f}</title></circle>" for i, v in pts)
    # 7-day rolling median
    roll = []
    for j in range(len(pts)):
        win = [v for _, v in pts[max(0, j - 6): j + 1]]
        roll.append((pts[j][0], statistics.median(win)))
    path = "M" + "L".join(f"{X(i):.1f},{Y(v):.1f}" for i, v in roll)
    return (f"<svg viewBox='0 0 {w} {h}' role='img'><path d='{path}' class='line'/>{dots}"
            f"<text x='{w-4}' y='14' text-anchor='end'>{hi:.0f}</text>"
            f"<text x='{w-4}' y='{h-4}' text-anchor='end'>{lo:.0f}</text></svg>")


def write_html(rows, lines, comparison):
    blocks = "".join(f"<section><h2>{html.escape(l)}{(' (' + u + ')') if u else ''}</h2>{spark(rows, k)}</section>"
                     for k, (l, u, _) in MEASURES.items())
    summary = "".join(f"<p>{html.escape(l)}</p>" for l in lines if not l.startswith("  "))
    table = ""
    if comparison:
        trs = "".join(
            f"<tr><td>{html.escape(l)}</td><td>{mu:.1f}</td><td>{rmu:.1f}</td>"
            f"<td class='{'flag' if c >= 2 else 'watch' if c >= 1 else 'ok'}'>{z:+.2f}</td></tr>"
            for l, u, mu, rmu, z, c in comparison)
        table = ("<table><tr><th>Measure</th><th>Baseline</th><th>Recent 4 weeks</th><th>Change</th></tr>"
                 f"{trs}</table>")
    page = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Typing Rhythm</title>
<style>
:root{{--bg:#f7f7f5;--ink:#1d232b;--muted:#646d78;--line:#1f5f8b;--dot:#1f5f8b55;--ok:#2e7d4f;--watch:#a26a00;--flag:#b3261e}}
@media (prefers-color-scheme: dark){{:root{{--bg:#12161b;--ink:#e5e9ee;--muted:#9aa5b1;--line:#6fb2e0;--dot:#6fb2e055;--ok:#5cc28a;--watch:#e0a94a;--flag:#ef7b72;color-scheme:dark}}}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 -apple-system,system-ui,sans-serif}}
main{{max-width:720px;margin:0 auto;padding:28px 18px;display:flex;flex-direction:column;gap:18px}}
h1{{margin:0;font-size:1.6rem}} h2{{font-size:1rem;margin:0 0 4px}} p{{margin:0}} .muted{{color:var(--muted)}}
svg{{width:100%;height:auto}} svg circle{{fill:var(--dot)}} svg .line{{fill:none;stroke:var(--line);stroke-width:2}}
svg text{{fill:var(--muted);font-size:11px}}
table{{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}} td,th{{text-align:left;padding:6px 8px;border-bottom:1px solid #8883}}
.ok{{color:var(--ok)}} .watch{{color:var(--watch)}} .flag{{color:var(--flag)}}
</style></head><body><main>
<h1>Typing Rhythm</h1>{summary}{table}
<p class="muted">Dots are single days; the line is a 7-day rolling median. Built from key timing only. No keys or text were recorded.</p>
{blocks}
</main></body></html>"""
    with open(os.path.join(HERE, "report.html"), "w") as f:
        f.write(page)


if __name__ == "__main__":
    main()
