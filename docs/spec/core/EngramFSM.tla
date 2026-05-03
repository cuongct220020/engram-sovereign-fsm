--------------------------- MODULE EngramFSM ---------------------------
(*
 * EngramFSM — Circuit-Breaker Finite State Machine
 *
 * Models the 4-state circuit breaker (ANCHORED -> SUSPICIOUS -> SOVEREIGN ->
 * RECOVERING -> ANCHORED) driven by three environment sensors: Bitcoin SPV
 * gap, DA availability, and P2P network quality.
 *
 * Depends on: EngramVars (variables), Integers, FiniteSets
 *)

EXTENDS Integers, FiniteSets, EngramVars

(* ======================== CONSTANTS & ASSUMPTIONS ========================= *)
CONSTANTS
    T_SUSPICIOUS,           \* BTC gap threshold for Gray Failure warning
    T_SOVEREIGN,            \* BTC gap threshold for Hard Failure (circuit-break)
    MIN_PEERS,              \* Minimum clean peers required to avoid isolation
    MIN_SUBNET_DIVERSITY,   \* Minimum distinct subnets required
    MIN_ANCHOR_PEERS        \* Minimum active anchor/bootstrap peers required

ASSUME
    /\ T_SUSPICIOUS      \in Nat
    /\ T_SOVEREIGN       \in Nat
    /\ T_DA              \in Nat
    /\ HYSTERESIS_WAIT   \in Nat
    /\ MIN_PEERS         \in Nat
    /\ MIN_SUBNET_DIVERSITY \in Nat
    /\ MIN_ANCHOR_PEERS  \in Nat
    /\ T_SUSPICIOUS < T_SOVEREIGN


(* ======================== DERIVED SENSOR GAPS ============================= *)
\* Helper: returns the smaller of two integers
MinVal(a, b) == IF a < b THEN a ELSE b

\* Bitcoin settlement gap: distance from current tip to last confirmed anchor
btc_gap == h_btc_current - MinVal(h_btc_submitted, h_btc_anchored)

\* Data Availability gap: unverified Engram blocks since last DA proof
da_gap == h_engram_current - h_engram_verified


(* ======================== P2P QUALITY SENSOR ============================== *)
\* Map virtual peer IDs to /24 subnets so TLC can compute SubnetDiversity.
\* Extend this CASE table to add new peer scenarios.
SubnetOf(p) ==
    CASE p = "anchor_n1"                             -> "subnet_A"
      [] p = "anchor_n2"                             -> "subnet_B"
      [] p = "anchor_n3"                             -> "subnet_C"
      [] p \in {"sybil_n1", "sybil_n2", "sybil_n3"}  -> "subnet_malicious"
      [] OTHER                                       -> "unknown_subnet"

\* Number of distinct subnets represented in active_peers
SubnetDiversity == Cardinality({SubnetOf(p) : p \in active_peers})

\* Subset of anchor_peers that are currently active
ActiveAnchors == active_peers \intersect anchor_peers

\* Active peers that have not been blacklisted
CleanPeers == active_peers \ blacklisted_peers

\* Composite P2P health predicate
IsP2PQualityHealthy ==
    /\ SubnetDiversity             >= MIN_SUBNET_DIVERSITY  \* Not concentrated on a single IP block
    /\ Cardinality(ActiveAnchors)  >= MIN_ANCHOR_PEERS      \* Maintains connection with root nodes
    /\ Cardinality(CleanPeers)     >= MIN_PEERS             \* Sufficient non-malicious peers


(* ======================== HEALTH CONDITION PREDICATES ===================== *)\* Withdrawal guard: TRUE whenever cross-chain withdrawals must be halted
WithdrawLocked == state \in {"SOVEREIGN", "RECOVERING"}

\* DA layer is publishing proofs within the allowed gap
IsDAHealthy == (da_gap < T_DA) /\ ~is_das_failed

\* Hard failure: BTC gap has crossed the sovereign threshold
IsCriticalCondition == btc_gap >= T_SOVEREIGN

\* Soft warning: BTC gap is elevated, or DA/P2P shows degradation
IsWarningCondition ==
    \/ (T_SUSPICIOUS <= btc_gap /\ btc_gap < T_SOVEREIGN)
    \/ ~IsDAHealthy
    \/ ~IsP2PQualityHealthy

\* All sensors are green and thresholds are satisfied
IsHealthyCondition ==
    /\ btc_gap < T_SUSPICIOUS
    /\ IsDAHealthy
    /\ IsP2PQualityHealthy

(* ======================== TYPE INVARIANT & SANITY CHECK ================================== *)
TypeInvariant == 
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
    /\ btc_gap >= 0
    /\ da_gap >= 0
    /\ is_das_failed \in BOOLEAN
    /\ IsFiniteSet(active_peers)
    /\ IsFiniteSet(anchor_peers)
    /\ IsFiniteSet(blacklisted_peers)
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ reanchoring_proof_valid \in BOOLEAN


\* SanityCheck: a deliberately-failing invariant used during TLC exploration
\* to confirm the system can reach RECOVERING (i.e., it does NOT freeze there).
SanityCheck == state /= "RECOVERING"


(* ======================== STATE MACHINE INITIALIZATION ================================== *)
FSM_Init == 
    /\ state = "ANCHORED"
    /\ h_btc_current = 0
    /\ h_btc_submitted = 0
    /\ h_btc_anchored = 0
    /\ h_engram_current = 0
    /\ h_engram_verified = 0
    /\ is_das_failed = FALSE
    /\ anchor_peers = {"anchor_n1", "anchor_n2", "anchor_n3"}
    /\ active_peers = anchor_peers
    /\ blacklisted_peers = {}
    /\ safe_blocks = 0
    /\ reanchoring_proof_valid = FALSE


(* ======================== ENVIRONMENT SENSOR UPDATE ======================= *)
\* Non-deterministic environment update that simulates the real network.
\* Heights are monotonically non-decreasing; P2P state picks one of 4 scenarios.
UpdateSensors ==
    \* -- Bitcoin heights (monotone) --
    /\ h_btc_current'   \in {h_btc_current,   h_btc_current + 1}
    /\ h_btc_submitted' \in {h_btc_submitted,  h_btc_current'}
    /\ h_btc_anchored'  \in {h_btc_anchored,   h_btc_submitted'}

    \* -- Engram DA heights (monotone) --
    /\ h_engram_current'  \in {h_engram_current,  h_engram_current + 1}
    /\ h_engram_verified' \in {h_engram_verified, h_engram_current'}

    \* -- ZK re-anchoring proof validity --
    \* Proof becomes valid only once the Bitcoin anchor has caught up to
    \* the submission height (i.e., the OP_RETURN tx is confirmed).
    /\ reanchoring_proof_valid' =
           IF state = "RECOVERING"
              /\ h_btc_anchored' >= h_btc_submitted'
              /\ h_btc_submitted' > 0
           THEN TRUE
           ELSE FALSE

    \* -- DAS failure flag (random external signal) --
    /\ is_das_failed' \in BOOLEAN

    \* -- P2P network: pick one of 4 adversarial/normal scenarios --
    \* (Abstracted to avoid state space explosion from per-peer enumeration)
    /\ \/ \* Scenario 1: Healthy — fully connected to all anchor peers
           /\ active_peers'     = anchor_peers
           /\ blacklisted_peers' = {}
       \/ \* Scenario 2: Eclipse Attack — sybil nodes fill connection slots
           /\ active_peers'     = {"sybil_n1", "sybil_n2", "sybil_n3"}
           /\ blacklisted_peers' = {"sybil_n1"}  \* Detection begins
       \/ \* Scenario 3: Network partition — complete loss of connectivity
           /\ active_peers'     = {}
           /\ blacklisted_peers' = blacklisted_peers
       \/ \* Scenario 4: Stable — no change
           /\ UNCHANGED <<active_peers, blacklisted_peers>>

    /\ UNCHANGED anchor_peers          \* Anchor peers are statically configured IPs
    /\ UNCHANGED <<state, safe_blocks>>
    /\ UNCHANGED <<censorVars>>

(* ======================== FSM RULE ENGINE ================================= *)
\* Pure function: given the current sensor readings, compute the next FSM state.
\* This is called by EngramServer at every decision point.
CalculateNextFSMState == 
    CASE state = "ANCHORED" /\ IsCriticalCondition -> "SOVEREIGN"
      [] state = "ANCHORED" /\ IsWarningCondition /\ ~IsCriticalCondition -> "SUSPICIOUS"
      [] state = "SUSPICIOUS" /\ IsCriticalCondition -> "SOVEREIGN"
      [] state = "SUSPICIOUS" /\ IsHealthyCondition -> "ANCHORED"
      [] state = "SOVEREIGN" /\ IsHealthyCondition -> "RECOVERING"
      [] state = "RECOVERING" /\ IsCriticalCondition -> "SOVEREIGN"
      [] state = "RECOVERING" /\ IsHealthyCondition /\ safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid = TRUE -> "ANCHORED"
      [] state = "RECOVERING" /\ IsHealthyCondition /\ safe_blocks < HYSTERESIS_WAIT -> "RECOVERING"
      [] OTHER -> state


\* Action: write the FSM transition and update the hysteresis counter.
ExecuteFSMTransition(target_state) ==
    /\ state'       = target_state
    /\ safe_blocks' =
           IF target_state = "RECOVERING" /\ state = "SOVEREIGN"
           THEN 0                   \* Reset counter on first entry into RECOVERING
           ELSE IF target_state = "RECOVERING"
                THEN safe_blocks + 1  \* Increment hysteresis counter each RECOVERING block
                ELSE 0



(* ======================== SAFETY PROPERTIES ============================== *)
\* Safety 1: Withdrawal lock is active if and only if state is SOVEREIGN or RECOVERING
CircuitBreakerSafety ==
    WithdrawLocked <=> (state \in {"SOVEREIGN", "RECOVERING"})

\* Safety 2: The only way to exit RECOVERING is after full hysteresis + valid ZK proof
HysteresisSafety ==
    [][ (state = "RECOVERING" /\ state' = "ANCHORED")
        => (safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid) ]_fsmVars


(* ======================== LIVENESS PROPERTIES ============================ *)
\* Liveness 1: Critical condition must eventually cause transition to SOVEREIGN
CircuitBreakerLiveness ==
    IsCriticalCondition ~> (state = "SOVEREIGN" \/ ~IsCriticalCondition)

\* Liveness 2: Recovery attempt must eventually be initiated once network heals
RecoveryAttemptLiveness ==
    (state = "SOVEREIGN" /\ IsHealthyCondition)
    ~> (state = "RECOVERING" \/ ~IsHealthyCondition)

\* Liveness 3: Recovery must eventually complete once proof is ready
CompleteRecoveryLiveness ==
    (state = "RECOVERING" /\ reanchoring_proof_valid /\ IsHealthyCondition)
    ~> (state = "ANCHORED" \/ ~IsHealthyCondition \/ ~reanchoring_proof_valid)

=============================================================================