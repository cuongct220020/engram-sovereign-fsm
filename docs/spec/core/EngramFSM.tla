--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers, FiniteSets, EngramVars

CONSTANTS 
    T_SUSPICIOUS,                   \* Warning delay threshold (Gray Failure)
    T_SOVEREIGN,                    \* Sovereign partition threshold (Hard Failure)
    MIN_PEERS,                       \* Minimum peers required to prevent isolation
    MIN_SUBNET_DIVERSITY,
    MIN_ANCHOR_PEERS


ASSUME 
    /\ T_SUSPICIOUS \in Nat 
    /\ T_SOVEREIGN \in Nat 
    /\ T_DA \in Nat 
    /\ HYSTERESIS_WAIT \in Nat  
    /\ MIN_PEERS \in Nat
    /\ MIN_SUBNET_DIVERSITY \in Nat
    /\ MIN_ANCHOR_PEERS \in Nat
    /\ T_SUSPICIOUS < T_SOVEREIGN


(************************ CALCULATE DYNAMIC GAPS *********************)
MinVal(a, b) == IF a < b THEN a ELSE b

\* Bitcoin layer verification gap
btc_gap == h_btc_current - MinVal(h_btc_submitted, h_btc_anchored)

\* Data Availability layer verification gap
da_gap == h_engram_current - h_engram_verified


(************************ P2P QUALITY SENSOR *********************)
\* Map virtual IPs to network ranges (subnets /24) so that TLC can compute SubnetDiversity
SubnetOf(p) == 
    CASE p = "Anchor_1" -> "Subnet_A"
      [] p = "Anchor_2" -> "Subnet_B"
      [] p = "Anchor_3" -> "Subnet_C"
      [] p \in {"Sybil_1", "Sybil_2", "Sybil_3"} -> "Subnet_Malicious" \* Sybil nodes are typically located within the same IP range
      [] OTHER -> "Unknown_Subnet"

\* 1. Assessing Subnet Diversity
SubnetDiversity == Cardinality({SubnetOf(p) : p \in active_peers})

\* 2. Anchor Health Assessment
ActiveAnchors == active_peers \intersect anchor_peers

\* 3. Evaluate the clean peer rate (Route table poisoning prevention)
CleanPeers == active_peers \ blacklisted_peers


IsP2PQualityHealthy == 
    /\ SubnetDiversity >= MIN_SUBNET_DIVERSITY          \* The network is not concentrated on a single IP block.
    /\ Cardinality(ActiveAnchors) >= MIN_ANCHOR_PEERS   \* Maintains connection with root nodes
    /\ Cardinality(CleanPeers) >= MIN_PEERS             \* Sufficient number of nodes with no malicious behavior


(************************ MACROS & DERIVED VARIABLES *********************)
WithdrawLocked == state \in {"SOVEREIGN", "RECOVERING"}


IsDAHealthy == (da_gap < T_DA) /\ ~is_das_failed

\* Critical failure conditions (Triggers circuit breaker)
IsCriticalCondition == btc_gap >= T_SOVEREIGN 

\* Warning conditions for unstable network or risks
IsWarningCondition == 
    \/ (T_Suspicious <= btc_gap /\ btc_gap < T_Sovereign)
    \/ ~IsDAHealthy
    \/ ~IsP2PQualityHealthy

\* Completely healthy network conditions
IsHealthyCondition == 
    /\ btc_gap < T_SUSPICIOUS
    /\ IsDAHealthy
    /\ IsP2PQualityHealthy


(************************ TYPE INVARIANT & SANITY CHECK *********************)
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

\* Sanity Check: Deliberately detecting errors to ensure the system does NOT freeze.
SanityCheck == state /= "RECOVERING"


(************************ STATE MACHINE INITIALIZATION *********************)
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

(************************ ENVIRONMENT SENSORS UPDATE *********************)
\* Non-deterministic environment variable updates (Simulates real network)
UpdateSensors ==
    \* The height of a block can only increase or remain constant; each subsequent block cannot exceed the previous one.
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1}
    /\ h_btc_submitted' \in {h_btc_submitted, h_btc_current'}
    /\ h_btc_anchored' \in {h_btc_anchored, h_btc_submitted'}
    
    /\ h_engram_current' \in {h_engram_current, h_engram_current + 1}
    /\ h_engram_verified' \in {h_engram_verified, h_engram_current'}

    \* ZK proof is only valid when the Bitcoin anchor point is confirmed (anchored)
    \* catches up with or exceeds the proof submission time.
    /\ reanchoring_proof_valid' = 
          IF state = "RECOVERING" /\ h_btc_anchored' >= h_btc_submitted' /\ h_btc_submitted' > 0
          THEN TRUE 
          ELSE FALSE
    
    \* Random external environmental variables
    /\ is_das_failed' \in BOOLEAN
    
    \* Abstract the network into 4 adversarial/normal scenarios to avoid state space explosion
    /\ \* Scenario 1: Healthy network - Fully connected to anchor peers, no malicious traffic
        /\ active_peers' = anchor_peers
        /\ blacklisted_peers' = {}
    \/ \* Scenario 2: Under Eclipse Attack - Connection slots filled with Sybil nodes, loss of anchor connectivity
        /\ active_peers' = {"sybil_n1", "sybil_n2", "sybil_n3"}
        /\ blacklisted_peers' = {"sybil_n1"}    \* Detection mechanism starts identifying some and adds them to the blacklist
    \/ \* Scenario 3: Physical network partition - Cable cut, complete loss of connectivity
        /\ active_peers' = {}
        /\ blacklisted_peers' = blacklisted_peers
    \/ \* Scenario 4: No change in P2P state (Stable network)
        /\ UNCHANGED <<active_peers, blacklisted_peers>>

    /\ UNCHANGED anchor_peers \* Anchor peers are statically configured bootstrap IPs

    \* Keep core FSM states unchanged during sensor updates
    /\ UNCHANGED <<state, safe_blocks>>
    /\ UNCHANGED <<censorVars>>

(************************ FSM RULE ENGINE (DYNAMIC STATE) *********************)
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

(************************ FSM TRIGGER EXECUTION *********************)
Execute_FSM_State_Transition(target_state) == 
    /\ state' = target_state
    /\ safe_blocks' = IF target_state = "RECOVERING" /\ state = "SOVEREIGN" THEN 0 
                      ELSE IF target_state = "RECOVERING" THEN safe_blocks + 1 
                      ELSE 0



(************************ SAFETY PROPERTIES *********************)
\* Safety 1: All withdrawals must be locked when in Sovereign or Recovering
CircuitBreakerSafety == WithdrawLocked <=> (state \in {"SOVEREIGN", "RECOVERING"})

\* Safety 2: The sequential nature of Hysteresis (No skipping steps allowed)
HysteresisSafety == 
    [][ (state = "RECOVERING" /\ state' = "ANCHORED") => (safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid) ]_fsmVars


(************************ LIVENESS PROPERTIES *********************)
\* Liveness 1: If critical thresholds are reached, system MUST transition to SOVEREIGN
CircuitBreakerLiveness == 
    IsCriticalCondition ~> (state = "SOVEREIGN" \/ ~IsCriticalCondition)

\* Liveness 2: If in SOVEREIGN and network recovers, system MUST attempt recovery
RecoveryAttemptLiveness == 
    (state = "SOVEREIGN" /\ IsHealthyCondition) ~> (state = "RECOVERING" \/ ~IsHealthyCondition)

\* Liveness 3: Ensure the recovery process will be completed.
CompleteRecoveryLiveness == 
    (state = "RECOVERING" /\ reanchoring_proof_valid /\ IsHealthyCondition) 
    ~> (state = "ANCHORED" \/ ~IsHealthyCondition \/ ~reanchoring_proof_valid)
=============================================================================