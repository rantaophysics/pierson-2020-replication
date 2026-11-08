"""05_slide_figures.py
Figures for the Nov 11 slides, in the style of the lab plotting notebook
(Scientific_Plotting_DEMO): style set once in rcParams, exact sizes in mm with
axes placed by add_axes (no bbox_inches="tight"), inward ticks, no top/right
spines, saved as PDF + SVG + PNG. Dark version: white ink on a black page.

Inputs (from the R scripts): data/derived/mj_panel.csv,
results/tables/did_event_study.csv, did_table1_replication.csv,
did_robustness.csv, did_placebo_estimates.csv, vod_texas_fig2.csv,
vod_coefficients.csv
Output: results/figures/slides/*.{pdf,svg,png}

Run from the project root:  python3 code/05_slide_figures.py
"""
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# ---------------------------------------------------------------------------
# 1. Style, set once
# ---------------------------------------------------------------------------
INK, BG = "#FFFFFF", "#000000"
MUTED = "#9A9A9A"
plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Liberation Sans", "Helvetica", "DejaVu Sans"],
    "font.size": 9, "axes.labelsize": 10, "axes.titlesize": 10,
    "mathtext.fontset": "custom", "mathtext.rm": "sans", "mathtext.it": "sans:italic",
    "mathtext.bf": "sans:bold", "mathtext.cal": "sans", "mathtext.sf": "sans",
    "pdf.fonttype": 42, "svg.fonttype": "none",
    "axes.linewidth": 1.0,
    "xtick.direction": "in", "ytick.direction": "in",
    "xtick.major.size": 2.5, "ytick.major.size": 2.5,
    # dark theme
    "figure.facecolor": BG, "axes.facecolor": BG, "savefig.facecolor": BG,
    "text.color": INK, "axes.labelcolor": INK, "axes.edgecolor": INK,
    "xtick.color": INK, "ytick.color": INK,
    "axes.spines.top": False, "axes.spines.right": False,
    "legend.frameon": False,
})

# One colour per race, chosen to read on black; green/magenta from the notebook
# mark "ours" vs "paper".
RACE = {"white": "#5FA8E8", "black": "#F2C14E", "hispanic": "#E46AA7"}
RACE_LABEL = {"white": "White drivers", "black": "Black drivers", "hispanic": "Hispanic drivers"}
OURS, PAPER = "#66BB6A", "#C54E88"

ROOT = Path(".")
TAB = ROOT / "results/tables"
OUT = ROOT / "results/figures/slides"
OUT.mkdir(parents=True, exist_ok=True)


def panel_figure(fig_mm, margin_mm):
    """Figure of an exact size in mm with one axes placed by hand (notebook sec. 4)."""
    FW, FH = fig_mm
    ML, MR, MB, MT = margin_mm
    fig = plt.figure(figsize=(FW / 25.4, FH / 25.4))
    ax = fig.add_axes([ML / FW, MB / FH, (FW - ML - MR) / FW, (FH - MB - MT) / FH])
    return fig, ax


def grid_figure(fig_mm, margin_mm, nrow, ncol, gap_mm=(8, 9)):
    """Exact-size grid of axes, all placed with add_axes."""
    FW, FH = fig_mm
    ML, MR, MB, MT = margin_mm
    GX, GY = gap_mm
    pw = (FW - ML - MR - GX * (ncol - 1)) / ncol
    ph = (FH - MB - MT - GY * (nrow - 1)) / nrow
    fig = plt.figure(figsize=(FW / 25.4, FH / 25.4))
    axes = []
    for r in range(nrow):
        for c in range(ncol):
            x = ML + c * (pw + GX)
            y = FH - MT - (r + 1) * ph - r * GY
            axes.append(fig.add_axes([x / FW, y / FH, pw / FW, ph / FH]))
    return fig, axes


def save(fig, stem):
    for ext in ("pdf", "svg", "png"):
        fig.savefig(OUT / f"{stem}.{ext}", dpi=300)   # no bbox_inches: keep the exact size
    plt.close(fig)
    print("wrote", stem)


def tidy(ax):
    ax.tick_params(length=2.5, width=1, direction="in")


# ---------------------------------------------------------------------------
# 2. Data
# ---------------------------------------------------------------------------
mj = pd.read_csv(ROOT / "data/derived/mj_panel.csv", parse_dates=["date"])
mj["quarter"] = mj["date"].dt.to_period("Q")
q = (mj.groupby(["state", "subject_race", "quarter"], as_index=False)
       .agg(n_searches=("n_searches", "sum"), n_stops=("n_stops", "sum")))
q["rate"] = 100 * q.n_searches / q.n_stops
q["t"] = q["quarter"].dt.start_time + pd.Timedelta(days=45)
q = q[q["quarter"] != pd.Period("2012Q4")]          # legalization quarter mixes pre and post
LEGAL = pd.Timestamp("2012-12-09")

STATE_NAME = {"CO": "Colorado", "WA": "Washington", "AZ": "Arizona", "CA": "California",
              "FL": "Florida", "MA": "Massachusetts", "MT": "Montana", "NC": "North Carolina",
              "OH": "Ohio", "RI": "Rhode Island", "SC": "South Carolina", "TX": "Texas",
              "VT": "Vermont", "WI": "Wisconsin"}


def rate_panel(ax, st, show_ylabel=True, lw=1.4):
    for race in ["white", "black", "hispanic"]:
        d = q[(q.state == st) & (q.subject_race == race)].sort_values("t")
        pre, post = d[d.t < LEGAL], d[d.t >= LEGAL]
        for part in (pre, post):                    # break the line at legalization
            ax.plot(part.t, part.rate, color=RACE[race], lw=lw, solid_capstyle="round")
    ax.axvline(LEGAL, color=MUTED, lw=0.9, ls=(0, (3, 2)))
    ax.set_ylim(bottom=0)
    ax.set_title(STATE_NAME[st], loc="left", fontsize=10, pad=4)
    ax.xaxis.set_major_locator(plt.matplotlib.dates.YearLocator(1))
    ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter("%Y"))
    if show_ylabel:
        ax.set_ylabel("Search rate (%)")
    tidy(ax)


# ---------------------------------------------------------------------------
# 3. Figures
# ---------------------------------------------------------------------------
# (a) Treated states: search rates by race
fig, axes = grid_figure((170, 80), (14, 4, 10, 13), 1, 2, gap_mm=(14, 0))
for ax, st in zip(axes, ["CO", "WA"]):
    rate_panel(ax, st, show_ylabel=(st == "CO"))
axes[0].annotate("Legalization\nDec 2012", xy=(LEGAL, axes[0].get_ylim()[1] * 0.97),
                 xytext=(5, 0), textcoords="offset points", fontsize=8, color=MUTED,
                 va="top")
handles = [plt.Line2D([], [], color=RACE[r], lw=2) for r in RACE]
fig.legend(handles, [RACE_LABEL[r] for r in RACE], loc="upper center", ncol=3,
           bbox_to_anchor=(0.5, 1.0), fontsize=9, handlelength=1.6)
save(fig, "fig_did_treated")

# (b) Control states, 12 small panels (backup slide)
controls = ["AZ", "CA", "FL", "MA", "MT", "NC", "OH", "RI", "SC", "TX", "VT", "WI"]
fig, axes = grid_figure((240, 120), (14, 4, 9, 12), 3, 4, gap_mm=(9, 9))
for i, (ax, st) in enumerate(zip(axes, controls)):
    rate_panel(ax, st, show_ylabel=(i % 4 == 0), lw=1.0)
    ax.tick_params(labelsize=7)
    ax.set_title(STATE_NAME[st], loc="left", fontsize=8.5, pad=3)
    if i < 8:
        ax.set_xticklabels([])
    ax.set_ylabel("Search rate (%)" if i == 4 else "")
fig.legend(handles, [RACE_LABEL[r] for r in RACE], loc="upper center", ncol=3,
           bbox_to_anchor=(0.5, 1.0), fontsize=9, handlelength=1.6)
save(fig, "fig_did_controls")

# (c) Table 1: paper vs ours, coefficient plot
t1 = pd.read_csv(TAB / "did_table1_replication.csv")
ours = {r: t1.loc[t1.term == f"subject_race{r}:is_treatmentTRUE"].iloc[0] for r in RACE}
paper = {"white": (-0.96, 0.02), "black": (-0.98, 0.06), "hispanic": (-0.69, 0.03)}
rob = pd.read_csv(TAB / "did_robustness.csv")
clus = rob[rob.spec == "Logit, linear trend, SE clustered by state"]
clus = {r: clus.loc[clus.term == f"subject_race{r}:is_treatmentTRUE"].iloc[0] for r in RACE}

fig, ax = panel_figure((150, 78), (38, 6, 14, 12))
races = ["white", "black", "hispanic"]
for i, r in enumerate(races):
    y = len(races) - 1 - i
    pm, ps = paper[r]
    om, os_ = ours[r]["estimate"], ours[r]["std.error"]
    cs = clus[r]["std_error"]
    ax.plot([pm - 1.96 * ps, pm + 1.96 * ps], [y + 0.18] * 2, color=PAPER, lw=2.2, zorder=3)
    ax.scatter(pm, y + 0.18, s=34, color=PAPER, zorder=4)
    # ours: thin line = state-clustered CI, thick = iid CI as in the paper
    ax.plot([om - 1.96 * cs, om + 1.96 * cs], [y - 0.18] * 2, color=OURS, lw=0.9, zorder=2)
    ax.plot([om - 1.96 * os_, om + 1.96 * os_], [y - 0.18] * 2, color=OURS, lw=2.2, zorder=3)
    ax.scatter(om, y - 0.18, s=34, color=OURS, zorder=4)
ax.axvline(0, color=MUTED, lw=0.9)
ax.set_yticks(range(len(races)))
ax.set_yticklabels([RACE_LABEL[r] for r in races[::-1]])
ax.set_xlim(-1.75, 0.1)
ax.set_ylim(-0.6, 2.6)
ax.set_xlabel("Effect of legalization on search (log odds)")
ax.spines["left"].set_visible(False)
tidy(ax)
ax.tick_params(axis="y", length=0)
fig.legend([plt.Line2D([], [], color=PAPER, lw=2.2, marker="o"),
            plt.Line2D([], [], color=OURS, lw=2.2, marker="o"),
            plt.Line2D([], [], color=OURS, lw=0.9)],
           ["Paper", "Ours", "Ours, clustered by state"],
           loc="upper center", bbox_to_anchor=(0.55, 1.0), ncol=3, fontsize=8.5,
           handlelength=1.8)
save(fig, "fig_table1_coefs")

# (d) Event study
es = pd.read_csv(TAB / "did_event_study.csv").sort_values("rel_q")
fig, ax = panel_figure((170, 78), (18, 4, 14, 6))
ax.axhline(0, color=MUTED, lw=0.9)
ax.axvline(-0.5, color=MUTED, lw=0.9, ls=(0, (3, 2)))
pre = es.rel_q < 0
for mask, col in ((pre, INK), (~pre, OURS)):
    d = es[mask]
    ax.plot([d.rel_q, d.rel_q], [100 * (d.estimate - 1.96 * d.se), 100 * (d.estimate + 1.96 * d.se)],
            color=col, lw=1.1, zorder=3)
    ax.scatter(d.rel_q, 100 * d.estimate, s=18, facecolor=BG, edgecolor=col, lw=1.1, zorder=4)
ax.set_xlabel("Quarters since legalization (0 = 2012 Q4)")
ax.set_ylabel("Effect on search rate (pp)")
ax.set_xticks(range(-7, 13))
ax.set_xlim(-7.6, 12.6)
ax.text(-3.8, -0.62, "before", color=INK, fontsize=9, ha="center")
ax.text(6.5, -0.62, "after", color=OURS, fontsize=9, ha="center")
tidy(ax)
save(fig, "fig_event_study")

# (e) Placebo inference
pl = pd.read_csv(TAB / "did_placebo_estimates.csv")
fig, axes = grid_figure((170, 62), (12, 4, 14, 9), 1, 3, gap_mm=(10, 0))
for ax, r in zip(axes, races):
    d = pl[pl.term == f"subject_race{r}:is_treatmentTRUE"].estimate.values
    ax.hist(d, bins=np.linspace(-1.2, 0.6, 28), color=MUTED, alpha=0.8, lw=0)
    ax.axvline(ours[r]["estimate"], color=OURS, lw=2)
    ax.set_title(RACE_LABEL[r], loc="left", fontsize=9.5, pad=3)
    ax.set_xlim(-1.2, 0.6)
    ax.set_xlabel("Estimate (log odds)")
    tidy(ax)
axes[0].set_ylabel("Placebo pairs")
axes[0].annotate("Real CO + WA\nestimate", xy=(ours["white"]["estimate"], axes[0].get_ylim()[1] * 0.92),
                 xytext=(6, 0), textcoords="offset points", fontsize=8, color=OURS, va="top")
save(fig, "fig_placebo")

# (f) Veil of darkness, Texas (analogue of paper Fig. 2)
vt = pd.read_csv(TAB / "vod_texas_fig2.csv")
windows = ["7:00-7:15 pm", "7:15-7:30 pm", "7:30-7:45 pm"]
fig, axes = grid_figure((200, 72), (16, 4, 14, 9), 1, 3, gap_mm=(8, 0))
for ax, w in zip(axes, windows):
    d = vt[vt.window == w]
    for dark, col in ((False, "#F2C14E"), (True, "#7E8FD9")):
        s = d[d.is_dark == dark]
        ax.scatter(s.min_since_dusk, 100 * s.share_black, s=s.n / s.n.max() * 40 + 4,
                   color=col, alpha=0.85, lw=0, zorder=3)
        if len(s) > 1:   # weighted least-squares line on each side of dusk
            b = np.polyfit(s.min_since_dusk, 100 * s.share_black, 1, w=np.sqrt(s.n))
            xs = np.array([s.min_since_dusk.min(), s.min_since_dusk.max()])
            ax.plot(xs, np.polyval(b, xs), color=col, lw=1.4, zorder=4)
    ax.axvline(0, color=MUTED, lw=0.9, ls=(0, (3, 2)))
    ax.set_title(w, loc="left", fontsize=9.5, pad=3)
    ax.set_ylim(10, 32)
    ax.set_xlabel("Minutes since dusk")
    tidy(ax)
    if ax is not axes[0]:
        ax.set_yticklabels([])
axes[0].set_ylabel("Stopped drivers who are Black (%)")
axes[0].text(-125, 11.2, "light", color="#F2C14E", fontsize=8.5)
axes[0].text(40, 11.2, "dark", color="#7E8FD9", fontsize=8.5)
save(fig, "fig_vod_texas")

# check that the saved PNGs have the size we asked for
from PIL import Image
for f in sorted(OUT.glob("*.png")):
    w, h = Image.open(f).size
    print(f"{f.name:28s} {w / 300 * 25.4:6.1f} x {h / 300 * 25.4:5.1f} mm")
