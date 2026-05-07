---------------- MODULE MC_ServerRefinementSafety ----------------
(*
 * MC_ServerRefinementSafety — TLC Safety Model Checker
 *
 * Runs TLC to verify SAFETY properties of the concrete EngramServer spec
 * against the abstract EngramConsensus (LiDO) spec via EngramRefinement.
 *
 * Run separately from MC_ServerRefinementLiveness because:
 *   - Safety uses INIT/NEXT directly (no fairness, faster state exploration)
 *   - Higher bounds (MaxRound = 3) are feasible without fairness overhead
 *
 * Corresponding config: MC_ServerRefinementSafety.cfg
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
MC_ServerInit == ServerInit
MC_ServerNext == ServerNext


(* ======================== STATE SPACE PRUNING CONSTRAINT ================= *)
\* Bounds are deliberately tighter than Liveness to keep safety runs tractable.
StateSpaceLimit ==
    \* Tendermint bounds
    /\ \A n \in MC_Corr : round[n] <= MAX_ROUND
    /\ real_time <= MAX_TIMESTAMP

    \* Chain height bounds (monotone by construction, but TLC needs explicit caps)
    /\ h_btc_current <= MAX_BTC_HEIGHT
    /\ h_engram_current <= MAX_ENGRAM_HEIGHT
    /\ h_engram_verified <= h_engram_current
    /\ h_btc_submitted <= h_btc_current
    /\ h_btc_anchored <= h_btc_submitted

    \* P2P network size
    /\ Cardinality(active_peers) \in {2, 3}
    /\ Cardinality(anchor_peers) <= 3
    /\ Cardinality(blacklisted_peers) <= 2
    /\ peer_churn_rate <= MAX_CHURN_RATE + 2
    /\ avg_peer_tenure <= MIN_AVG_TENURE + 100
    /\ peer_latency <= MAX_PEER_LATENCY + 10

    /\ is_btc_spv_failed \in BOOLEAN
    /\ is_das_failed \in BOOLEAN
    /\ is_attestation_failed \in BOOLEAN
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}


(* ======================== REFINEMENT PROPERTIES ========================== *)
RefinementSafety   == AbstractConsensus!Safety

=============================================================================
