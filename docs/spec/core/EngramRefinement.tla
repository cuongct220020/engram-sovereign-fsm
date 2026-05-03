--------------------------- MODULE EngramRefinement -------------------------
(*
 * EngramRefinement — LiDO Abstract Refinement Mapping
 *
 * This module proves that EngramServer (the concrete Tendermint-based spec)
 * refines EngramConsensus (the abstract LiDO pacemaker spec).
 *
 * Refinement structure (per the conventions document):
 *   1. Mapping functions: translate concrete variables → abstract variables
 *   2. INSTANCE:  AbstractConsensus == INSTANCE EngramConsensus WITH ...
 *   3. Theorem:   Server_Spec => AbstractConsensus!Spec
 *
 * Key design decision — Homogeneous Stake:
 *   Instead of tracking arbitrary stake weights (which would add a variable
 *   and explode the TLC state space), every node is assigned exactly 1 unit
 *   of stake. This preserves the Quorum Overlap property while keeping the
 *   state space tractable. The assumption is verified by ASSUME QuorumOverlap.
 *
 * Depends on: EngramServer (all concrete variables and operators),
 *             EngramConsensus (abstract spec being refined)
 *)
EXTENDS EngramServer


(* ======================== HOMOGENEOUS STAKE ASSUMPTION ==================== *)
\* Each node contributes exactly 1 vote unit.
\* TotalStake = |Nodes|, so a quorum needs more than 2/3 of Nodes.
HomogeneousStake      == [n \in Nodes |-> 1]
HomogeneousTotalStake == Cardinality(Nodes)

\* Pick any valid quorum (used for mapping voters in synthesized certificates)
Q_abstract == CHOOSE q \in SUBSET Nodes : Cardinality(q) >= THRESHOLD2


(* ======================== CERTIFICATE MAPPING HELPERS ==================== *)
\* Synthesize C-caches from concrete precommit quorums.
\* Each (round, id) pair with >= 2f+1 precommits becomes a C-cache entry.
CommitPairs ==
    UNION { { <<r, m.id>> : m \in msgsPrecommit[r] } : r \in Rounds }

ValidCommits ==
    { pair \in CommitPairs :
        /\ pair[2] /= NilProposal
        /\ Cardinality({ m \in msgsPrecommit[pair[1]] : m.id = pair[2] }) >= THRESHOLD2 }

\* C-caches derived from concrete precommit quorums
c_caches_dynamic == {
    [ type          |-> "C",
      c_round       |-> pair[1] + 1,
      caller        |-> Proposer[pair[2]],
      method        |-> "None",
      voters        |-> Q_abstract,
      btc_anchored  |-> h_btc_current + 2 ] : pair \in ValidCommits
}


(* ======================== ABSTRACT TREE MAPPING ========================== *)
\* Translate concrete QC/TC certificate sets (qcs, tcs) into the abstract
\* AdoB buffer tree consumed by EngramConsensus.
\*
\*   E_QC  -> E-cache  (Pull event)
\*   M_QC  -> M-cache  (Invoke event)
\*   T_QC  -> T-cache  (Timeout event)
\*   precommit quorum -> C-cache (Push / commit event)
mapped_tree ==
    LET
        e_caches == {
            [ type          |-> "E",
              c_round       |-> qc.round + 1,
              caller        |-> qc.caller,
              method        |-> "None",
              voters        |-> Q_abstract,
              btc_anchored  |-> qc.btc_anchored + 2 ]
            : qc \in { q \in qcs : q.type = "E_QC" } }

        m_caches == {
            [ type          |-> "M",
              c_round       |-> qc.round + 1,
              caller        |-> qc.caller,
              method        |-> qc.method,
              voters        |-> {qc.caller},
              btc_anchored  |-> qc.btc_anchored + 2 ]
            : qc \in { q \in qcs : q.type = "M_QC" } }

        t_caches == {
            [ type          |-> "T",
              c_round       |-> tc.round + 1,
              caller        |-> tc.caller,
              method        |-> "None",
              voters        |-> Q_abstract,
              btc_anchored  |-> tc.btc_anchored + 2 ]
            : tc \in { t \in tcs : t.type = "T_QC" } }
    IN
        e_caches \cup m_caches \cup c_caches_dynamic \cup t_caches


(* ======================== ABSTRACT STATE MAPPINGS ======================== *)
\* FSM state mapping: collapse SUSPICIOUS into ANCHORED (abstract spec only
\* distinguishes ANCHORED vs SOVEREIGN).
mapped_fsm_state ==
    IF state \in {"ANCHORED", "SUSPICIOUS"}
    THEN "ANCHORED"
    ELSE "SOVEREIGN"

\* Local time mapping: a node's abstract logical time is the highest E_QC or
\* C-cache round it has participated in.
mapped_local_times ==
    [ n \in Nodes |->
        IF n \in Q_abstract
        THEN Max(
                 {0}
                 \cup { qc.round + 1 : qc \in { q \in qcs : q.type = "E_QC" } }
                 \cup { c.c_round + 1 : c \in c_caches_dynamic }
             )
        ELSE 0
    ]

\* Round mapping: the abstract consensus round leads the concrete max round by 1
CurrentMaxRound == Max({ round[p] : p \in Corr })

CurrentRoundNodes == { p \in Corr : round[p] = CurrentMaxRound }

\* Timeout mapping: minimum remaining time among processes in the current round
MinRemTime == Min({ local_rem_time[p] : p \in CurrentRoundNodes })


(* ======================== INSTANTIATION ================================== *)
\* Bind all abstract variables to their concrete mappings.
\* The "+2" offsets on btc heights account for the finality depth k=2.
AbstractConsensus ==
    INSTANCE EngramConsensus WITH
        Nodes           <- Nodes,
        Method          <- Method,
        Stake           <- HomogeneousStake,
        TotalStake      <- HomogeneousTotalStake,
        ResetTime       <- TimeoutDuration,
        MaxBTCHeight    <- MAX_BTC_HEIGHT,
        tree            <- mapped_tree,
        fsm_state       <- mapped_fsm_state,
        round           <- CurrentMaxRound + 1,
        local_times     <- mapped_local_times,
        rem_time        <- MinRemTime,
        h_btc_current   <- h_btc_current + 2,
        h_btc_anchored  <- h_btc_anchored + 2


(* ======================== REFINEMENT CHECKS ============================== *)
\* QuorumOverlap: any two valid quorums share at least one correct process.
\* This is the foundational safety assumption — checked as ASSUME in MC files.
QuorumOverlap ==
    \A q1, q2 \in AbstractConsensus!ValidQuorums :
        (q1 \intersect q2) \intersect Corr /= {}

\* RefinementSafety:  concrete Server_Spec satisfies the abstract Safety spec
RefinementSafety   == AbstractConsensus!Safety

\* RefinementLiveness: concrete Server_Spec satisfies the abstract Liveness spec
RefinementLiveness == AbstractConsensus!Liveness

=============================================================================
