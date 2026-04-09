------------------------ MODULE EngramMultiNode ------------------------
EXTENDS Integers, FiniteSets, TLC

\* Define parameters and the set of Nodes in the network
CONSTANTS T1, T2, MAX_GAP, HYSTERESIS_WAIT, Nodes

ASSUME T1 \in Nat /\ T2 \in Nat /\ MAX_GAP \in Nat /\ HYSTERESIS_WAIT \in Nat
ASSUME T1 < T2 /\ T2 < MAX_GAP

\* node_state: Local state of each Node
\* votes_sovereign: Set of Nodes requesting circuit breaker activation
VARIABLES node_state, gap, connection, safe_blocks, withdraw_locked, votes_sovereign

vars == <<node_state, gap, connection, safe_blocks, withdraw_locked, votes_sovereign>>

States == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
Connections == {"STABLE", "CONGESTED", "PARTITIONED"}

\* -----------------------------------------------------------------------------
\* BFT CONSENSUS MECHANISM: REQUIRES > 2/3 OF NODES (QUORUM)
\* -----------------------------------------------------------------------------
Quorum == (2 * Cardinality(Nodes) \div 3) + 1

\* -----------------------------------------------------------------------------
\* SAFETY PROPERTIES
\* -----------------------------------------------------------------------------
TypeOK == 
    /\ node_state \in [Nodes -> States]  \* Maps each Node to its state
    /\ gap \in 0..MAX_GAP
    /\ connection \in Connections
    /\ safe_blocks \in 0..HYSTERESIS_WAIT
    /\ withdraw_locked \in BOOLEAN
    /\ votes_sovereign \subseteq Nodes   \* Set of Nodes that have voted for circuit breaker activation

\* CRITICAL SAFETY: If any Node is in Sovereign/Recovering, assets must be locked
CircuitBreakerSafety == 
    (\E n \in Nodes: node_state[n] \in {"SOVEREIGN", "RECOVERING"}) => (withdraw_locked = TRUE)

\* -----------------------------------------------------------------------------
\* STATE MACHINE LOGIC (MULTI-AGENT)
\* -----------------------------------------------------------------------------
Init ==
    /\ node_state = [n \in Nodes |-> "ANCHORED"]
    /\ gap = 0
    /\ connection = "STABLE"
    /\ safe_blocks = 0
    /\ withdraw_locked = FALSE
    /\ votes_sovereign = {}

\* 1. Gray Failure Warning (Local): Node transitions to SUSPICIOUS, no global impact yet
NodeToSuspicious(n) ==
    /\ node_state[n] = "ANCHORED"
    /\ gap >= T1
    /\ gap < T2
    /\ node_state' = [node_state EXCEPT ![n] = "SUSPICIOUS"]
    /\ UNCHANGED <<gap, connection, safe_blocks, withdraw_locked, votes_sovereign>>

\* 2. Sovereign Vote (P2P Gossip): Node detects network failure, sends vote for SOVEREIGN
CastVoteSovereign(n) ==
    /\ node_state[n] \in {"ANCHORED", "SUSPICIOUS"}
    /\ (gap >= T2 \/ connection = "PARTITIONED")
    /\ n \notin votes_sovereign
    /\ votes_sovereign' = votes_sovereign \cup {n}
    /\ UNCHANGED <<node_state, gap, connection, safe_blocks, withdraw_locked>>

\* 3. Execute Global Circuit Breaker
\* Only when the number of votes reaches QUORUM (>= 2/3), the system officially activates the circuit breaker and locks assets
ExecuteSovereignFallback ==
    /\ Cardinality(votes_sovereign) >= Quorum
    /\ withdraw_locked = FALSE
    /\ node_state' = [n \in Nodes |-> IF n \in votes_sovereign THEN "SOVEREIGN" ELSE node_state[n]]
    /\ withdraw_locked' = TRUE
    /\ UNCHANGED <<gap, connection, safe_blocks, votes_sovereign>>

\* Dynamic network environment
NetworkEnvironment ==
    /\ connection' \in Connections
    /\ gap' \in 0..MAX_GAP
    /\ UNCHANGED <<node_state, safe_blocks, withdraw_locked, votes_sovereign>>

\* -----------------------------------------------------------------------------
\* NEXT STATE RELATION
\* -----------------------------------------------------------------------------
Next == 
    \/ (\E n \in Nodes : NodeToSuspicious(n))   \* Any Node can update its state
    \/ (\E n \in Nodes : CastVoteSovereign(n))  \* Any Node can cast a vote
    \/ ExecuteSovereignFallback                 \* Trigger circuit breaker when quorum is reached
    \/ NetworkEnvironment

Fairness == WF_vars(Next)
Spec == Init /\ [][Next]_vars /\ Fairness

\* -----------------------------------------------------------------------------
\* REFINEMENT MAPPING
\* -----------------------------------------------------------------------------

\* 1. Define how to map states from "Local View" to "Global View".
\* If any Node is in Sovereign, the entire network is considered SOVEREIGN/RECOVERING.
\* If not, but a Node is in SUSPICIOUS, the network is SUSPICIOUS. Otherwise, it is ANCHORED.
GlobalState == 
    IF \E n \in Nodes: node_state[n] = "SOVEREIGN" THEN "SOVEREIGN"
    ELSE IF \E n \in Nodes: node_state[n] = "RECOVERING" THEN "RECOVERING"
    ELSE IF \E n \in Nodes: node_state[n] = "SUSPICIOUS" THEN "SUSPICIOUS"
    ELSE "ANCHORED"

\* 2. Embed the abstract model and map its variables (left-hand side) to current variables (right-hand side)
AbstractModel == INSTANCE EngramFSM WITH
    state <- GlobalState,
    gap <- gap,
    connection <- connection,
    safe_blocks <- safe_blocks,
    withdraw_locked <- withdraw_locked

\* 3. Define Refinement Property
\* "Every valid behavior of this multi-node model must also be a valid behavior of EngramFSM"
Refinement == AbstractModel!Spec

\* Declare symmetry: Any permutation of Nodes creates an equivalent state
Symmetry == Permutations(Nodes)
=============================================================================