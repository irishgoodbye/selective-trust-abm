"""
generate_figures.py

If you use this code, please cite:
Left, S. (2026). Permission to Deviate: How Audiences Grant and
Withdraw Prestige Through Selective Trust.

Regenerates Fig. 1, Fig. 2, and Fig. 3 

Expects the following CSVs in the same directory as this script:

    H1-H2-reduced-clean-nostrangers-table.csv   -> Fig. 1
    H3-reappraisal-threshold-sweep-final-table.csv -> Fig. 2
    H3-controlled-shock-recovery-table.csv      -> Fig. 3

Requires: matplotlib
    pip install matplotlib

Run: python generate_figures.py
Output: fig1_prestige_saturation.pdf/.png,
        fig2_recalibration_finding.pdf/.png,
        fig3_shock_recovery.pdf/.png
"""

import csv
import statistics
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load_table(path):
    with open(path) as f:
        lines = list(csv.reader(f))
    header_idx = next(i for i, row in enumerate(lines) if row and row[0] == "[run number]")
    header = lines[header_idx]
    data = [row for row in lines[header_idx + 1:] if len(row) == len(header)]
    return header, data


def fig1_prestige_saturation():
    _, data = load_table("H1-H2-reduced-clean-nostrangers-table.csv")

    by_step_elite = defaultdict(list)
    by_step_sub = defaultdict(list)
    by_step_counter = defaultdict(list)
    for row in data:
        step = int(row[1])
        by_step_elite[step].append(float(row[2]))
        by_step_sub[step].append(float(row[3]))
        by_step_counter[step].append(float(row[5]) / 500.0)

    steps = sorted(by_step_elite.keys())
    elite = [statistics.mean(by_step_elite[s]) for s in steps]
    sub = [statistics.mean(by_step_sub[s]) for s in steps]
    counter = [statistics.mean(by_step_counter[s]) for s in steps]

    fig, ax1 = plt.subplots(figsize=(6.5, 4.3))
    l1, = ax1.plot(steps, elite, linestyle='-', color='black', linewidth=1.3,
                    label='Elite mean prestige')
    l2, = ax1.plot(steps, sub, linestyle='-.', color='black', linewidth=1.3,
                    label='Subculture mean prestige')
    ax1.set_xlabel('Tick', fontsize=9)
    ax1.set_ylabel('Mean prestige (left axis)', fontsize=9)
    ax1.set_ylim(0, 1)
    ax1.set_xlim(0, 2500)
    ax1.tick_params(labelsize=8)

    ax2 = ax1.twinx()
    l3, = ax2.plot(steps, counter, linestyle=':', color='black', linewidth=1.6,
                    label='Countersignal population share')
    ax2.set_ylabel('Countersignal population share (right axis)', fontsize=9)
    ax2.set_ylim(0, 0.45)
    ax2.tick_params(labelsize=8)
    ax2.axhline(y=0.30, color='black', linewidth=0.7, linestyle=(0, (1, 1)), alpha=0.7)
    ax2.text(1250, 0.40, 'SATURATION-THRESHOLD = 0.30', fontsize=7.5, va='center', ha='center')
    ax2.annotate('', xy=(1250, 0.305), xytext=(1250, 0.385),
                 arrowprops=dict(arrowstyle='-', color='black', linewidth=0.5, linestyle=':'))

    ax1.legend([l1, l2, l3], [l1.get_label(), l2.get_label(), l3.get_label()],
               loc='lower right', fontsize=7.5, frameon=True, framealpha=0.9)

    plt.tight_layout()
    plt.savefig('fig1_prestige_saturation.pdf', dpi=1200)
    plt.savefig('fig1_prestige_saturation.png', dpi=300)
    plt.close()
    print("Saved fig1_prestige_saturation.pdf/.png")


def fig2_recalibration_finding():
    _, data = load_table("H3-reappraisal-threshold-sweep-final-table.csv")

    by_thresh = defaultdict(list)
    for row in data:
        by_thresh[row[1]].append(row)

    thresholds = [0.003, 0.005, 0.007, 0.010]
    occ_rate, reap_sim, baseline_sim = [], [], []
    for t in thresholds:
        rows = by_thresh[str(t)]
        n = len(rows)
        n_events = sum(1 for r in rows if int(r[7]) > 0)
        occ_rate.append(100 * n_events / n)
        sims = [float(r[12]) for r in rows if float(r[12]) != -1]
        reap_sim.append(statistics.mean(sims) if sims else None)
        baseline_sim.append(statistics.mean([float(r[13]) for r in rows]))

    fig, ax1 = plt.subplots(figsize=(6.5, 4.3))
    l1, = ax1.plot(thresholds, baseline_sim, linestyle='-.', color='black', marker='s',
                    markerfacecolor='white', markeredgecolor='black', linewidth=1.3,
                    label='General deviator SIM (baseline)')
    reap_x = [t for t, s in zip(thresholds, reap_sim) if s is not None]
    reap_y = [s for s in reap_sim if s is not None]
    l2, = ax1.plot(reap_x, reap_y, linestyle='-', color='black', marker='o',
                    markerfacecolor='black', markeredgecolor='black', linewidth=1.6,
                    label='Mean SIM at reappraisal')
    ax1.set_xlabel('REAPPRAISAL-CREDIBILITY', fontsize=9)
    ax1.set_ylabel('Mean cultural similarity (SIM), left axis', fontsize=9)
    ax1.set_ylim(0, 0.65)
    ax1.set_xticks(thresholds)
    ax1.set_xticklabels(['0.003', '0.005', '0.007', '0.010'])
    ax1.tick_params(labelsize=8)

    ax2 = ax1.twinx()
    ax2.bar(thresholds, occ_rate, width=0.0012, color='0.85', edgecolor='black',
            linewidth=0.8, alpha=0.9, zorder=0)
    ax2.set_ylabel('Replications with >=1 reappraisal event (%), right axis', fontsize=9)
    ax2.set_ylim(0, 110)
    ax2.tick_params(labelsize=8)
    for t, r in zip(thresholds, occ_rate):
        ax2.text(t, r + 3, f'{r:.0f}%', fontsize=7.5, ha='center', va='bottom')

    ax1.set_zorder(ax2.get_zorder() + 1)
    ax1.patch.set_visible(False)

    bar_proxy = plt.Rectangle((0, 0), 1, 1, fc='0.85', ec='black', linewidth=0.8)
    ax1.legend([l1, l2, bar_proxy],
               [l1.get_label(), l2.get_label(), 'Occurrence rate'],
               loc='upper left', fontsize=7, frameon=True, framealpha=0.9)

    plt.tight_layout()
    plt.savefig('fig2_recalibration_finding.pdf', dpi=1200)
    plt.savefig('fig2_recalibration_finding.png', dpi=300)
    plt.close()
    print("Saved fig2_recalibration_finding.pdf/.png")


def fig3_shock_recovery():
    _, data = load_table("H3-controlled-shock-recovery-table.csv")

    by_level_tickssince = defaultdict(lambda: defaultdict(list))
    for row in data:
        level, step, prestige = row[1], int(row[2]), float(row[5])
        if prestige == -1:
            continue
        ticks_since = int(row[4])
        by_level_tickssince[level][ticks_since].append(prestige)

    fig, ax = plt.subplots(figsize=(6.5, 4.3))
    for level, style, label in [("high", '-', 'High-SIM agents (n=20)'),
                                  ("low", '--', 'Low-SIM agents (n=20)')]:
        ts_keys = sorted(by_level_tickssince[level].keys())
        means = [statistics.mean(by_level_tickssince[level][t]) for t in ts_keys]
        ax.plot(ts_keys, means, linestyle=style, color='black', linewidth=1.4, label=label)

    ax.set_xlabel('Ticks since shock', fontsize=9)
    ax.set_ylabel('Mean prestige', fontsize=9)
    ax.set_xlim(0, 500)
    ax.set_ylim(0, 1)
    ax.tick_params(labelsize=8)
    ax.axvline(x=0, color='black', linewidth=0.6, linestyle=(0, (1, 1)), alpha=0.6)
    ax.text(5, 0.95, 'Shock applied\n(prestige x 0.1)', fontsize=6.5, va='top', ha='left')
    ax.legend(loc='lower right', fontsize=8, frameon=True, framealpha=0.9)

    plt.tight_layout()
    plt.savefig('fig3_shock_recovery.pdf', dpi=1200)
    plt.savefig('fig3_shock_recovery.png', dpi=300)
    plt.close()
    print("Saved fig3_shock_recovery.pdf/.png")


if __name__ == "__main__":
    fig1_prestige_saturation()
    fig2_recalibration_finding()
    fig3_shock_recovery()
