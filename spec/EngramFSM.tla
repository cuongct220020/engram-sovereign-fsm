--------------------------- MODULE EngramFSM ---------------------------
EXTENDS Integers

\* Define system parameters (Constants)
CONSTANTS T1, T2, MAX_GAP, HYSTERESIS_WAIT

\* Prevent nonsense parameters
ASSUME T1 \in Nat /\ T2 \in Nat /\ MAX_GAP \in Nat /\ HYSTERESIS_WAIT \in Nat
ASSUME T1 < T2 /\ T2 < MAX_GAP

VARIABLES state, gap, connection, safe_blocks, withdraw_locked

\* Group all variables into a tuple for easy UNCHANGED and Fairness declarations
vars == <<state, gap, connection, safe_blocks, withdraw_locked>>

States == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}

\* UPGRADE: Added "CONGESTED" to accurately model Gray Failures (packet loss, latency)
Connections == {"STABLE", "CONGESTED", "PARTITIONED"}

\* -----------------------------------------------------------------------------
\* SAFETY PROPERTIES
\* -----------------------------------------------------------------------------
TypeOK == 
    /\ state \in States
    /\ gap \in 0..MAX_GAP
    /\ connection \in Connections
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ withdraw_locked \in BOOLEAN

\* CRITICAL SAFETY PROPERTY: Circuit Breaker Integrity
CircuitBreakerSafety == 
    (state \in {"SOVEREIGN", "RECOVERING"}) => (withdraw_locked = TRUE)

\* GRAY FAILURE TOLERANCE: Withdrawals remain unlocked during Gray Failures (Suspicious state)
GrayFailureTolerance ==
    (state = "SUSPICIOUS") => (withdraw_locked = FALSE)

\* -----------------------------------------------------------------------------
\* STATE MACHINE LOGIC
\* -----------------------------------------------------------------------------

Init ==
    /\ state = "ANCHORED"
    /\ gap = 0
    /\ connection = "STABLE"
    /\ safe_blocks = 0
    /\ withdraw_locked = FALSE

\* 1. Normal to Suspicious (Gray Failure Buffer Phase)
\* When network is CONGESTED, gap increases to T1. System warns but DOES NOT lock withdrawals.
NormalToSuspicious ==
    /\ state = "ANCHORED"
    /\ gap >= T1
    /\ gap < T2
    /\ state' = "SUSPICIOUS"
    /\ UNCHANGED <<gap, connection, safe_blocks, withdraw_locked>>

\* 2. Suspicious to Sovereign (Hard Failure / Partitioned)
\* If Gray Failure degrades into a Hard Partition (gap >= T2), lock withdrawals.
SuspiciousToSovereign ==
    /\ state = "SUSPICIOUS"
    /\ gap >= T2
    /\ state' = "SOVEREIGN"
    /\ withdraw_locked' = TRUE  
    /\ UNCHANGED <<gap, connection, safe_blocks>>

\* 3. Suspicious back to Anchored (Gray Failure Resolved / False Alarm)
\* The network stabilizes before reaching T2. Withdrawals were never interrupted.
SuspiciousToAnchored ==
    /\ state = "SUSPICIOUS"
    /\ connection = "STABLE"
    /\ gap < T1
    /\ state' = "ANCHORED"
    /\ UNCHANGED <<gap, connection, safe_blocks, withdraw_locked>>

\* 4. Anchored directly to Sovereign (Emergency Jump / Sudden Partition)
AnchoredToSovereign_Emergency ==
    /\ state = "ANCHORED"
    /\ gap >= T2
    /\ state' = "SOVEREIGN"
    /\ withdraw_locked' = TRUE  
    /\ UNCHANGED <<gap, connection, safe_blocks>>

\* 5. Sovereign to Recovering (Network restored, start ZK-proof generation)
SovereignToRecovering ==
    /\ state = "SOVEREIGN"
    /\ connection = "STABLE"
    /\ gap < T1
    /\ state' = "RECOVERING"
    /\ safe_blocks' = 0
    /\ UNCHANGED <<gap, connection, withdraw_locked>> 

\* 6. Recovering Progress (Hysteresis mechanism)
RecoveringProgress ==
    /\ state = "RECOVERING"
    /\ connection = "STABLE"
    /\ gap < T1
    /\ safe_blocks < HYSTERESIS_WAIT
    /\ safe_blocks' = safe_blocks + 1
    /\ UNCHANGED <<state, gap, connection, withdraw_locked>>

\* 7. Recovering to Anchored (ZK-proof verified on Bitcoin)
RecoveringToAnchored ==
    /\ state = "RECOVERING"
    /\ connection = "STABLE"
    /\ gap < T1
    /\ safe_blocks = HYSTERESIS_WAIT
    /\ state' = "ANCHORED"
    /\ safe_blocks' = 0
    /\ withdraw_locked' = FALSE  
    /\ UNCHANGED <<gap, connection>>

\* 8. Recovering back to Sovereign (Network flaps back to Partitioned OR Congested)
\* UPGRADE: If network experiences Gray Failures (CONGESTED) during recovery, abort and fallback.
RecoveringToSovereign_Fail ==
    /\ state = "RECOVERING"
    /\ (connection \in {"PARTITIONED", "CONGESTED"} \/ gap >= T1)
    /\ state' = "SOVEREIGN"
    /\ safe_blocks' = 0
    /\ UNCHANGED <<gap, connection, withdraw_locked>> 

\* Environment Action: Simulates the unpredictable physical network
NetworkEnvironment ==
    /\ connection' \in Connections
    /\ gap' \in 0..MAX_GAP
    /\ UNCHANGED <<state, safe_blocks, withdraw_locked>>

\* The Next State Relation
Next == 
    \/ NormalToSuspicious
    \/ SuspiciousToSovereign
    \/ SuspiciousToAnchored
    \/ AnchoredToSovereign_Emergency
    \/ SovereignToRecovering
    \/ RecoveringProgress
    \/ RecoveringToAnchored
    \/ RecoveringToSovereign_Fail
    \/ NetworkEnvironment

\* -----------------------------------------------------------------------------
\* FAIRNESS AND SPECIFICATION
\* -----------------------------------------------------------------------------

Fairness == 
    /\ WF_vars(NormalToSuspicious)
    /\ WF_vars(SuspiciousToSovereign)
    /\ WF_vars(SuspiciousToAnchored)
    /\ WF_vars(AnchoredToSovereign_Emergency)
    /\ WF_vars(SovereignToRecovering)
    /\ WF_vars(RecoveringProgress)
    /\ WF_vars(RecoveringToAnchored)
    /\ WF_vars(RecoveringToSovereign_Fail)

Spec == Init /\ [][Next]_vars /\ Fairness

\* -----------------------------------------------------------------------------
\* LIVENESS PROPERTIES
\* -----------------------------------------------------------------------------

CircuitBreakerLiveness == 
    (gap >= T2) ~> (state = "SOVEREIGN")

RecoveryAttemptLiveness == 
    (state = "SOVEREIGN" /\ connection = "STABLE" /\ gap < T1) ~> (state = "RECOVERING")
=============================================================================