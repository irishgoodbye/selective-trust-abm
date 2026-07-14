globals [
  NUM-CONFORM        ;Running counts of how many agents are currently sending each signal type. Updated every tick.
  NUM-SIGNAL
  NUM-COUNTERSIGNAL
  pop-modal-signal    ; most common signal in the host population

  regime              ; egalitarian, stratified, transitional, or frozen. Recalculated every 50 ticks.
  top-id              ; Who number of the agent with the highest prestige
  turnover-count      ; How many times the top prestige agent has changed across the run. Measures prestige hierarchy stability.

  fossilize-streak                ;how many consecutive ticks have passed without a leadership change.
  fossilize-streak-threshold      ; If the streak hits the threshold the model flags itself as fossilized -
  fossilized?                     ; the hierarchy has locked and stopped moving.

  elite-mean-prestige             ; Average prestige for each tier, updated every tick.
  subculture-mean-prestige        ; These are primary output measures for tier differentiation.
  institutional-mean-prestige
  stranger-mean-prestige
  host-mean-prestige

  ; H1 diffusion tracking
  subculture-first-adopted-tick   ; The tick at which each tier first crossed the countersignal adoption threshold-
  elite-adopted-tick              ; which tier adopted countersignaling first.

  ; host modal vector for stranger initialization
  host-modal-vec                   ;most common cultural vector across all host agents.
                                 ; Computed when strangers arrive so their vectors can be placed at a controlled distance from the host cultural center.
 ; for H3 / cancel culture logging
  reappraisal-count
  reappraisal-sim-log
  deviator-sim-log

  ; H3 diagnostic: does VIS/SIM correlate among host deviators?
  host-dev-vis-log
  host-dev-sim-log
  host-dev-cred-log
  high-vis-host-sim-log      ; SIM values only for host deviators with VIS > 0.90

  reappraisal-who-log

 ; for controlled exogenous-shock recovery tracking
  shocked-agent-who
  shocked-agent-tick

  ; BehaviorSpace-controlled shock experiment parameters
  ; SHOCK-TICK
  ;RECOVERY-WINDOW
  ;SHOCK-SIM-LEVEL
]

turtles-own [
  signal              ; conform, signal, or countersignal
  prestige    ; Current standing in the population. Continuous value between 0 and 1. Accumulates through credible deviation, decays passively every tick.
  status-tier         ; group the agent belongs to — elite, subculture, institutional, or stranger. Fixed at initialization
  cultural-vector     ; 5-element binary list- (Axelrod)- compute SIM scores between actor and observer
  signal-history      ; running list of the agent's recent signals, bounded by OBSERVATION-WINDOW. This is what CON is calculated from
  deviation-score       ; 1 if deviating from population modal, 0 if conforming
  credibility-score     ; The most recently computed credibility evaluation for this agent. Updated every tick for deviating agents
  switched-this-tick?   ;
  ticks-since-reappraisal   ; -1 if never reappraised, else counts up each tick

  frac-conform          ; Proportion of this agent's direct neighbors currently sending each signal type-
  frac-signal           ; Updated every tick-
  frac-counter          ; Gives each agent a local picture of their neighborhood signal distribution
]

; =============================================================
; SETUP
; =============================================================

to setup
  clear-all

  set fossilize-streak 0
  set fossilize-streak-threshold 50
  set fossilized? false
  set turnover-count 0
  set subculture-first-adopted-tick -1
  set elite-adopted-tick -1

  set reappraisal-count 0
  set reappraisal-sim-log []
  set reappraisal-who-log []
  set deviator-sim-log []

  set shocked-agent-who -1
  set shocked-agent-tick -1

  set host-dev-vis-log []
  set host-dev-sim-log []
  set host-dev-cred-log []
  set high-vis-host-sim-log []

  setup-turtles
  setup-network
  update-stats
  set pop-modal-signal compute-pop-modal
  set host-modal-vec compute-host-modal-vector
  reset-ticks

  set-current-plot "Prestige by Tier"
  clear-plot


end

to setup-turtles
  create-turtles NUM-AGENTS [
    setxy random-xcor random-ycor

  ; signal assignment by tier baseline tendency
    ; elite: baseline tendency is countersignaling
    ; subculture: mixed, origin point for signals elites adopt
    ; institutional: baseline tendency is conformist
    ; behavioral type and status tier assigned together here,
    ; agents can still switch through reappraisal collapse

    ; cultural vector: 5 binary features (Axelrod- SIM score)
    set cultural-vector n-values 5 [random 2]      ; Gives every agent a random placeholder cultural vector/ 5 features each randomly 0 or 1.

    set signal "conform"         ; temporary default - to be overwritten
    set signal-history []          ; filled after signal assigned
    set deviation-score 0
    set credibility-score 0
    set switched-this-tick? false
    set status-tier 0
    set prestige 0
    set ticks-since-reappraisal -1
  ]

  ; --- TIER ASSIGNMENT ---
  let elite-n round (NUM-AGENTS * 0.20)    ; Calculates how many agents go into each tier-
  let sub-n   round (NUM-AGENTS * 0.30)    ; 20% elite, 30% subculture, leaving 50% institutional

  ask n-of elite-n turtles [                                    ; Randomly selects the elite agents
    set status-tier "elite"                                     ; assigns them their tier label
    set cultural-vector n-values 5 [ifelse-value (random-float 1 < 0.15) [1] [0]]   ; tightly clustered cultural vectors
                                                                                   ; starting prestige between 0.70 & 0.80
    set prestige 0.70 + random-float 0.10
  ]
  ask n-of sub-n turtles with [status-tier = 0] [                ; From remaining unassigned agents selects subculture agents.
    set status-tier "subculture"                                 ; Gives them partially distinct cultural vectors and starting -
    set cultural-vector n-values 5 [round random-float 0.7]      ; prestige between 0.55 and 0.65.
    set prestige 0.55 + random-float 0.10
  ]
  ask turtles with [status-tier = 0] [                            ; Everyone still unassigned becomes institutional —
    set status-tier "institutional"                               ; the dominant normative order.
    set cultural-vector n-values 5 [random 2]                      ; Random cultural vectors and lowest starting prestige between 0.25 and 0.35.
    set prestige 0.25 + random-float 0.10
  ]

 ; --- SIGNAL ASSIGNMENT BY TIER ---
  ; countersignalers rare at initialization (proposal section 3.5)         ; Each elite agent draws a random number.
  ; diffusion dynamics produce adoption sequence, not initialization       ; Elite agents: 15% conform, 82% signal, 3% countersignal.
  ; elite: baseline tendency toward signaling, countersignal rare           ; diffusion dynamics produce the adoption sequence
  ; elite: ~3% countersignal at initializationon
ask turtles with [status-tier = "elite"] [
  let r random-float 1
  ifelse r < 0.15 [ set signal "conform" ]
  [ ifelse r < 0.97 [ set signal "signal" ]
  [ set signal "countersignal" ] ]
]

; subculture :~2% countersignal at initialization            ; Subculture agents: 40% conform, 58% signal, 2% countersignal.
ask turtles with [status-tier = "subculture"] [           ; Institutional agents have no explicit signal block — they keep the default conform assigned earlier,
  let r random-float 1                                    ; giving them roughly 100% conformist starting tendency consistent with their role as the dominant normative order.
  ifelse r < 0.40 [ set signal "conform" ]
  [ ifelse r < 0.98 [ set signal "signal" ]
  [ set signal "countersignal" ] ]
]

  ; --- WARM START ---
  ; Pre-fills every agent's signal history with copies of their just-assigned signal.
  ; An agent assigned countersignal gets a full history of countersignal
  ; This means CON starts at 1.0 for everyone- agents enter the model with established reputations rather than blank histories.

  ask turtles [                                                  ; simulates agents with existing reputation (CON non-zero from tick 1)
    set signal-history n-values OBSERVATION-WINDOW [signal]
  ]

end


to setup-network
  clear-links

  if NETWORK-TYPE = "small-world" [                 ; Builds the Watts-Strogatz small-world base.
    let k 6                                         ; Each agent connects to k=6 neighbors in a ring structure
    let turtle-list sort turtles                    ; agents link to the agents nearest them in the sorted list.
    let n length turtle-list
    foreach turtle-list [ t ->
      ask t [
        repeat k [
          let offset 1 + random k
          let buddy item ((who + offset) mod n) turtle-list
          if buddy != self and not link-neighbor? buddy [
            create-link-with buddy
          ]
        ]
      ]
    ]
    ; rewiring at probability 0.1                    ; Rewiring step — each link has a 10% chance of being redirected-
    ask links [                                       ; to a random agent instead of its original neighbor
      if random-float 1 < 0.1 [                       ; creates the shortcuts that give small-world networks their short average path lengths.
        let t1 end1
        let new-buddy one-of other turtles with [
          self != t1 and not link-neighbor? t1
        ]
        if new-buddy != nobody [
          die
          ask t1 [ create-link-with new-buddy ]
        ]
      ]
    ]
  ]

  if NETWORK-TYPE = "scale-free" [                                ; Scale-free alternative
    ask turtles [                                                 ; each agent connects to whoever already has the most connections
      let buddy max-one-of other turtles [count link-neighbors]    ; preferential attachment, producing hubs with disproportionate reach
      if buddy != nobody and not link-neighbor? buddy [
        create-link-with buddy
      ]
    ]
  ]
  ; elite agents get higher degree- operationalizes Henrich & Gil-White
  ; prestige bias through attention: high-status actors attract more observers
  ; additional connections give elite agents more evaluation events
  ; and higher VIS scores through broader network reach
  ask turtles with [status-tier = "elite"] [                             ; After the base topology is built, elite agents get
    repeat 4 [                                                            ; 4 extra connections
      let buddy one-of other turtles with [not link-neighbor? self]
      if buddy != nobody [ create-link-with buddy ]
    ]
  ]

  ask turtles with [status-tier = "subculture"] [
    repeat 2 [                                                             ; subculture agents get 2 extra connections
      let buddy one-of other turtles with [not link-neighbor? self]
      if buddy != nobody [ create-link-with buddy ]
    ]
  ]
  repeat 30 [ layout-spring turtles links 0.5 10 1.0 ]           ;  spring layout to position agents visually closer together
end

; =============================================================
; STRANGER INTRODUCTION
; Strangers arrive at STRANGER-ARRIVAL-TICK with:
;   empty signal history (CON = 0)
;   cultural vector at STRANGER-VECTOR-DISTANCE from host modal
;   categorical prior as only initial credibility source
; This is the same mechanism as cold start but with lower SIM
; producing a lower prior and a higher effective credibility bar
; =============================================================

to introduce-strangers                                                ; Recomputes the host cultural center at the moment strangers arrive-
  set host-modal-vec compute-host-modal-vector                        ; captures whatever cultural drift has occurred since initialization.

  ; build stranger origin vector at distance from host modal
  let origin-vec []
  foreach range 5 [ i ->                                                ; Goes through each of the 5 cultural features
    let host-feature item i host-modal-vec
    let flipped ifelse-value (host-feature = 1) [0] [1]                  ; places strangers at a cultural distance

    ; first STRANGER-VECTOR-DISTANCE features flipped from host modal
    let feature ifelse-value (i < STRANGER-VECTOR-DISTANCE)
      [flipped]
      [host-feature]
    set origin-vec lput feature origin-vec
  ]

  create-turtles NUM-STRANGERS [                     ; Creates stranger agents
    setxy random-xcor random-ycor
    set status-tier "stranger"
    set signal "conform"                              ; They start conforming, with low prestige matching institutional agents
    set prestige 0.25 + random-float 0.10

    ; strangers arrive with origin cultural vector
    set cultural-vector origin-vec

    ; NO warm start/ strangers have zero host-context history
    ; CON is 0
    ; categorical prior provides the only initial credibility floor
    set signal-history []

    set deviation-score 0
    set credibility-score 0
    set switched-this-tick? false

    ; Each stranger connects to one randomly chosen host agent
    let buddy one-of turtles with [status-tier != "stranger"]           ; strangers enter the network peripherally
    if buddy != nobody [ create-link-with buddy ]                       ; only 1 link through which to accumulate observations and credibility

    update-appearance
  ]
end

to-report compute-host-modal-vector
  let host-agents turtles with [status-tier != "stranger"]           ; Looks at all host agents except strangers
  if not any? host-agents [ report n-values 5 [0] ]
  let modal-vec []
  foreach range 5 [ i ->                                              ; For each of the 5 cultural features, counts how many agents have a 1
    let feature-sum sum [item i cultural-vector] of host-agents
    let modal-val ifelse-value (feature-sum > count host-agents / 2) [1] [0]   ;If more than half do, the modal value for that feature is 1, otherwise 0.
    set modal-vec lput modal-val modal-vec
  ]
  report modal-vec                                                   ; Returns a 5-element list representing the cultural center of the host population
end

; =============================================================
; MAIN LOOP
;
; 0: Introduce strangers if arrival tick reached
; 1. Emit signals (update history)
; 2. Update observational records
; 3. Compute population modal signal
; 4. Decay prestige
; 5. Evaluate credibility and update prestige
; 6. Apply epsilon noise
; 7. Clamp prestige to [0, 1]
; 8. Update statistics and tracking
; 9. Update plots and layout
;
; =============================================================

to go
  ;Step 0:  At the designated tick, if strangers are enabled, introduces them
  if ticks = STRANGER-ARRIVAL-TICK and NUM-STRANGERS > 0 [            ; At STRANGER-ARRIVAL-TICK, if NUM-STRANGERS is greater than zero,
    introduce-strangers                                               ; strangers are created and added to the network
  ]

  ; Step 1: emit signals
  ask turtles [
    set switched-this-tick? false                         ; Resets the switch flag.
    set signal-history lput signal signal-history         ; Appends the current signal to the end of history
    if length signal-history > OBSERVATION-WINDOW [       ; If history is now longer than the observation window,
      set signal-history but-first signal-history         ; removes the oldest entry from the front.
    ]
  ]

  ; Step 2: update observational records
  ask turtles [ update-neighbor-fracs ]         ;  each agent looks at their neighbors and records what fraction are sending each signal type.

  ; Step 3 : population modal computed once per tick    ; computes the population-wide modal signal once and stores it.
  set pop-modal-signal compute-pop-modal       ; Every agent uses this same value to determine whether they are conforming or deviating.

  ; Step 4: decay then evaluate
  ask turtles [
    set prestige prestige * (1 - PRESTIGE-DECAY)     ; Every agent loses a fixed percentage of their prestige before evaluation runs.
  ]                                                  ; Actors must signal continuously to maintain standing.

  ; Step 5: evaluate                  ;  the core mechanism.
  ask turtles [ evaluate ]            ; Every agent runs the evaluate procedure which determines -
                                      ; whether they are conforming or deviating and updates prestige accordingly.
  ; step 6 epsilon noise
  ask turtles [
    if not switched-this-tick? [
      if random-float 1 < EPSILON [                              ; Agents who haven't already switched this tick have a small probability
        set signal one-of ["conform" "signal" "countersignal"]    ; of randomly changing their signal and clearing their history
        set signal-history []                                     ; Set to near zero
        set switched-this-tick? true
      ]
    ]
  ]

 ; Step 7: Prestige Clamp:                ; Hard ceiling and floor on prestige
  ask turtles [                            ; Nothing can exceed 1.0 or go below 0
    if prestige > 1 [ set prestige 1 ]
    if prestige < 0 [ set prestige 0 ]
  ]

; Step 8: update all tracking and classification
  update-stats                                      ; Stats update first so everything else reads current values.
  track-turnover
  check-fossilization
  track-h1-diffusion

  if shocked-agent-who != -1 [ log-shocked-agent-recovery ]

  if ticks mod 50 = 0 [ classify-regime ]            ; Regime classification only runs every 50 ticks

; Step 9: Update plots and layout
  tick

  update-prestige-plot                              ;

  if ticks mod 20 = 0 [
    layout-spring turtles links 0.5 10 1.0
  ]

  ask turtles [ update-appearance ]
end

; =============================================================
; NEIGHBOR FRACTIONS
; =============================================================

to update-neighbor-fracs
  let nb link-neighbors
  ifelse any? nb [
    set frac-conform  count nb with [signal = "conform"]       / count nb
    set frac-signal   count nb with [signal = "signal"]        / count nb
    set frac-counter  count nb with [signal = "countersignal"] / count nb
  ] [
    set frac-conform 0
    set frac-signal  0
    set frac-counter 0
  ]
end

; =============================================================
; POPULATION MODAL SIGNAL
; =============================================================

to-report compute-pop-modal
  let host-agents turtles with [status-tier != "stranger"]
  if not any? host-agents [ report "conform" ]
  let nc count host-agents with [signal = "conform"]
  let ns count host-agents with [signal = "signal"]
  let nk count host-agents with [signal = "countersignal"]
  ifelse (nc >= ns and nc >= nk)
    [ report "conform" ]
    [ ifelse (ns >= nk)
      [ report "signal" ]
      [ report "countersignal" ]
    ]
end

; =============================================================
; EVALUATE
; tier differentiation emerges from the credibility gate:
;   Elite agents have higher prestige --> higher VIS scores
;   Elite agents have consistent histories --> higher CON scores
;   Elite agents cluster culturally --> higher SIM with observers
; These structural advantages produce higher credibility scores
; which produce higher prestige rewards through the gate alone
;
; Strangers evaluated identically to known actors
; They start with CON = 0 so categorical prior provides floor
; As they accumulate history, CON grows and full formula activates
; =============================================================

to evaluate
  ; deviation measured against host population modal
  ; strangers deviating from host modal register as deviants
  set deviation-score ifelse-value (signal != pop-modal-signal) [1] [0]
  ; If it doesn't match, deviation-score is 1 & full credibility evaluation runs
  ; If it matches, deviation-score is 0 and only the conformer reward applies.

  ; --- NEW: advance cooldown counter for any agent previously reappraised ---
  if ticks-since-reappraisal >= 0 [
    set ticks-since-reappraisal ticks-since-reappraisal + 1
  ]

  ifelse deviation-score = 0 [
    ; CONFORMER: exempt from decay
    ; undoes the decay that already ran in Step 4 for conforming agents
    ; conformers hold their position rather than accumulating prestige
    ; theoretically grounded in Ridgeway status maintenance logic:
    ; conformity maintains standing, it does not build it
    set prestige prestige / (1 - PRESTIGE-DECAY)

  ] [
    ; DEVIATOR: full credibility evaluation
    let scores []                                     ; For deviators,
    ask link-neighbors [                              ; each neighbor independently decides whether to
      if random-float 1 < OBSERVATION-PROBABILITY [   ; observe based on OBSERVATION-PROBABILITY.
        let s [compute-credibility self] of myself    ; Those who observe compute a credibility score
        set scores lput s scores                      ; for the deviating agent and add it to the scores list
      ]
    ]

    ; computes categorical prior floor
    ; The agent's credibility score is whichever is higher: the mean of observer scores or the categorical prior.
    ; For agents with empty history the prior is their only credibility source.
    ; For warm-started agents the full formula almost always dominates.
    let cat-prior compute-categorical-prior

    set credibility-score ifelse-value (length scores > 0)
      [ max (list (mean scores) cat-prior) ]
      [ cat-prior ]

    ; --- H3 diagnostic logging: host agents only ---
    if status-tier != "stranger" [
      let this-host self
      let my-vis ifelse-value (any? link-neighbors and max [prestige] of turtles > 0)
        [mean [prestige] of link-neighbors / max [prestige] of turtles]
        [0]
      let my-sim ifelse-value (any? link-neighbors)
        [mean [compute-sim-only self this-host] of link-neighbors]
        [0]
      set host-dev-vis-log lput my-vis host-dev-vis-log
      set host-dev-sim-log lput my-sim host-dev-sim-log
      set host-dev-cred-log lput credibility-score host-dev-cred-log
      if my-vis > 0.90 [
        set high-vis-host-sim-log lput my-sim high-vis-host-sim-log
      ]
    ]
       ; --- NEW: log SIM for every deviator, not just reappraised ones, as the H3 comparison baseline ---
    let my-sim-baseline mean [item 0 (list (compute-sim-only self myself))] of link-neighbors
    set deviator-sim-log lput my-sim-baseline deviator-sim-log

    ; reappraisal trigger (both conditions simultaneously)
    let vis-score ifelse-value (any? link-neighbors and max [prestige] of turtles > 0) [        ; The audience watching must be high prestige,
      mean [prestige] of link-neighbors / max [prestige] of turtles                             ; and the credibility score must be very low.
    ] [0]

    if (vis-score > REAPPRAISAL-VISIBILITY and
    credibility-score < REAPPRAISAL-CREDIBILITY and
    (ticks-since-reappraisal = -1 or ticks-since-reappraisal >= OBSERVATION-WINDOW)) [

      ; log mean SIM to neighbors at moment of collapse, for H3 asymmetry test
      let my-sim mean [item 0 (list (compute-sim-only self myself))] of link-neighbors
      set reappraisal-sim-log lput my-sim reappraisal-sim-log
      set reappraisal-who-log lput (list who status-tier) reappraisal-who-log
      set reappraisal-count reappraisal-count + 1
      set ticks-since-reappraisal 0                              ; --- reset cooldown clock so it can expire and re-trigger correctly ---

      set prestige prestige * 0.1                                ;  If both hold, prestige is multiplied by 0.1 (a near-total collapse)
      set signal-history []                                      ;  history is wiped, and the procedure stops.
      set switched-this-tick? true                               ; This is the cancel culture condition.

      stop

    ]
    ; prestige gate- selective trust mechanism
    ; rewards and penalties uniform across tiers
    ; tier differentiation emerges from credibility scores
    ifelse credibility-score >= SELECTIVE-TRUST-THRESHOLD [           ; If reappraisal didn't trigger, the prestige gate runs.
                                                                      ; If credibility score clears the threshold the deviation is credited
      let base-reward DEVIATION-REWARD                                ; and the agent earns the deviation reward.

      ; rarity bonus (H2 mechanism)
      ; countersignaling when rare produces more information
      ; bonus disappears at saturation- prestige advantage collapses
      if signal = "countersignal" [
        let frac-counter-pop count turtles with [signal = "countersignal"] / count turtles
        if frac-counter-pop < SATURATION-THRESHOLD [
          set base-reward base-reward * 1.5                ; If countersignalers are still below the saturation threshold the reward is multiplied by 1.5.
        ]
      ]

      ; institutional enforcement/ Condition 3
      if signal = "countersignal" [                       ; countersignalers face a probability of being penalized by institutional pressure each tick
        if random-float 1 < INSTITUTIONAL-ENFORCEMENT [     ; penalty subtracts the base reward, effectively canceling the gain.
          set base-reward base-reward - DEVIATION-REWARD    ; Used in Condition 3 to test norm erosion thresholds.
        ]
      ]

      set prestige prestige + base-reward
      set switched-this-tick? true

    ] [
      ; failed deviation/ uniform penalty
      set prestige prestige - DEVIATION-PENALTY            ; If credibility score does not clear the threshold
    ]                                                       ; the deviation fails and the agent loses the deviation penalty.
  ]


end

; =============================================================
; CREDIBILITY SCORE:  MULTIPLICATIVE FORMULA
; Proposal section 3.4
;
; CON: consistency of current signal in recent history
;      warm-started agents have full CON from tick 1
;      strangers have CON = 0 until history accumulates
;      An agent whose history was just wiped by reappraisal has CON = 0
; VIS: Visibility. emitter prestige normalized by population max
;      high-prestige actors attract more legitimating attention
; SIM: cultural Similarity. vector overlap, Axelrod operationalization
;      mismatch raises credibility bar for cross-category actors
; =============================================================

to-report compute-credibility [observer-agent]
  ; --- CON ---
  let con-raw ifelse-value (length signal-history > 0) [                     ; Counts how many entries in signal history match
    length filter [s -> s = signal] signal-history / length signal-history   ; the current signal and divides by total history length.
  ] [0]

; --- VIS ---
; Produces a value between 0 and 1 representing where the observer sits in the current prestige distribution.
; high-prestige observers carry more legitimating force
; relative standing matters, not absolute prestige value

  let max-p max [prestige] of turtles
  let vis-raw ifelse-value (max-p > 0) [
    [prestige] of observer-agent / max-p      ; The observing agent's prestige divided by the highest prestige in the population
  ] [0]


  ; --- SIM ---
  let actor-vec cultural-vector                     ; Compares actor and observer cultural vectors feature by feature and counts matches.
  let obs-vec [cultural-vector] of observer-agent
  let matches 0
  foreach range 5 [ i ->
    if item i actor-vec = item i obs-vec [
      set matches matches + 1
    ]
  ]
  let sim-raw matches / 5                                                   ; Divides by 5 to get a proportion.
  let mismatch-val (5 - matches) / 5                                        ; Computes mismatch as the proportion of non-matching features.
  let multiplier max (list 0 (1 - (mismatch-val * MISMATCH-SENSITIVITY)))   ; The multiplier scales down the SIM contribution based on mismatch
                                                                           ; higher MISMATCH-SENSITIVITY raises the credibility bar more steeply
  ; --- MULTIPLICATIVE SCORE ---                                            ; for culturally distant pairs.
  let score (CONSISTENCY-WEIGHT * con-raw) *
            (VISIBILITY-WEIGHT  * vis-raw) *                  ; Multiplies all three weighted components together and returns the score.
            (SIMILARITY-WEIGHT  * sim-raw * multiplier)        ;  zero on any single component produces zero overall
                                                              ;  all three must contribute for a deviation to succeed.
  report score
end

to-report compute-sim-only [actor-agent observer-agent]
  let actor-vec [cultural-vector] of actor-agent
  let obs-vec [cultural-vector] of observer-agent
  let matches 0
  foreach range 5 [ i ->
    if item i actor-vec = item i obs-vec [ set matches matches + 1 ]
  ]
  report matches / 5
end

; behaviorspace/ diagnose/ vis-sim-correlation
to-report high-vis-host-sim-mean
  report ifelse-value (length high-vis-host-sim-log > 0) [mean high-vis-host-sim-log] [-1]
end

to-report high-vis-host-sim-min
  report ifelse-value (length high-vis-host-sim-log > 0) [min high-vis-host-sim-log] [-1]
end

to-report high-vis-host-sim-max
  report ifelse-value (length high-vis-host-sim-log > 0) [max high-vis-host-sim-log] [-1]
end

to-report high-vis-host-n
  report length high-vis-host-sim-log
end

; behaviorspace/ diagnose/dev-vis correlation

to-report host-dev-cred-min
  report ifelse-value (length host-dev-cred-log > 0) [min host-dev-cred-log] [-1]
end

to-report host-dev-vis-max
  report ifelse-value (length host-dev-vis-log > 0) [max host-dev-vis-log] [-1]
end

to-report host-dev-vis-mean
  report ifelse-value (length host-dev-vis-log > 0) [mean host-dev-vis-log] [-1]
end

; =============================================================
; CATEGORICAL PRIOR
; Prior = CATEGORICAL-PRIOR-SCALAR * SIM * Multiplier * VIS
; Floor for zero-history actors.
; Strangers with lower SIM get lower prior — higher effective bar.
; =============================================================

to-report compute-categorical-prior
  ifelse any? link-neighbors [                     ; Checks whether the agent has any neighbors to evaluate from. If not returns 0.
    let sim-vals []
    let vis-vals []
    let max-p max [prestige] of turtles
    ask link-neighbors [
      let actor-vec [cultural-vector] of myself
      let obs-vec cultural-vector
      let m 0
      foreach range 5 [ ii ->
        if item ii actor-vec = item ii obs-vec [
          set m m + 1
        ]
      ]
      let s m / 5                                       ; For each neighbor computes the SIM score
      let mis (5 - m) / 5
      let mult max (list 0 (1 - (mis * MISMATCH-SENSITIVITY)))     ; with mismatch multiplier
      set sim-vals lput (s * mult) sim-vals
      let v ifelse-value (max-p > 0) [prestige / max-p] [0]        ; and the normalized VIS score. Collects these into lists.
      set vis-vals lput v vis-vals
    ]
    report CATEGORICAL-PRIOR-SCALAR * mean sim-vals * mean vis-vals    ; Returns the prior scalar times avg SIM times avg VIS.
  ] [                                                                  ; For a stranger with low cultural similarity this produces a low floor
    report 0                                                           ; Ridgeway's expectation states theory when no individual history exists,
  ]                                                                    ; audiences evaluate through categorical assumptions about who the actor appears to be.
end

; =============================================================
; CREDIBILITY BUFFER
; Distance between current prestige and reappraisal trigger.
; =============================================================

to-report credibility-buffer
  let max-p max [prestige] of turtles
  let min-p min [prestige] of turtles
  let norm-pos (prestige - min-p) / (max-p - min-p + 0.0001)
  report norm-pos - REAPPRAISAL-CREDIBILITY
end

; =============================================================
; PRESTIGE NORMALIZATION
; =============================================================

to normalize-prestige
  let max-p max [prestige] of turtles
  let min-p min [prestige] of turtles
  let range-p max-p - min-p
  ask turtles [
    set prestige (prestige - min-p) / (range-p + 0.0001)
  ]
end

; =============================================================
; PRESTIGE PLOT
; Pen names: Elite, Subculture, Institutional, Stranger
; All pen update commands blank in editor.
; Y min 0, Y max 1
; =============================================================

to update-prestige-plot
  set-current-plot "Prestige by Tier"

  set-current-plot-pen "Elite"
  if any? turtles with [status-tier = "elite"] [
    plot mean [prestige] of turtles with [status-tier = "elite"]
  ]

  set-current-plot-pen "Subculture"
  if any? turtles with [status-tier = "subculture"] [
    plot mean [prestige] of turtles with [status-tier = "subculture"]
  ]

  set-current-plot-pen "Institutional"
  if any? turtles with [status-tier = "institutional"] [
    plot mean [prestige] of turtles with [status-tier = "institutional"]
  ]

  set-current-plot-pen "Stranger"
  ifelse any? turtles with [status-tier = "stranger"]
    [ plot mean [prestige] of turtles with [status-tier = "stranger"] ]
    [ plot 0 ]
end

; =============================================================
; H1 DIFFUSION TRACKING
; =============================================================

to track-h1-diffusion
  let sub-counters count turtles with [
    status-tier = "subculture" and signal = "countersignal"]
  let sub-total count turtles with [status-tier = "subculture"]
  let elite-counters count turtles with [
    status-tier = "elite" and signal = "countersignal"]
  let elite-total count turtles with [status-tier = "elite"]

  ; tick guard prevents initialization noise from triggering the check before real diffusion dynamics have had time to develop.
  ; only once- when subculture-first-adopted-tick is still unset & past tick 50 & subculture countersignal share reaches 7%,
  ; records the current tick.
  if subculture-first-adopted-tick = -1 [                                       ;
    if ticks > 150 and sub-total > 0 and (sub-counters / sub-total) >= 0.07 [
      set subculture-first-adopted-tick ticks
    ]
  ]

  ; Same logic for elite at an 8% threshold.
  ; Elite threshold is slightly higher than subculture because elite agents start with higher prestige
  ; and their early-tick countersignal share is more volatile.
  if elite-adopted-tick = -1 [
    if ticks > 150 and elite-total > 0 and (elite-counters / elite-total) >= 0.08 [
      set elite-adopted-tick ticks
    ]
  ]
end

; =============================================================
; APPEARANCE
; =============================================================

to update-appearance
  if signal = "conform"       [ set color green ]
  if signal = "signal"        [ set color blue  ]
  if signal = "countersignal" [ set color red   ]

  if status-tier = "elite"         [ set shape "circle"   ]
  if status-tier = "subculture"    [ set shape "square"   ]
  if status-tier = "institutional" [ set shape "triangle" ]
  if status-tier = "stranger"      [ set shape "star"  ]

  set size 0.5 + prestige * 1.5

  ifelse SHOW-LABELS
    [ set label precision prestige 2 ]
    [ set label "" ]
end

; =============================================================
; STATS
; =============================================================

to update-stats
  set NUM-CONFORM       count turtles with [signal = "conform"]
  set NUM-SIGNAL        count turtles with [signal = "signal"]
  set NUM-COUNTERSIGNAL count turtles with [signal = "countersignal"]

  if any? turtles with [status-tier = "elite"] [
    set elite-mean-prestige
      mean [prestige] of turtles with [status-tier = "elite"]
  ]
  if any? turtles with [status-tier = "subculture"] [
    set subculture-mean-prestige
      mean [prestige] of turtles with [status-tier = "subculture"]
  ]
  if any? turtles with [status-tier = "institutional"] [
    set institutional-mean-prestige
      mean [prestige] of turtles with [status-tier = "institutional"]
  ]
  if any? turtles with [status-tier = "stranger"] [
    set stranger-mean-prestige
      mean [prestige] of turtles with [status-tier = "stranger"]
  ]
  if any? turtles with [status-tier != "stranger"] [
    set host-mean-prestige
      mean [prestige] of turtles with [status-tier != "stranger"]
  ]
end

to classify-regime
  let v variance [prestige] of turtles
  let s1 NUM-CONFORM / count turtles
  let s2 NUM-SIGNAL  / count turtles
  let s3 NUM-COUNTERSIGNAL / count turtles

  ; If prestige variance across all agents is very low everyone is roughly equal
  ; the mechanism is not producing meaningful stratification.
  ifelse v < 0.01 [
    set regime "egalitarian"
  ] [
   ; If variance is above threshold and at least one pair of signal-type shares differs
   ; by more than 15 percentage points the population is stratified
    ifelse (abs (s1 - s2) > 0.15 or abs (s2 - s3) > 0.15 or abs (s1 - s3) > 0.15) [
      set regime "stratified"
    ] [
    ; If all three signal shares are within 5 percentage points of each other
    ; the distribution is frozen
    ; stratification exists but signal type alone can't explain it.
    ; Anything in between is transitional, the population is moving between states.
      ifelse (abs (s1 - s2) < 0.05 and abs (s2 - s3) < 0.05 and abs (s1 - s3) < 0.05) [
        set regime "frozen"
      ] [
        set regime "transitional"
      ]
    ]
  ]
end

; =============================================================
; TURNOVER AND FOSSILIZATION
; =============================================================
; Finds whoever has the highest prestige this tick
; Measures whether the prestige hierarchy is stable or contested.
to track-turnover
  let current-top [who] of max-one-of turtles [prestige]
  ifelse top-id = -1                                      ; If top-id is still the unset sentinel records this agent as the first leader
    [ set top-id current-top ]
    [ if current-top != top-id [                           ; Otherwise checks whether the leader has changed
        set turnover-count turnover-count + 1              ;  if so increments turnover count and updates top-id.
        set top-id current-top
      ]
    ]
end

to check-fossilization
  ifelse turnover-count = 0
    [ set fossilize-streak fossilize-streak + 1 ]          ; If turnover count hasn't changed this tick the streak counter increments.
    [ set fossilize-streak 0 ]                            ;  If it has changed the streak resets to zero.
  if fossilize-streak >= fossilize-streak-threshold [    ; If the streak reaches the threshold the model flags itself as fossilized
    set fossilized? true                                ; the same agent has held top position for 50 consecutive ticks and the hierarchy has locked.
  ]
end

to check-repeat-offender
  let agent-id first remove-duplicates map [pair -> item 0 pair] reappraisal-who-log
  let a turtle agent-id
  ask a [
    print (word "Agent " who " tier: " status-tier)
    print (word "Cultural vector: " cultural-vector)
    let neighbor-sims []
    ask link-neighbors [
      let m 0
      foreach range 5 [ i ->
        if item i cultural-vector = item i [cultural-vector] of myself [
          set m m + 1
        ]
      ]
      set neighbor-sims lput (m / 5) neighbor-sims
    ]
    print (word "Mean SIM to neighbors: " precision (mean neighbor-sims) 3)
    print (word "Neighbor mean prestige: " precision (mean [prestige] of link-neighbors) 3)
  ]
end

; =============================================================
; SAFE MEAN REPORTERS FOR BEHAVIORSPACE
; Guard against mean [] runtime errors when a replication
; produces zero reappraisals or zero logged deviators.
; -1 used as sentinel (0 is a real, meaningful SIM value).
; =============================================================

to-report safe-mean-reappraisal-sim
  report ifelse-value (length reappraisal-sim-log > 0) [mean reappraisal-sim-log] [-1]
end

to-report safe-mean-deviator-sim
  report ifelse-value (length deviator-sim-log > 0) [mean deviator-sim-log] [-1]
end

to-report reappraisal-elite-n
  report length filter [pair -> item 1 pair = "elite"] reappraisal-who-log
end

to-report reappraisal-subculture-n
  report length filter [pair -> item 1 pair = "subculture"] reappraisal-who-log
end

to-report reappraisal-institutional-n
  report length filter [pair -> item 1 pair = "institutional"] reappraisal-who-log
end

to-report reappraisal-stranger-n
  report length filter [pair -> item 1 pair = "stranger"] reappraisal-who-log
end

; =============================================================
; DIAGNOSTICS
; =============================================================
;  calibration monitoring
; tick count, signal distribution, tier prestige means, deviator and conformer means,
; a sample credibility score against the threshold,
; H1 adoption ticks, regime classification, and history counts.

to diagnose
  print "=== CALIBRATION DIAGNOSTICS ==="
  print (word "Ticks: " ticks)
  print (word "Pop modal signal: " pop-modal-signal)
  print (word "Conform: " NUM-CONFORM " Signal: " NUM-SIGNAL " Counter: " NUM-COUNTERSIGNAL)
  print " "
  print (word "Elite mean prestige:         " precision elite-mean-prestige 3)
  print (word "Subculture mean prestige:    " precision subculture-mean-prestige 3)
  print (word "Institutional mean prestige: " precision institutional-mean-prestige 3)
  if any? turtles with [status-tier = "stranger"] [
    print (word "Stranger mean prestige:      " precision stranger-mean-prestige 3)
    print (word "Host mean prestige:          " precision host-mean-prestige 3)
  ]
  print " "
  print (word "Deviators: " count turtles with [deviation-score = 1])
  if any? turtles with [deviation-score = 1] [
    print (word "Deviator mean prestige:  "
      precision mean [prestige] of turtles with [deviation-score = 1] 3)
  ]
  if any? turtles with [deviation-score = 0] [
    print (word "Conformer mean prestige: "
      precision mean [prestige] of turtles with [deviation-score = 0] 3)
  ]
  print " "
  let sample-agent one-of turtles with [any? link-neighbors]
  if sample-agent != nobody [
    let sample-score [compute-credibility one-of link-neighbors] of sample-agent
    print (word "Sample credibility score: " precision sample-score 4)
    print (word "Threshold:                " SELECTIVE-TRUST-THRESHOLD)
    print (word "Score clears threshold:   " (sample-score >= SELECTIVE-TRUST-THRESHOLD))
  ]
  print " "
  ifelse subculture-first-adopted-tick = -1
  [ print "H1 subculture adoption tick: not reached" ]
  [ print (word "H1 subculture adoption tick: " subculture-first-adopted-tick) ]

  ifelse elite-adopted-tick = -1
  [ print "H1 elite adoption tick:      not reached" ]
  [ print (word "H1 elite adoption tick:      " elite-adopted-tick) ]

  print (word "Regime: " regime)
  print "==============================="
  print (word "Agents with empty history: "
  count turtles with [length signal-history = 0])
  print (word "Agents with full history: "
  count turtles with [length signal-history = OBSERVATION-WINDOW])

  let dev-agents turtles with [deviation-score = 1 and any? link-neighbors]
if any? dev-agents [
  let all-scores []
  ask dev-agents [
    let s [compute-credibility one-of link-neighbors] of self
    set all-scores lput s all-scores
  ]
  print (word "N deviators sampled: " length all-scores)
  print (word "Mean score: " precision (mean all-scores) 4)
  print (word "Min score:  " precision (min all-scores) 4)
  print (word "Max score:  " precision (max all-scores) 4)
  print (word "Fraction clearing threshold: "
    precision (length filter [s -> s >= SELECTIVE-TRUST-THRESHOLD] all-scores / length all-scores) 3)
]
   ; --- new VIS/credibility diagnostic for reappraisal troubleshooting ---
  let dev-agents2 turtles with [deviation-score = 1 and any? link-neighbors]
  if any? dev-agents2 [
    let vis-scores []
    let cred-scores []
    ask dev-agents2 [
      let vs ifelse-value (max [prestige] of turtles > 0) [
        mean [prestige] of link-neighbors / max [prestige] of turtles
      ] [0]
      set vis-scores lput vs vis-scores
      set cred-scores lput credibility-score cred-scores
    ]
    print (word "N deviators: " length vis-scores)
    print (word "Fraction with VIS > 0.90: "
      precision (length filter [v -> v > 0.90] vis-scores / length vis-scores) 3)
    print (word "Fraction with credibility < 0.003: "
      precision (length filter [c -> c < 0.003] cred-scores / length cred-scores) 3)
    print (word "Max VIS observed: " precision (max vis-scores) 3)
    print (word "Min credibility observed: " precision (min cred-scores) 4)
  ]
  ; --- H3 / reappraisal SIM check ---
  print " "
  print (word "Reappraisal count: " reappraisal-count)
  ifelse reappraisal-count > 0 [
    print (word "Mean SIM at reappraisal: " precision (mean reappraisal-sim-log) 3)
    print (word "Min SIM at reappraisal:  " precision (min reappraisal-sim-log) 3)
    print (word "Max SIM at reappraisal:  " precision (max reappraisal-sim-log) 3)
  ] [
    print "No reappraisals yet."
  ]
  ifelse length deviator-sim-log > 0 [
    print (word "Mean SIM across all deviators: " precision (mean deviator-sim-log) 3)
  ] [
    print "No deviator SIM data yet."
  ]
; --- which term is driving credibility-score: main formula or categorical prior? ---
  let dev-agents3 turtles with [deviation-score = 1 and any? link-neighbors]
  if any? dev-agents3 [
    let main-means []
    let priors []
    ask dev-agents3 [
      let s [compute-credibility one-of link-neighbors] of self
      set main-means lput s main-means
      let p compute-categorical-prior
      set priors lput p priors
    ]
    print (word "Mean main-formula score: " precision (mean main-means) 4)
    print (word "Mean categorical prior:  " precision (mean priors) 4)
    print (word "Max categorical prior:   " precision (max priors) 4)
    print (word "Fraction where prior > main formula: "
      precision (length filter [i -> item i priors > item i main-means] (n-values length priors [i -> i])
        / length priors) 3)
  ]
let hv-agents turtles with [
    deviation-score = 1 and any? link-neighbors and
    (mean [prestige] of link-neighbors / (max [prestige] of turtles + 0.00001)) > 0.90
  ]
  if any? hv-agents [
    let sim-list []
    ask hv-agents [
      let sv mean [item 0 (list (compute-sim-only self myself))] of link-neighbors
      set sim-list lput sv sim-list
    ]
    print (word "High-VIS deviator SIM values: " sim-list)
  ]

  ; --- credibility distribution among high-VIS deviators specifically ---
  let hv-agents2 turtles with [
    deviation-score = 1 and any? link-neighbors and
    (mean [prestige] of link-neighbors / (max [prestige] of turtles + 0.00001)) > 0.90
  ]
  if any? hv-agents2 [
    let cred-list []
    ask hv-agents2 [
      let s [compute-credibility one-of link-neighbors] of self
      set cred-list lput s cred-list
    ]
    let sorted-cred sort cred-list
    let n length sorted-cred
    print (word "N high-VIS deviators: " n)
    print (word "Sorted credibility scores: " sorted-cred)
    print (word "10th percentile (approx): " item (floor (n * 0.10)) sorted-cred)
    print (word "25th percentile (approx): " item (floor (n * 0.25)) sorted-cred)
    print (word "50th percentile (approx): " item (floor (n * 0.50)) sorted-cred)
    print (word "Unique agents reappraised: " length remove-duplicates reappraisal-who-log)
    print (word "Total reappraisal events: " length reappraisal-who-log)
  ]
ifelse length reappraisal-who-log > 0 [
  let repeat-agent first remove-duplicates reappraisal-who-log
  let hits length filter [w -> w = repeat-agent] reappraisal-who-log
  print (word "Agent " repeat-agent " was reappraised " hits " times")
] [
  print "No reappraisal events this run."
]

end



; =============================================================
; EXOGENOUS SHOCK — CANCEL CULTURE STRESS TEST
; Section 3.6 — exogenous implementation mode
; Targets the highest-prestige agent with sufficient signal
; history to ensure the reappraisal event has history to revise.
; Minimum consistency threshold: 80% of observation window
; filled with consistent signaling behavior.
; Fire manually via interface button after host population
; has established prestige differentiation — recommended
; minimum tick 100, after stranger arrival if enabled.
; Compare collapse trajectory against endogenous reappraisal
; events to test whether the mechanism operates equivalently
; regardless of how the triggering event arises.
; =============================================================

to trigger-exogenous-shock
  let min-history round (OBSERVATION-WINDOW * 0.80)

  ; target: highest prestige host agent with sufficient history
  ; sufficient history defined as 80% of observation window
  ; filled with consistent signaling — per thesis section 3.6
  let target max-one-of turtles with [
    status-tier != "stranger" and
    length signal-history >= min-history
  ] [prestige]

  ifelse target != nobody [
    ask target [
      set prestige prestige * 0.1
      set signal-history []
      set switched-this-tick? true
    ]
    print (word "Exogenous shock fired at tick " ticks)
    print (word "Target agent: " [who] of target)
    print (word "Target tier: " [status-tier] of target)
    print (word "Pre-shock prestige: " precision ([prestige] of target / 0.1) 3)
    print (word "Post-shock prestige: " precision [prestige] of target 3)
  ] [
    print "No eligible target — no agent has sufficient signal history."
    print (word "Minimum history required: " min-history " ticks")
    print "Wait for history to accumulate before firing shock."
  ]
end

; =============================================================
; CONTROLLED EXOGENOUS SHOCK — SIM-TARGETED
; Same collapse mechanic as trigger-exogenous-shock, but targets
; a host agent above or below the population's median SIM-to-
; neighbors, instead of just the highest-prestige agent.
; Lets H1-H3's SIM-dependent recovery claim be tested directly
; via a controlled trigger, since the endogenous reappraisal
; mechanism does not fire on host agents at current thresholds.
; =============================================================

to trigger-exogenous-shock-controlled [target-sim-level]
  let min-history round (OBSERVATION-WINDOW * 0.80)
  let eligible turtles with [
    status-tier != "stranger" and
    length signal-history >= min-history
  ]

  if not any? eligible [
    print "No eligible target."
    stop
  ]
let sims []
  ask eligible [
    let this-agent self
    let my-sim ifelse-value (any? link-neighbors)
      [mean [compute-sim-only self this-agent] of link-neighbors]
      [0]
    set sims lput (list who my-sim) sims
  ]
  let median-sim median map [pair -> item 1 pair] sims

  let target nobody
  ifelse target-sim-level = "high" [
    let candidates filter [pair -> item 1 pair >= median-sim] sims
    if not empty? candidates [
      let chosen one-of candidates
      set target turtle (item 0 chosen)
    ]
  ] [
    let candidates filter [pair -> item 1 pair >= median-sim] sims
    if not empty? candidates [
      let chosen one-of candidates
      set target turtle (item 0 chosen)
    ]
  ]

  ifelse target != nobody [
    let pre-prestige [prestige] of target
    let target-who [who] of target
    let target-tier [status-tier] of target
    let target-sim ifelse-value (any? [link-neighbors] of target)
      [mean [compute-sim-only self target] of [link-neighbors] of target]
      [0]

    ask target [
      set prestige prestige * 0.1
      set signal-history []
      set switched-this-tick? true
    ]

    print (word "EXOGENOUS SHOCK | tick=" ticks
      " who=" target-who " tier=" target-tier
      " sim-level=" target-sim-level " sim=" precision target-sim 3
      " pre=" precision pre-prestige 3
      " post=" precision (pre-prestige * 0.1) 3)

    set shocked-agent-who target-who
    set shocked-agent-tick ticks
  ] [
    print (word "No eligible " target-sim-level "-SIM target found.")
  ]
end

to log-shocked-agent-recovery
  if shocked-agent-who != -1 [
    let a turtle shocked-agent-who
    if a != nobody [
      let ticks-since ticks - shocked-agent-tick
      print (word "RECOVERY | ticks-since-shock=" ticks-since
        " prestige=" precision [prestige] of a 3)
    ]
  ]
end

to-report shocked-prestige
  report ifelse-value (shocked-agent-who != -1) [[prestige] of turtle shocked-agent-who] [-1]
end
to go-with-shock
  ifelse ticks < SHOCK-TICK [
    go
  ] [
    if ticks = SHOCK-TICK and shocked-agent-who = -1 [
      trigger-exogenous-shock-controlled SHOCK-SIM-LEVEL
    ]
    ifelse ticks < (SHOCK-TICK + RECOVERY-WINDOW) [
      go
    ] [
      stop
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
348
10
785
448
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

CHOOSER
12
67
150
112
NETWORK-TYPE
NETWORK-TYPE
"small-world" "scale-free"
0

SLIDER
12
132
184
165
NUM-AGENTS
NUM-AGENTS
100
1000
500.0
50
1
NIL
HORIZONTAL

SLIDER
12
168
236
201
SELECTIVE-TRUST-THRESHOLD
SELECTIVE-TRUST-THRESHOLD
.001
.9
0.008
.01
1
NIL
HORIZONTAL

SLIDER
11
206
203
239
REAPPRAISAL-VISIBILITY
REAPPRAISAL-VISIBILITY
0.5
.9
0.9
.01
1
NIL
HORIZONTAL

SLIDER
11
243
215
276
REAPPRAISAL-CREDIBILITY
REAPPRAISAL-CREDIBILITY
0.001
.4
0.003
.001
1
NIL
HORIZONTAL

SLIDER
10
283
182
316
PRESTIGE-DECAY
PRESTIGE-DECAY
0
.1
0.015
.001
1
NIL
HORIZONTAL

SLIDER
795
14
976
47
CONSISTENCY-WEIGHT
CONSISTENCY-WEIGHT
0.2
.5
0.5
.05
1
NIL
HORIZONTAL

SLIDER
795
59
967
92
VISIBILITY-WEIGHT
VISIBILITY-WEIGHT
0.3
.6
0.3
.05
1
NIL
HORIZONTAL

TEXTBOX
801
153
985
181
CON + VIS + SIM must sum to 1.0\n
11
0.0
1

SLIDER
799
107
971
140
SIMILARITY-WEIGHT
SIMILARITY-WEIGHT
0.1
.3
0.2
.05
1
NIL
HORIZONTAL

BUTTON
14
10
77
43
NIL
GO
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
88
10
155
43
NIL
Setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
254
96
343
141
Regime
regime
17
1
11

MONITOR
256
144
346
189
Conformists
NUM-CONFORM
17
1
11

MONITOR
254
191
345
236
Signalers
NUM-SIGNAL
17
1
11

MONITOR
255
239
348
284
Countersignalers
NUM-COUNTERSIGNAL
17
1
11

SWITCH
175
11
349
44
MOVEMENT-ENABLED
MOVEMENT-ENABLED
0
1
-1000

SWITCH
180
53
316
86
SHOW-LABELS
SHOW-LABELS
1
1
-1000

SLIDER
798
186
1015
219
OBSERVATION-WINDOW
OBSERVATION-WINDOW
5
50
10.0
5
1
ticks
HORIZONTAL

SLIDER
798
223
1009
256
OBSERVATION-PROBABILITY
OBSERVATION-PROBABILITY
.1
1
0.75
.1
1
NIL
HORIZONTAL

SLIDER
12
548
184
581
EPSILON
EPSILON
0
.2
0.001
.001
1
NIL
HORIZONTAL

PLOT
276
608
729
776
Prestige by Tier
NIL
NIL
0.0
500.0
0.0
1.0
true
true
"" ""
PENS
"Elite" 10.0 0 -10899396 true "" ""
"Subculture" 10.0 0 -955883 true "" ""
"Institutional" 10.0 0 -6459832 true "" ""
"Stranger" 10.0 0 -2064490 true "" ""

PLOT
275
455
536
605
Credibility Buffer by Tier
NIL
NIL
0.0
10.0
-0.5
1.0
true
true
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [credibility-buffer] of turtles"
"Elite" 1.0 0 -8630108 true "" "if any? turtles with [status-tier = \"elite\"] [ plot mean [credibility-buffer] of turtles with [status-tier = \"elite\"] ]"
"Subculture" 1.0 0 -955883 true "" "if any? turtles with [status-tier = \"subculture\"] [ plot mean [credibility-buffer] of turtles with [status-tier = \"subculture\"] ]"
"Institutional" 1.0 0 -6459832 true "" "if any? turtles with [status-tier = \"institutional\"] [ plot mean [credibility-buffer] of turtles with [status-tier = \"institutional\"] ]"
"Stranger" 1.0 0 -2064490 true "" "ifelse any? turtles with [status-tier = \"stranger\"] [ plot mean [credibility-buffer] of turtles with [status-tier = \"stranger\"] ] [ plot 0 ]"

PLOT
543
454
784
604
Signal Distribution
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Conform" 1.0 0 -10899396 true "" "plot NUM-CONFORM"
" Signal" 1.0 0 -8630108 true "" "plot NUM-SIGNAL"
"Countersignal" 1.0 0 -2674135 true "" "plot NUM-COUNTERSIGNAL"

SLIDER
10
323
207
356
SATURATION-THRESHOLD
SATURATION-THRESHOLD
0.1
.6
0.3
.01
1
NIL
HORIZONTAL

SLIDER
10
362
182
395
DEVIATION-REWARD
DEVIATION-REWARD
0.001
.1
0.01
.001
1
NIL
HORIZONTAL

SLIDER
9
402
181
435
DEVIATION-PENALTY
DEVIATION-PENALTY
.005
.05
0.039
.001
1
NIL
HORIZONTAL

SLIDER
796
407
1019
440
CATEGORICAL-PRIOR-SCALAR
CATEGORICAL-PRIOR-SCALAR
0.01
1
0.03
.001
1
NIL
HORIZONTAL

SLIDER
9
468
195
501
MISMATCH-SENSITIVITY
MISMATCH-SENSITIVITY
0
1.0
0.38
.005
1
NIL
HORIZONTAL

SLIDER
13
508
241
541
INSTITUTIONAL-ENFORCEMENT
INSTITUTIONAL-ENFORCEMENT
0
1
0.1
.005
1
NIL
HORIZONTAL

SLIDER
801
330
1025
363
STRANGER-VECTOR-DISTANCE
STRANGER-VECTOR-DISTANCE
0
5
0.0
1
1
NIL
HORIZONTAL

SLIDER
799
292
971
325
NUM-STRANGERS
NUM-STRANGERS
0
200
0.0
10
1
NIL
HORIZONTAL

SLIDER
797
370
993
403
STRANGER-ARRIVAL-TICK
STRANGER-ARRIVAL-TICK
0
500
0.0
10
1
NIL
HORIZONTAL

BUTTON
792
459
921
492
Exogenous Shock
trigger-exogenous-shock
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
14
591
143
624
ABLATE-SIM?
ABLATE-SIM?
1
1
-1000

BUTTON
792
501
1056
534
trigger-exogenous-shock-controlled "high"
NIL
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
791
540
1050
573
trigger-exogenous-shock-controlled "low"
NIL
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
796
600
968
633
SHOCK-TICK
SHOCK-TICK
0
2500
1000.0
1
1
NIL
HORIZONTAL

SLIDER
798
638
973
671
RECOVERY-WINDOW
RECOVERY-WINDOW
0
1000
500.0
1
1
NIL
HORIZONTAL

CHOOSER
805
677
943
722
SHOCK-SIM-LEVEL
SHOCK-SIM-LEVEL
"high" "low"
0

@#$#@#$#@
## WHAT IS IT?

Permission to Deviate: How Audiences Grant and Withdraw Prestige Through Selective Trust
Shannon Left | CSS | George Mason University | 2026

Does departure from the population norm read as earned?
Under what conditions does deviation confer prestige advantage?

Companion model for the paper of the same name.
Code and configs: https://github.com/irishgoodbye/selective-trust-abm



## HOW IT WORKS

FORMULA (multiplicative, conjunctive logic):
   Credibility = (CONSISTENCY-WEIGHT * CON) * (VISIBILITY-WEIGHT * VIS) * (SIMILARITY-WEIGHT * SIM * Multiplier)

   Categorical prior floor when CON = 0:
   Prior = CATEGORICAL-PRIOR-SCALAR * SIM * Multiplier * VIS
   Effective score = max(full score, prior)

   Zero on any single component eliminates credibility entirely.
   All three must contribute for a deviation to succeed.

WEIGHTS (free parameters in BehaviorSpace sweep, must sum to 1.0):
   Consistency: 0.50  prior signaling history, highest weight
   Visibility:  0.30  observer prestige normalized by population max
   Similarity:  0.20  cultural vector overlap, raises or lowers the bar

PRESTIGE:
   Clamped to [0,1] each tick.
   Deviating agents decay each tick — reputation requires maintenance.
   Conforming agents are exempt from decay — conformity holds standing,
   it does not build it. Relational standing captured through VIS
   normalization against population maximum.

WHAT DOES THE WORK:
   Tier differentiation emerges from the credibility gate alone —
   no manual multipliers. Elite agents start with higher prestige,
   which produces higher VIS scores, which produces higher credibility
   scores, which maintains higher prestige. The mechanism compounds
   starting advantages tick by tick.

AGENT TYPES AND SIGNAL INITIALIZATION:
   elite:         20%  highest prestige (0.70–0.80), clustered cultural vectors
                  ~3% countersignal at initialization
   subculture:    30%  intermediate prestige (0.55–0.65), partially distinct vectors
                  ~2% countersignal at initialization
   institutional: 50%  lowest prestige (0.25–0.35), dominant normative order
                  100% conform at initialization, no countersignal minority —
                  any institutional-tier deviation over a run is therefore
                  endogenous, not seeded
   stranger:      introduced mid-run at STRANGER-ARRIVAL-TICK
                  zero signal history, categorical prior only,
                  prestige ~0.30

   Host agents warm-started with full signal history — CON = 1.0 from tick 1.
   Countersignalers rare at initialization across all seeded tiers.
   Diffusion dynamics produce the adoption sequence H1 predicts.

SIGNAL TYPES:
   conform:       matches population majority — no credibility evaluation,
                  decay exemption applies
   signal:        visible conventional marker — evaluated if deviating
   countersignal: deliberate departure — high risk, high reward when it works,
                  1.5x rarity bonus when population share below saturation threshold

STRANGER MECHANISM:
   Strangers arrive with CON = 0. The full formula produces zero
   so the categorical prior takes over — a small credibility floor
   based on cultural similarity and observer prestige alone.
   This is Ridgeway's expectation states theory in practice:
   no individual history means audiences fall back on categorical
   assumptions about who the agent appears to be.
   As history accumulates, CON grows and the full formula displaces
   the prior. Strangers with lower cultural similarity face a higher
   bar and integrate more slowly.

   Diagnostic testing found this mechanism, at default thresholds,
   is the ONLY population the endogenous reappraisal trigger reaches —
   host agents with real signal history did not trigger it until
   REAPPRAISAL-CREDIBILITY was recalibrated (see Things to Try).

NETWORK:
   Watts-Strogatz small-world (primary): local clustering plus
   short path lengths. Subcultural recognition operates locally,
   elite signals travel broadly.
   Barabasi-Albert scale-free (Condition 2): preferential attachment
   produces hubs with disproportionate reach.

## HOW TO USE IT

1. Set NETWORK-TYPE: small-world for Conditions 1, 3, 4;
   scale-free for Condition 2.
2. Set NUM-AGENTS to 500 for standard conditions.
3. Set NUM-STRANGERS to 0 for standard H1–H3 results;
   set to 50 only to run the separate stranger-mechanism validation.
4. Press Setup then Go.
5. Use the Diagnose button at any tick to check calibration targets
   in the command center.
6. Two exogenous shock buttons are available:
   - Exogenous Shock: targets the single highest-prestige host agent
     with sufficient history. Use after tick 150.
   - Controlled Exogenous Shock (SIM-targeted): ranks eligible host
     agents by cultural similarity to their neighbors, splits at the
     population median into high-SIM / low-SIM groups, and targets
     a random agent from a specified group. This is the variant used
     to generate the paper's controlled-shock recovery results.
7. Run BehaviorSpace for full parameter sweeps across 50 replications.

## COMMAND CENTER CHECK

At any tick type in the command center:

"diagnose"

For a full snapshot of all key outputs


## THINGS TO NOTICE

- Tier hierarchy should hold across the full run:
  elite above subculture above institutional above stranger.
- Deviator mean prestige should exceed conformer mean prestige.
- Conformer prestige should hold steady, not accumulate upward.
- H1: subculture adoption tick should precede elite adoption tick
  in most replications (84% in the paper's reduced-reward condition).
- Signal distribution shifts as countersignaling spreads —
  watch counter share approach saturation threshold.
- Stranger prestige climbs slowly after tick 100 as CON builds.
- Regime monitor: reads "stratified" under default-parameter
  conditions. Under the reduced-reward condition (DEVIATION-REWARD
  = 0.010), the regime reads "frozen" by tick 2500 in the paper's
  validation runs — this is an expected, documented finding
  (the reward-saturation tradeoff), not a miscalibration.
- Host-agent reappraisal does not fire at default
  REAPPRAISAL-CREDIBILITY (0.003) — only zero-history agents trigger
  it at this threshold. See Things to Try for recalibration.

## THINGS TO TRY

- Raise MISMATCH-SENSITIVITY toward 1.0 — watch whether
  cross-category agent-observer pairs produce lower credibility
  scores and slower prestige accumulation.
- Set INSTITUTIONAL-ENFORCEMENT to 0: does countersignaling
  spread without penalty? This is the Condition 3 tipping point.
- Switch to scale-free network: compare collapse depth and
  recovery speed against small-world baseline.
- Fire the Controlled Exogenous Shock (SIM-targeted) on both a
  high-SIM and a low-SIM agent: do their recovery trajectories
  diverge, as in the paper's Fig. 3?
- Loosen REAPPRAISAL-CREDIBILITY from 0.003 toward 0.007 with
  NUM-STRANGERS = 0: at 0.007, the endogenous mechanism becomes
  reliably reachable — but only for institutional-tier agents,
  whose randomly-assigned cultural vectors make them the tier most
  likely to end up mismatched with their neighbors. Loosening
  further (toward 0.010) starts catching subculture agents too,
  diluting the effect — this is the reachability/specificity
  tradeoff reported in the paper's Fig. 2.
- Set NUM-STRANGERS to 0: how does removing strangers affect
  tier dynamics and reappraisal targeting?
- Set STRANGER-VECTOR-DISTANCE to 5: do maximally distant
  strangers integrate within 500 ticks?

## EXTENDING THE MODEL

- Evaluative schema: separate how observers evaluate signals from
  how culturally similar they are to the agent being evaluated.
  Currently the model assumes shared cultural background means
  shared evaluative standards. This extension would let an observer
  apply dominant-group criteria regardless of their own demographic
  position, capturing internalized-oppression dynamics.
- Discrete-state credibility: reformulate credibility as a small
  number of qualitatively distinct states (e.g., Goffman's
  discredited vs. merely discreditable) rather than one continuous
  score, so a single reappraisal event doesn't collapse the
  distinction into one instantaneous transition.
- Field-level norm structure: introduce a population-wide symbolic
  order that precedes dyadic evaluation (Bourdieu's field logic
  operating above the agent-observer level).
- Assimilation: model directional signal movement toward field norms
  as a distinct credibility strategy, separate from deviation.
- Dynamic cultural vectors: let vectors evolve through interaction
  following Axelrod's original model rather than staying fixed —
  this would let the model distinguish a transient cultural mismatch
  from a structural one.
- Strategic misrepresentation: allow agents to fake higher standing
  than they actually hold. Connects to passing and code-switching
  phenomena.
- Directed networks: asymmetric observation relationships,
  particularly relevant to scale-free hub dynamics.
- Recalibrating the endogenous reappraisal trigger to reach elite
  and subculture agents, not only institutional agents, without
  simply reproducing the zero-history pattern this version shows.

## NETLOGO FEATURES

- BehaviorSpace runs 50 replications per parameter combination.
  Output processed in Python via Jupyter Notebooks.
- Warm start via n-values pre-fills signal histories at initialization —
  eliminates cold start without a burn-in period.
- Multiplicative formula uses nested arithmetic so zero on any
  component eliminates the full score.
- Decay exemption for conformers implemented as prestige / (1 - PRESTIGE-DECAY)
  in the evaluate procedure, undoing that tick's decay for conforming agents.
- Regime classification every 50 ticks rather than every tick —
  reduces overhead at 500 agents.
- Categorical prior as max() floor: formula and prior are scaled to the
  same ceiling (CATEGORICAL-PRIOR-SCALAR = 0.03) so the comparison
  is meaningful. An earlier version scaled the prior to 0.25, roughly
  8x the main formula's ceiling, causing it to dominate credibility
  scores for nearly all deviating agents rather than only zero-history
  ones — corrected in validation (see paper Section 8).
- Reappraisal cooldown: an agent becomes eligible for reappraisal again
  only after OBSERVATION-WINDOW ticks since its last reappraisal. An
  earlier version had no cooldown, concentrating most reappraisal
  events onto one or two agents per run — corrected in validation.

## RELATED MODELS
RELATED MODELS
Axelrod (1997) Culture Model - NetLogo Models Library
Watts-Strogatz Small World - NetLogo Models Library

## Defaults

SELECTIVE-TRUST-THRESHOLD  0.008
PRESTIGE-DECAY             0.015
DEVIATION-REWARD           0.030 (default condition) / 0.010 (reduced-reward condition)
DEVIATION-PENALTY          0.039
REAPPRAISAL-VISIBILITY     0.90
REAPPRAISAL-CREDIBILITY    0.003 (default) / 0.007 (recalibrated, institutional-only reappraisal)
CATEGORICAL-PRIOR-SCALAR   0.03
CONSISTENCY-WEIGHT         0.50
VISIBILITY-WEIGHT          0.30
SIMILARITY-WEIGHT          0.20
OBSERVATION-WINDOW         10
OBSERVATION-PROBABILITY    0.75
MISMATCH-SENSITIVITY       0.380
SATURATION-THRESHOLD       0.50 (default condition) / 0.30 (reduced-reward condition)
INSTITUTIONAL-ENFORCEMENT  0.10
EPSILON                    0.001
NUM-STRANGERS              0 (main results) / 50 (stranger-mechanism validation)
STRANGER-ARRIVAL-TICK      100
STRANGER-VECTOR-DISTANCE   2


## CREDITS AND REFERENCES

Shannon Left
Computational Social Science
College of Science
George Mason University
2026

Axelrod, R. (1997). The dissemination of culture.
  Journal of Conflict Resolution, 41(2), 203-226.
Feltovich, N., Harbaugh, R., and To, T. (2002). Too cool for school?
  RAND Journal of Economics, 33(4), 630-649.
Henrich, J. and Gil-White, F. J. (2001). The evolution of prestige.
  Evolution and Human Behavior, 22(3), 165-196.
Ridgeway, C. L. (2014). Why status matters for inequality.
  American Sociological Review, 79(1), 1-16.
Watts, D. J. and Strogatz, S. H. (1998). Collective dynamics of
  small-world networks. Nature, 393(6684), 440-442.
Grimm, V. et al. (2010). The ODD protocol.
  Ecological Modelling, 221(23), 2760-2768.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Condition1_Baseline" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
  </experiment>
  <experiment name="Condition1_H3_Rerun" repetitions="30" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>reappraisal-count</metric>
    <metric>(ifelse-value (length reappraisal-who-log &gt; 0) [length remove-duplicates reappraisal-who-log] [0])</metric>
    <metric>(ifelse-value (length reappraisal-sim-log &gt; 0) [mean reappraisal-sim-log] [-1])</metric>
    <metric>(ifelse-value (length deviator-sim-log &gt; 0) [mean deviator-sim-log] [-1])</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>stranger-mean-prestige</metric>
    <metric>regime</metric>
  </experiment>
  <experiment name="ReappraisalCredibility_Sweep" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>REAPPRAISAL-CREDIBILITY</metric>
    <metric>reappraisal-count</metric>
    <metric>(ifelse-value (length reappraisal-who-log &gt; 0) [length remove-duplicates reappraisal-who-log] [0])</metric>
    <enumeratedValueSet variable="REAPPRAISAL-CREDIBILITY">
      <value value="0.003"/>
      <value value="0.002"/>
      <value value="0.011"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Condition1_Final_Validation_3000" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="3000"/>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>stranger-mean-prestige</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
    <metric>reappraisal-count</metric>
    <metric>(ifelse-value (length reappraisal-who-log &gt; 0) [length remove-duplicates reappraisal-who-log] [0])</metric>
    <metric>(ifelse-value (length reappraisal-sim-log &gt; 0) [mean reappraisal-sim-log] [-1])</metric>
    <metric>(ifelse-value (length deviator-sim-log &gt; 0) [mean deviator-sim-log] [-1])</metric>
  </experiment>
  <experiment name="SaturationDynamics_Sweep" repetitions="3" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>SATURATION-THRESHOLD</metric>
    <metric>PRESTIGE-DECAY</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <enumeratedValueSet variable="SATURATION-THRESHOLD">
      <value value="0.2"/>
      <value value="0.1"/>
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="PRESTIGE-DECAY">
      <value value="0.015"/>
      <value value="0.01"/>
      <value value="0.045"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEVIATION-REWARD">
      <value value="0.02"/>
      <value value="0.01"/>
      <value value="0.04"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="DeviationReward_Pilot" repetitions="3" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>DEVIATION-REWARD</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <enumeratedValueSet variable="DEVIATION-REWARD">
      <value value="0.01"/>
      <value value="0.01"/>
      <value value="0.03"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Condition1_Final_Validation_H2Fix" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>stranger-mean-prestige</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
    <metric>reappraisal-count</metric>
    <metric>(ifelse-value (length reappraisal-who-log &gt; 0) [length remove-duplicates reappraisal-who-log] [0])</metric>
    <metric>(ifelse-value (length reappraisal-sim-log &gt; 0) [mean reappraisal-sim-log] [-1])</metric>
    <metric>(ifelse-value (length deviator-sim-log &gt; 0) [mean deviator-sim-log] [-1])</metric>
  </experiment>
  <experiment name="H3-reappraisal-tier-SIM-ablation" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>NUM-CONFORM</metric>
    <metric>NUM-SIGNAL</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>stranger-mean-prestige</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
    <metric>reappraisal-count</metric>
    <metric>(ifelse-value (length reappraisal-who-log &gt; 0) [length remove-duplicates reappraisal-who-log] [0])</metric>
    <metric>safe-mean-reappraisal-sim</metric>
    <metric>safe-mean-deviator-sim</metric>
    <metric>reappraisal-elite-n</metric>
    <metric>reappraisal-subculture-n</metric>
    <metric>reappraisal-institutional-n</metric>
    <metric>reappraisal-stranger-n</metric>
  </experiment>
  <experiment name="H3-stranger-confound-check" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>reappraisal-count</metric>
    <metric>reappraisal-elite-n</metric>
    <metric>reappraisal-subculture-n</metric>
    <metric>reappraisal-institutional-n</metric>
    <metric>reappraisal-stranger-n</metric>
    <metric>safe-mean-reappraisal-sim</metric>
    <metric>safe-mean-deviator-sim</metric>
    <enumeratedValueSet variable="NUM-STRANGERS">
      <value value="0"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="H3-controlled-shock-recovery" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go-with-shock</go>
    <metric>shocked-agent-who</metric>
    <metric>ticks - shocked-agent-tick</metric>
    <metric>shocked-prestige</metric>
    <enumeratedValueSet variable="SHOCK-SIM-LEVEL">
      <value value="&quot;high&quot;"/>
      <value value="&quot;low&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="H1-H2-reduced-clean-nostrangers" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
  </experiment>
  <experiment name="H1-H2-default-clean-nostrangers" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
  </experiment>
  <experiment name="H1-H2-default-clean-full-reporters" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="500"/>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>regime</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
  </experiment>
  <experiment name="H2-regime-confirmation" repetitions="50" sequentialRunOrder="false" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>elite-mean-prestige</metric>
    <metric>subculture-mean-prestige</metric>
    <metric>institutional-mean-prestige</metric>
    <metric>NUM-COUNTERSIGNAL</metric>
    <metric>subculture-first-adopted-tick</metric>
    <metric>elite-adopted-tick</metric>
    <metric>regime</metric>
  </experiment>
  <experiment name="H3-vis-sim-correlation-diagnostic" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>high-vis-host-sim-mean</metric>
    <metric>high-vis-host-sim-min</metric>
    <metric>high-vis-host-sim-max</metric>
    <metric>high-vis-host-n</metric>
    <metric>host-dev-cred-min</metric>
    <enumeratedValueSet variable="NUM-STRANGERS">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="REAPPRAISAL-VISIBILITY">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEVIATION-REWARD">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SATURATION-THRESHOLD">
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="REAPPRAISAL-CREDIBILITY">
      <value value="0.003"/>
      <value value="0.007"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="H3-reappraisal-threshold-sweep" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>reappraisal-count</metric>
    <metric>reappraisal-elite-n</metric>
    <metric>reappraisal-subculture-n</metric>
    <metric>reappraisal-institutional-n</metric>
    <metric>reappraisal-stranger-n</metric>
    <metric>safe-mean-reappraisal-sim</metric>
    <metric>safe-mean-deviator-sim</metric>
    <enumeratedValueSet variable="REAPPRAISAL-CREDIBILITY">
      <value value="0.003"/>
      <value value="0.007"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="H3-host-vis-ceiling" repetitions="20" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>host-dev-vis-max</metric>
    <metric>host-dev-vis-mean</metric>
    <metric>host-dev-cred-min</metric>
    <enumeratedValueSet variable="NUM-STRANGERS">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="REAPPRAISAL-VISIBILITY">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="REAPPRAISAL-CREDIBILITY">
      <value value="0.003"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEVIATION-REWARD">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SATURATION-THRESHOLD">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="H3-reappraisal-threshold-sweep-final" repetitions="30" sequentialRunOrder="false" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="2500"/>
    <metric>reappraisal-count</metric>
    <metric>reappraisal-elite-n</metric>
    <metric>reappraisal-subculture-n</metric>
    <metric>reappraisal-institutional-n</metric>
    <metric>reappraisal-stranger-n</metric>
    <metric>safe-mean-reappraisal-sim</metric>
    <metric>safe-mean-deviator-sim</metric>
    <enumeratedValueSet variable="REAPPRAISAL-CREDIBILITY">
      <value value="0.003"/>
      <value value="0.005"/>
      <value value="0.007"/>
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="NUM-STRANGERS">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="REAPPRAISAL-VISIBILITY">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEVIATION-REWARD">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="SATURATION-THRESHOLD">
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
