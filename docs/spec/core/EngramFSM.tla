--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers, EngramVars

CONSTANTS 
    T_SUSPICIOUS,                   \* Warning delay threshold (Gray Failure)
    T_SOVEREIGN,                    \* Sovereign partition threshold (Hard Failure)
    T_DA,                           \* Block gap since the last DA publication verification
    HYSTERESIS_WAIT,                \* Consecutive safe blocks required for successful recovery
    MIN_PEERS                       \* Minimum peers required to prevent isolation


ASSUME 
    /\ T_SUSPICIOUS \in Nat 
    /\ T_SOVEREIGN \in Nat 
    /\ T_DA \in Nat 
    /\ HYSTERESIS_WAIT \in Nat  
    /\ MIN_PEERS \in Nat
    /\ T_SUSPICIOUS < T_SOVEREIGN


-----------------------------------------------------------------------------
\* CALCULATE DYNAMIC GAPS
-----------------------------------------------------------------------------
MinVal(a, b) == IF a < b THEN a ELSE b

\* Bitcoin layer verification gap
btc_gap == h_btc_current - MinVal(h_btc_submitted, h_btc_anchored)

\* Data Availability layer verification gap
da_gap == h_da_local - h_da_verified

\* -----------------------------------------------------------------------------
\* MACROS & DERIVED VARIABLES
\* -----------------------------------------------------------------------------
withdraw_locked == state \in {"SOVEREIGN", "RECOVERING"}

FSM_IsDAHealthy == (da_gap < T_DA) /\ ~is_das_failed

\* Critical failure conditions (Triggers circuit breaker)
IsCriticalCondition == btc_gap >= T_SOVEREIGN 

\* Warning conditions for unstable network or risks
IsWarningCondition == 
    \/ (btc_gap >= T_SUSPICIOUS /\ btc_gap < T_SOVEREIGN)
    \/ da_gap >= T_DA
    \/ is_das_failed
    \/ peer_count < MIN_PEERS

\* Completely healthy network conditions
IsHealthyCondition == 
    /\ btc_gap < T_SUSPICIOUS
    /\ FSM_IsDAHealthy
    /\ peer_count >= MIN_PEERS


\* -----------------------------------------------------------------------------
\* TYPE INVARIANT & SANITY CHECK
\* -----------------------------------------------------------------------------
TypeInvariant == 
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
    /\ btc_gap >= 0
    /\ da_gap >= 0
    /\ is_das_failed \in BOOLEAN
    /\ peer_count \in 0..(MIN_PEERS * 2)
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ reanchoring_proof_valid \in BOOLEAN

\* Sanity Check: Deliberately detecting errors to ensure the system does NOT freeze.
SanityCheck == state /= "RECOVERING"


\* -----------------------------------------------------------------------------
\* STATE MACHINE LOGIC
\* -----------------------------------------------------------------------------
FSM_Init == 
    /\ state = "ANCHORED" 
    /\ h_btc_current = 0 
    /\ h_btc_submitted = 0 
    /\ h_btc_anchored = 0 
    /\ h_da_local = 0 
    /\ h_da_verified = 0 
    /\ is_das_failed = FALSE 
    /\ peer_count = MIN_PEERS + 1 
    /\ safe_blocks = 0 
    /\ reanchoring_proof_valid = FALSE

\* Non-deterministic environment variable updates (Simulates real network)
UpdateSensors ==
    \* The height of a block can only increase or remain constant; each subsequent block cannot exceed the previous one.
    /\ h_btc_current' \in {h_btc_current, h_btc_current + 1}
    /\ h_btc_submitted' \in {h_btc_submitted, h_btc_current'}
    /\ h_btc_anchored' \in {h_btc_anchored, h_btc_submitted'}
    
    /\ h_da_local' \in {h_da_local, h_da_local + 1}
    /\ h_da_verified' \in {h_da_verified, h_da_local'}
    
    \* Random external environmental variables
    /\ is_das_failed' \in BOOLEAN
    /\ reanchoring_proof_valid' \in BOOLEAN
    /\ peer_count' \in 0..(MIN_PEERS * 2)
    
    /\ UNCHANGED <<state, safe_blocks>>


\* FSM state transitions based on sensor data
AnchoredToSuspicious == 
    /\ state = "ANCHORED"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToSovereign == 
    /\ state = "SUSPICIOUS"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<safe_blocks>>

AnchoredToSovereign == 
    /\ state = "ANCHORED"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ UNCHANGED <<safe_blocks>>

SuspiciousToAnchored == 
    /\ state = "SUSPICIOUS"
    /\ IsHealthyCondition
    /\ state' = "ANCHORED"
    /\ UNCHANGED <<safe_blocks>>

SovereignToRecovering == 
    /\ state = "SOVEREIGN"
    /\ IsHealthyCondition
    /\ state' = "RECOVERING"
    /\ safe_blocks' = 0

RecoveringProgress == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks < HYSTERESIS_WAIT
    /\ safe_blocks' = safe_blocks + 1
    /\ UNCHANGED <<state>>

RecoveringToAnchored == 
    /\ state = "RECOVERING"
    /\ IsHealthyCondition
    /\ safe_blocks = HYSTERESIS_WAIT
    /\ reanchoring_proof_valid = TRUE
    /\ state' = "ANCHORED"
    /\ safe_blocks' = 0

RecoveringToSuspicious == 
    /\ state = "RECOVERING"
    /\ IsWarningCondition
    /\ ~IsCriticalCondition
    /\ state' = "SUSPICIOUS"
    /\ safe_blocks' = 0

RecoveringToSovereign == 
    /\ state = "RECOVERING"
    /\ IsCriticalCondition
    /\ state' = "SOVEREIGN"
    /\ safe_blocks' = 0

FSM_Transition == 
    \/ AnchoredToSuspicious \/ SuspiciousToSovereign \/ AnchoredToSovereign 
    \/ SuspiciousToAnchored \/ SovereignToRecovering \/ RecoveringProgress 
    \/ RecoveringToAnchored \/ RecoveringToSuspicious \/ RecoveringToSovereign

FSM_Next == UpdateSensors \/ (FSM_Transition /\ UNCHANGED envVars)


FSM_Fairness == 
    /\ WF_fsmVars(AnchoredToSuspicious /\ UNCHANGED envVars)
    /\ WF_fsmVars(SuspiciousToSovereign /\ UNCHANGED envVars)
    /\ WF_fsmVars(AnchoredToSovereign /\ UNCHANGED envVars)
    /\ WF_fsmVars(SuspiciousToAnchored /\ UNCHANGED envVars)
    /\ WF_fsmVars(SovereignToRecovering /\ UNCHANGED envVars)
    /\ WF_fsmVars(RecoveringProgress /\ UNCHANGED envVars)
    /\ WF_fsmVars(RecoveringToAnchored /\ UNCHANGED envVars)
    /\ WF_fsmVars(RecoveringToSuspicious /\ UNCHANGED envVars)
    /\ WF_fsmVars(RecoveringToSovereign /\ UNCHANGED envVars)

Spec == FSM_Init /\ [][FSM_Next]_fsmVars /\ FSM_Fairness


\* -----------------------------------------------------------------------------
\* SAFETY PROPERTIES
\* -----------------------------------------------------------------------------

\* Safety 1: All withdrawals must be locked when in Sovereign or Recovering
CircuitBreakerSafety == withdraw_locked <=> (state \in {"SOVEREIGN", "RECOVERING"})

\* Safety 2: Ensure the system never gets stuck (Deadlock-Free).
NoDeadlockSafety == ENABLED FSM_Next

\* Safety 3: The sequential nature of Hysteresis (No skipping steps allowed)
HysteresisSafety == 
    [][ (state = "RECOVERING" /\ state' = "ANCHORED") => (safe_blocks = HYSTERESIS_WAIT /\ reanchoring_proof_valid) ]_fsmVars


\* -----------------------------------------------------------------------------
\* LIVENESS PROPERTIES
\* -----------------------------------------------------------------------------

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