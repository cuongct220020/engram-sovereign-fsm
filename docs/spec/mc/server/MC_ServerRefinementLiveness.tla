---------------- MODULE MC_ServerRefinementLiveness ----------------
(*
 * MC_ServerRefinementLiveness — TLC Liveness Model Checker
 *
 * Runs TLC to verify LIVENESS properties of the concrete EngramServer spec
 * against the abstract EngramConsensus (LiDO) spec via EngramRefinement.
 *
 * Run separately from MC_ServerRefinementSafety because:
 *   - Liveness requires a SPECIFICATION (Init ∧ [][Next] ∧ Fairness)
 *   - Smaller bounds (MaxRound = 2) needed — fairness checking is expensive
 *   - MC_Server_Fairness defines the WF conditions for progress
 *
 * Corresponding config: MC_ServerRefinementLiveness.cfg
 *)
EXTENDS EngramServer, EngramRefinement, TLC, Sequences

CONSTANTS n1, n2, n3, n4

ASSUME QuorumOverlap


(* ======================== NETWORK CONFIGURATION ========================== *)
MC_Nodes  == {n1, n2, n3, n4}
MC_Method == {"TX_NORMAL", "TX_WITHDRAWAL"}
MC_Faulty == {n4}
MC_Corr   == MC_Nodes \ MC_Faulty


(* ======================== ROTATIONAL LEADER SCHEDULE ===================== *)
\* Round-robin proposer: node at position (r mod 4) + 1 in the sequence
MC_NodeSeq  == <<n1, n2, n3, n4>>
MC_Proposer == [r \in 0..5 |-> MC_NodeSeq[(r % 4) + 1]]


(* ======================== INIT & NEXT ==================================== *)
MC_Server_Init == Server_Init
MC_Server_Next == Server_Next


(* ======================== FAIRNESS CONDITIONS ============================ *)
\* Weak fairness on time advance ensures clocks always eventually tick.
\* Weak fairness on message processing ensures every enabled action
\* eventually fires (prevents "unfair" stuttering in liveness proofs).
MC_Server_Fairness ==
    /\ WF_serverVars(Server_AdvanceRealTime)
    /\ \A p \in MC_Corr : WF_serverVars(Server_MessageProcessing(p))

\* Full liveness specification: safety behaviour + fairness assumptions
MC_Server_Spec ==
    MC_Server_Init /\ [][MC_Server_Next]_serverVars /\ MC_Server_Fairness


(* ======================== STATE SPACE PRUNING CONSTRAINT ================= *)
\* Bounds are tighter than Safety run to keep liveness checking tractable.
StateSpaceLimit ==
    \* -- Tendermint bounds --
    /\ \A n \in MC_Corr : round[n] <= MAX_ROUND
    /\ real_time <= MAX_TIMESTAMP

    \* -- Chain height bounds (monotone by construction, but TLC needs explicit caps) --
    /\ h_btc_current    <= MAX_BTC_HEIGHT
    /\ h_engram_current <= MAX_ENGRAM_HEIGHT
    /\ h_engram_verified <= h_engram_current
    /\ h_btc_submitted   <= h_btc_current
    /\ h_btc_anchored    <= h_btc_submitted

    \* -- P2P network size --
    /\ Cardinality(active_peers) \in {2, 3}
    /\ Cardinality(anchor_peers) <= 3
    /\ Cardinality(blacklisted_peers) <= 2
    /\ peer_churn_rate <= MAX_CHURN_RATE + 2
    /\ avg_peer_tenure <= MIN_AVG_TENURE + 100
    /\ peer_latency    <= MAX_PEER_LATENCY + 10

    \* -- DAS failure is binary, state already constrained by FSM invariant --
    /\ is_das_failed \in BOOLEAN
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}


(* ======================== REFINEMENT PROPERTIES ========================== *)
RefinementLiveness == AbstractConsensus!Liveness
=============================================================================
