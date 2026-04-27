---------------- MODULE MC_ServerRefinementSafety ---------------- 
EXTENDS EngramServer, TLC, Sequences

CONSTANTS n1, n2, n3, n4

ASSUME QuorumOverlap

(* ======================== NETWORK SCALE =============================== *)
MC_Nodes == {n1, n2, n3, n4} 
MC_Method == {"TX_NORMAL", "TX_WITHDRAWAL"}
MC_Faulty == {n4}
MC_Corr == MC_Nodes \ MC_Faulty

(* ======================== ROTATIONAL LEADER CONFIGURATION =============================== *)
MC_NodeSeq == <<n1, n2, n3, n4>>
MC_Proposer == [r \in 0..5 |-> MC_NodeSeq[(r % 4) + 1]]

(* ======================== INIT & NEXT =============================== *)
MC_Server_Init == Server_Init
MC_Server_Next == Server_Next

(* ======================== PRUNING CONSTRAINT) =============================== *)
StateSpaceLimit == 
    \* 1. Tendermint constraints
    /\ \A n \in MC_Corr : round[n] <= MaxRound
    /\ realTime <= MaxTimestamp

    \* 2. FSM constraints
    /\ h_btc_current <= MaxBTCHeight
    /\ h_engram_current <= MaxEngramHeight

    \* 3. Freeze DA and P2P sensors (State combination interference removal)
    /\ is_das_failed = FALSE
    /\ peer_count \in {2, 3}
    /\ state \in {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}


(* ======================== REFINEMENT CHECKS =============================== *)
\* Phase 1: Verify Safety
RefinementSafety == AbstractConsensus!Safety

\* Phase 2: Verify Liveness
RefinementLiveness == AbstractConsensus!Liveness
=============================================================================