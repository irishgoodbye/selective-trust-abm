# Permission to Deviate

**An agent-based model of how audiences grant and withdraw prestige through selective trust.**

Why does breaking a norm sometimes make someone *more* respected, and sometimes end them? This model tests one answer: audiences don't judge a deviation on its own — they judge it against the deviator's history, and they can revoke that judgment all at once.

---

## The idea in one line

Credibility isn't a property of a signal. It's a judgment an audience makes by checking a new act against everything it already knows about the actor — and that judgment can be withdrawn.

## What's actually in here

A 500-agent NetLogo simulation where:

- Agents sit in one of three tiers (elite, subculture, institutional), each with its own starting prestige and cultural profile
- Every deviation from the group norm gets scored on **consistency**, **visibility**, and **cultural similarity** — multiplied together, so no single factor can carry a deviation on its own
- Prestige builds only through *credited* deviation. Conformity holds your position; it never grows it
- A collapse mechanism (**reappraisal**) can wipe an agent's prestige and history in a single tick, modeling how a reputation can fail all at once rather than erode gradually

## What we found

- Subcultures adopt new signals before elites do, 84% of the time — confirming a subculture-to-elite adoption pathway
- Prestige rises while a signal stays rare and collapses once it's common — but only once we fixed a parameter tradeoff that was masking the effect entirely
- The collapse mechanism, at its original settings, only ever caught agents with no history at all — never the established actors the theory is actually about. Two implementation bugs were found and fixed along the way
- Once recalibrated, the mechanism turned out to be highly selective: it reaches only the one agent tier whose cultural traits are randomly assigned rather than clustered — exactly the population most likely to end up genuinely out of step with its neighbors
- A separate, controlled test confirms the same thing directly: force an identical collapse on two agents, one culturally close to its neighbors and one far, and the far one recovers to roughly half the prestige — if it recovers at all

Full results, statistics, and the two-bug debugging story are in the paper.

## Quick start

1. Open `selective-trust-model.nlogo` in NetLogo 6.4+.
2. Click Setup, then Go.
3. Type `diagnose` into the Command Center at any tick for a full snapshot of calibration targets.
4. See the Info tab for parameter definitions, defaults, and things to try.

To reproduce the paper's results, load the BehaviorSpace experiments in /experiments and run at the parameter values listed in the paper's Appendix.

## Repository structure
