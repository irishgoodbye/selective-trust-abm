"""
If you use this code, please cite:
Left, S. (2026). Permission to Deviate: How Audiences Grant and
Withdraw Prestige Through Selective Trust.

statistics.py

Reproduces every statistical test and headline number reported in
"Permission to Deviate: How Audiences Grant and Withdraw Prestige
Through Selective Trust."

Expects the following CSVs in the same directory as this script
(filenames match the BehaviorSpace exports uploaded to this repo):

    H1-H2-default-clean-nostrangers-table.csv
    H1-H2-reduced-clean-nostrangers-table.csv
    H2-regime-confirmation-table.csv
    H3-stranger-confound-check-table.csv
    H3-controlled-shock-recovery-table.csv
    H3-host-vis-ceiling-table.csv
    H3-reappraisal-threshold-sweep-final-table.csv

Requires: scipy, statsmodels
    pip install scipy statsmodels

Run: python statistics.py
"""

import csv
import statistics
from collections import defaultdict
from scipy import stats
import statsmodels.api as sm


def load_table(path):
    """Load a BehaviorSpace table export, returning (header, data_rows)."""
    with open(path) as f:
        lines = list(csv.reader(f))
    header_idx = next(i for i, row in enumerate(lines) if row and row[0] == "[run number]")
    header = lines[header_idx]
    data = [row for row in lines[header_idx + 1:] if len(row) == len(header)]
    return header, data


def h1_sequencing():
    """H1: subculture-before-elite adoption sequencing, binomial test."""
    print("=" * 60)
    print("H1 — Signal Origin and Elite Adoption")
    print("=" * 60)

    header, data = load_table("H2-regime-confirmation-table.csv")
    runs = defaultdict(list)
    for row in data:
        runs[row[0]].append(row)

    sub_adopt, elite_adopt = {}, {}
    for run, rows in runs.items():
        last = sorted(rows, key=lambda r: int(r[1]))[-1]
        sub_adopt[run] = int(last[6])
        elite_adopt[run] = int(last[7])

    joint = [r for r in runs if sub_adopt[r] != -1 and elite_adopt[r] != -1]
    seq = sum(1 for r in joint if sub_adopt[r] < elite_adopt[r])

    print(f"Joint adoption: {len(joint)}/{len(runs)}")
    print(f"Sequencing (subculture before elite): {seq}/{len(joint)} "
          f"({100*seq/len(joint):.0f}%)")

    result = stats.binomtest(seq, len(joint), 0.5)
    print(f"Binomial test vs. chance: p = {result.pvalue:.6f}")
    print()


def h2_saturation_trajectory():
    """H2: prestige trajectory and saturation threshold crossing (feeds Fig. 1)."""
    print("=" * 60)
    print("H2 — Signal Decay Through Diffusion")
    print("=" * 60)

    header, data = load_table("H1-H2-reduced-clean-nostrangers-table.csv")
    by_step_elite = defaultdict(list)
    by_step_sub = defaultdict(list)
    by_step_counter = defaultdict(list)

    for row in data:
        step = int(row[1])
        by_step_elite[step].append(float(row[2]))
        by_step_sub[step].append(float(row[3]))
        by_step_counter[step].append(float(row[5]) / 500.0)

    steps = sorted(by_step_elite.keys())
    elite_means = [statistics.mean(by_step_elite[s]) for s in steps]
    sub_means = [statistics.mean(by_step_sub[s]) for s in steps]

    peak_step_elite = max(steps, key=lambda s: statistics.mean(by_step_elite[s]) if s >= 200 else -1)
    peak_step_sub = max(steps, key=lambda s: statistics.mean(by_step_sub[s]) if s >= 200 else -1)

    print(f"Elite peak: {statistics.mean(by_step_elite[peak_step_elite]):.3f} at tick {peak_step_elite}")
    print(f"Elite final (tick 2500): {statistics.mean(by_step_elite[2500]):.3f}")
    print(f"Subculture peak: {statistics.mean(by_step_sub[peak_step_sub]):.3f} at tick {peak_step_sub}")
    print(f"Subculture final (tick 2500): {statistics.mean(by_step_sub[2500]):.3f}")

    for step in sorted(by_step_counter.keys()):
        if statistics.mean(by_step_counter[step]) >= 0.30:
            print(f"Countersignal share crosses 0.30 at approximately tick {step}")
            break
    print()


def h4_tier_convergence():
    """Reward-Saturation Tradeoff: tier convergence at tick 2500."""
    print("=" * 60)
    print("Reward-Saturation Tradeoff — Tier Convergence at Tick 2500")
    print("=" * 60)

    header, data = load_table("H1-H2-reduced-clean-nostrangers-table.csv")
    elite, sub, inst = [], [], []
    for row in data:
        if int(row[1]) == 2500:
            elite.append(float(row[2]))
            sub.append(float(row[3]))
            inst.append(float(row[4]))

    e, s, i = statistics.mean(elite), statistics.mean(sub), statistics.mean(inst)
    print(f"Elite: {e:.4f}  Subculture: {s:.4f}  Institutional: {i:.4f}")
    print(f"Spread: {max(e,s,i)-min(e,s,i):.4f} ({(max(e,s,i)-min(e,s,i))*100:.2f} percentage points)")
    print()


def h3_stranger_confound():
    """H3: stranger-confound diagnostic (0/20 vs 10/20, 100% stranger-tagged)."""
    print("=" * 60)
    print("H3 — Stranger-Confound Diagnostic")
    print("=" * 60)

    header, data = load_table("H3-stranger-confound-check-table.csv")
    # Columns: [run number], NUM-STRANGERS, [step], reappraisal-count,
    #          reappraisal-elite-n, reappraisal-subculture-n,
    #          reappraisal-institutional-n, reappraisal-stranger-n, ...
    # Per-tick data: take the final step for each run to get end-of-run totals.
    runs = defaultdict(list)
    for row in data:
        runs[row[0]].append(row)

    by_ns = defaultdict(list)
    for run, rows in runs.items():
        last = sorted(rows, key=lambda r: int(r[2]))[-1]
        by_ns[last[1]].append(last)  # group final row by NUM-STRANGERS

    for ns, rows in sorted(by_ns.items()):
        n_events = sum(1 for r in rows if int(r[3]) > 0)  # reappraisal-count column
        n_stranger_tagged = sum(int(r[7]) for r in rows)  # reappraisal-stranger-n
        total_events = sum(int(r[3]) for r in rows)
        print(f"NUM-STRANGERS = {ns}: reappraisal in {n_events}/{len(rows)} replications "
              f"({total_events} total events, {n_stranger_tagged} tagged stranger)")
    print()


def h3_controlled_shock():
    """H3: controlled exogenous shock, Mann-Whitney U (feeds Fig. 3)."""
    print("=" * 60)
    print("H3 — Controlled Exogenous Shock Test")
    print("=" * 60)

    header, data = load_table("H3-controlled-shock-recovery-table.csv")
    by_level = defaultdict(dict)
    for row in data:
        run, level, step = row[0], row[1], int(row[2])
        prestige = float(row[5])
        if prestige == -1:
            continue
        by_level[level][run] = prestige  # keeps last value written per run = final tick

    high_vals = list(by_level["high"].values())
    low_vals = list(by_level["low"].values())

    print(f"High-SIM: mean = {statistics.mean(high_vals):.3f}, "
          f"SD = {statistics.stdev(high_vals):.3f}, n = {len(high_vals)}")
    print(f"Low-SIM:  mean = {statistics.mean(low_vals):.3f}, "
          f"SD = {statistics.stdev(low_vals):.3f}, n = {len(low_vals)}")
    print(f"No-recovery count — low-SIM: {sum(1 for v in low_vals if v < 0.15)}/{len(low_vals)}, "
          f"high-SIM: {sum(1 for v in high_vals if v < 0.15)}/{len(high_vals)}")

    u_stat, p_val = stats.mannwhitneyu(high_vals, low_vals, alternative="two-sided")
    print(f"Mann-Whitney U: U = {u_stat:.0f}, p = {p_val:.3f}")
    print()


def h3_recalibration_sweep():
    """H3: endogenous recalibration threshold sweep (feeds Fig. 2)."""
    print("=" * 60)
    print("H3 — Endogenous Recalibration Sweep")
    print("=" * 60)

    header, data = load_table("H3-reappraisal-threshold-sweep-final-table.csv")
    by_thresh = defaultdict(list)
    for row in data:
        by_thresh[row[1]].append(row)  # REAPPRAISAL-CREDIBILITY column

    for thresh in sorted(by_thresh.keys(), key=float):
        rows = by_thresh[thresh]
        n = len(rows)
        n_events = sum(1 for r in rows if int(r[7]) > 0)
        total_events = sum(int(r[7]) for r in rows)
        total_inst = sum(int(r[10]) for r in rows)
        sims = [float(r[12]) for r in rows if float(r[12]) != -1]
        baseline_sims = [float(r[13]) for r in rows]

        print(f"\nREAPPRAISAL-CREDIBILITY = {thresh}")
        print(f"  Replications with >=1 event: {n_events}/{n} ({100*n_events/n:.0f}%)")
        print(f"  Total events: {total_events} (institutional: {total_inst})")
        if sims:
            print(f"  Mean SIM at reappraisal: {statistics.mean(sims):.3f}")
        print(f"  Mean general deviator SIM baseline: {statistics.mean(baseline_sims):.3f}")

    # 95% CI on occurrence rate at 0.007 (the reported calibration)
    rows_007 = by_thresh.get("0.007", [])
    if rows_007:
        n = len(rows_007)
        x = sum(1 for r in rows_007 if int(r[7]) > 0)
        ci_low, ci_high = sm.stats.proportion_confint(x, n, alpha=0.05, method="wilson")
        print(f"\n95% CI on occurrence rate at 0.007: [{ci_low:.3f}, {ci_high:.3f}]")
    print()


def h3_vis_ceiling():
    """Host-agent VIS reachability check."""
    print("=" * 60)
    print("H3 — Host-Agent VIS Ceiling Check")
    print("=" * 60)

    header, data = load_table("H3-host-vis-ceiling-table.csv")
    vis_max = [float(row[7]) for row in data if float(row[7]) != -1]
    vis_mean = [float(row[8]) for row in data if float(row[8]) != -1]

    print(f"n replications: {len(vis_max)}")
    print(f"Mean of per-run max VIS: {statistics.mean(vis_max):.3f}")
    print(f"Mean of per-run mean VIS: {statistics.mean(vis_mean):.3f} "
          f"(range {min(vis_mean):.2f}-{max(vis_mean):.2f})")
    print()


if __name__ == "__main__":
    h1_sequencing()
    h2_saturation_trajectory()
    h4_tier_convergence()
    h3_stranger_confound()
    h3_controlled_shock()
    h3_recalibration_sweep()
    h3_vis_ceiling()
