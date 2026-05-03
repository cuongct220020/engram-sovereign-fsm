--------------------------- MODULE EngramServer ---------------------------
(*
 * EngramServer — Concrete Protocol Integration Layer
 *
 * Bridges the abstract Tendermint BFT core (EngramTendermint) with the
 * Engram-specific application logic:
 *   - FSM-aware proposal construction (ServerInsertProposal)
 *   - LiDO certificate generation (E_QC, M_QC, T_QC)
 *   - Post-decision FSM state synchronisation (ServerUponProposalInPrecommitNoDecision)
 *   - Hybrid safety invariants (FSM <-> consensus cross-checks)
 *   - Liveness properties under GST
 *
 * The LiDO abstract refinement mapping lives in EngramRefinement.tla.
 *
 * Depends on: EngramFSM, EngramTendermint, Naturals, FiniteSets
 *)
EXTENDS Naturals, FiniteSets, EngramFSM, EngramTendermint

CONSTANTS
    Nodes,      \* Set of all nodes in the abstract consensus layer
    Method,     \* Set of valid transaction methods (e.g. {"TX_NORMAL", "TX_WITHDRAWAL"})
    RESET_TIME  \* Pacemaker reset time (passed through to EngramConsensus)


(* ======================== HELPERS ========================================= *)
\* TRUE once the network has accumulated 2f+1 matching precommits for any value.
\* Used as a guard to stop issuing new proposals after a block is closed.
GlobalDecisionExists ==
    \E r \in Rounds :
        \E m \in msgs_precommit[r] :
            /\ m.id /= NilProposal
            /\ Cardinality({ msg \in msgs_precommit[r] : msg.id = m.id }) >= THRESHOLD2


(* ======================== SERVER HOOKS (INTEGRATION LAYER) ================ *)

\* Hook 1: Leader builds and injects a proposal → emits E_QC (maps to Abstract Pull).
\*
\* State-space control: all non-determinism over ValidValues, proof_search_space,
\* and validValue is resolved HERE, before entering the black-box Tendermint core.
ServerInsertProposal(p) ==
    /\ ~GlobalDecisionExists
    /\ p = Proposer[round[p]]
    /\ step[p] = "PROPOSE"
    /\ \A m \in msgs_propose[round[p]] : m.src /= p
    /\ \E v \in ValidValues :
           LET
               target_state == CalculateNextFSMState

               receipt == [
                   published_block_height   |-> h_engram_verified,
                   attestation              |-> IsDAHealthy
               ]

               \* ZK proof search space: only open the TRUE branch once
               \* hysteresis is satisfied, to avoid spurious re-anchoring paths.
               proof_search_space ==
                   IF state = "RECOVERING" /\ safe_blocks >= HYSTERESIS_WAIT
                   THEN {TRUE, FALSE}
                   ELSE {FALSE}
           IN
           \E proof_found \in proof_search_space :
               LET prop ==
                       IF valid_value[p] /= NilProposal
                       THEN valid_value[p]
                       ELSE Proposal(v, local_clock[p], round[p], target_state,
                                     receipt, h_btc_anchored, proof_found)
               IN
               \* Inject the concrete proposal into Tendermint
               /\ InsertProposal(p, prop)

               \* Emit E_QC for the LiDO abstract pacemaker
               /\ LET NewEQC == [
                          type          |-> "E_QC",
                          round         |-> round[p],
                          caller        |-> p,
                          method        |-> "None",
                          btc_anchored  |-> h_btc_current ]
                  IN qcs' = qcs \cup {NewEQC}
    /\ UNCHANGED <<tcs, fsmVars, censorVars>>
    /\ UNCHANGED <<coreVars, temporalVars>>
    /\ UNCHANGED <<msgs_prevote, msgs_precommit, msgs_timeout,
                   evidence, received_timely_proposal, inspected_proposal>>
    /\ action' = "ServerInsertProposal"


\* Hook 2: Proposer votes for its own proposal → emits M_QC (maps to Abstract Invoke).
ServerProposerVotes(p) ==
    /\ \/ UponProposalInPropose(p)
       \/ UponProposalInProposeAndPrevote(p)
    /\ IF p = Proposer[round[p]]
          /\ \E m \in msgs_propose[round[p]] : m.src = p
       THEN
           LET
               prop  == (CHOOSE m \in msgs_propose[round[p]] : m.src = p).proposal
               NewMQC == [
                   type         |-> "M_QC",
                   round        |-> round[p],
                   caller       |-> p,
                   method       |-> prop.value,
                   btc_anchored |-> h_btc_current ]
           IN
           /\ qcs' = qcs \cup {NewMQC}
           /\ tcs' = tcs
       ELSE
           /\ qcs' = qcs
           /\ tcs' = tcs
    /\ action' = "ServerProposerVotes"


\* Hook 3: Intercept the decision moment -> trigger FSM transition + state sync.
\*
\* On every block commit, the decided proposal's FSM state, BTC anchor, and
\* DA receipt are written back into the local sensor variables so that the
\* next proposal reflects the globally agreed-upon chain view.
ServerUponProposalInPrecommitNoDecision(p) ==
    \* Step 1: Execute core Tendermint decision logic
    /\ UponProposalInPrecommitNoDecision(p)

    \* Step 2: Extract the just-decided proposal (the majority's agreed truth)
    /\ LET
           r    == round[p]
           msg  == CHOOSE m \in msgs_propose[r] :
                       m.src = Proposer[r] /\ m.type = "PROPOSAL"
           prop == msg.proposal
       IN
           \* Step 3: Drive FSM transition and update anchored heights
           /\ ExecuteFSMTransition(prop.fsm_state)
           /\ h_btc_anchored'    = prop.btc_receipt.checkpoint_block_height
           /\ h_engram_verified' = prop.da_receipt.published_block_height

           \* Step 4: ZK proof submission tracking.
           \* Mark proof as submitted (pending Bitcoin confirmation).
           /\ IF prop.fsm_state = "RECOVERING" /\ prop.zk_proof_ref = TRUE
              THEN
                  /\ h_btc_submitted'        = h_btc_current
                  /\ reanchoring_proof_valid' = FALSE   \* Awaiting Bitcoin confirmation
              ELSE
                  /\ h_btc_submitted'        = h_btc_submitted
                  /\ reanchoring_proof_valid' = reanchoring_proof_valid

           \* Step 5: Force-sync local sensors when ANCHORED.
           \* If the network majority is in ANCHORED, suppress any local false alarms.
           /\ IF prop.fsm_state = "ANCHORED"
              THEN
                  /\ h_btc_current'    = prop.btc_receipt.checkpoint_block_height
                  /\ h_engram_current' = prop.da_receipt.published_block_height
                  /\ is_das_failed'    = FALSE
              ELSE
                  \* Otherwise let the FSM sensors evolve independently.
                  /\ UNCHANGED <<h_btc_current, h_engram_current, is_das_failed>>

           /\ UNCHANGED <<p2pSensorVars>>

    \* Step 6: Keep pacemaker certificates and censorship sensor unchanged
    /\ UNCHANGED <<qcs, tcs, censorVars>>
    /\ action' = "ServerUponProposalInPrecommitNoDecision"


\* Hook 4: 2f+1 timeout votes -> emit T_QC (maps to Abstract Timeout) + advance round.
ServerUponTimeoutCert(p) ==
    \* Check timeout quorum
    /\  LET UniqueSenders == { m.src : m \in msgs_timeout[round[p]] }
        IN Cardinality(UniqueSenders) >= THRESHOLD2

    \* Advance to next round
    /\ StartRound(p, round[p] + 1)

    \* Emit T_QC for the LiDO abstract pacemaker
    /\  LET NewTQC == [
               type         |-> "T_QC",
               round        |-> round[p],
               caller       |-> p,
               btc_anchored |-> h_btc_current ]
        IN tcs' = tcs \cup {NewTQC}

    /\ UNCHANGED <<qcs, fsmVars>>
    /\ UNCHANGED <<forced_tx_queue>>
    /\ UNCHANGED <<local_clock, real_time>>
    /\ UNCHANGED <<end_consensus, proposal_time, proposal_received_time>>
    /\ UNCHANGED <<decision, locked_value, locked_round, valid_value, valid_round>>
    /\ UNCHANGED <<msgs_propose, msgs_prevote, msgs_precommit, msgs_timeout,
                   evidence, received_timely_proposal, inspected_proposal>>
    /\ action' = "ServerUponTimeoutCert"


(* ======================== ACTION AGGREGATION ============================== *)
\* Pass-through: Tendermint actions that require no Server-layer interception.
ServerPassThrough(p) ==
    \/ ReceiveProposal(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ UponQuorumOfPrevotesAny(p)
    \/ /\ UponQuorumOfPrecommitsAny(p)
       /\ ~GlobalDecisionExists
    \/ ServerUponProposalInPrecommitNoDecision(p)
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)
    \/ UponfPlusOneTimeoutsAny(p)

ServerMessageProcessing(p) ==
    \/ /\ ServerPassThrough(p)
       /\ UNCHANGED <<qcs, tcs, fsmVars>>
    \/ ServerInsertProposal(p)
    \/ ServerProposerVotes(p)


(* ======================== SPECIFICATION (INIT & NEXT) ===================== *)
ServerInit ==
    /\ TendermintInit
    /\ FSMInit
    /\ qcs = {}
    /\ tcs = {}

ServerAdvanceRealTime ==
    /\ AdvanceRealTime
    /\ UNCHANGED <<qcs, tcs, fsmVars>>

ServerByzantineDataWithholding ==
    /\ Byzantine_Data_Withholding
    /\ UNCHANGED <<qcs, tcs, fsmVars>>

ServerNext ==
    \/ ServerAdvanceRealTime
    \/ /\ SynchronizedLocalClocks
       /\ \E p \in Corr : ServerMessageProcessing(p)
    \/ /\ UpdateSensors
       /\ UNCHANGED <<coreVars, temporalVars, invariantVars, bookkeepingVars, censorVars>>
       /\ UNCHANGED <<action, qcs, tcs>>
    \/ ServerByzantineDataWithholding

ServerSpec == ServerInit /\ [][ServerNext]_serverVars


(* ======================== MONOTONICITY SAFETY ======================== *)
\* Chain heights and real time must monotonically increase or remain constant.
\* This temporal property ensures the model is immune to time-travel or 
\* chain rollback anomalies, preventing Long-Range Attacks.
MonotonicitySafety == 
    [][ /\ h_btc_current'    >= h_btc_current
        /\ h_btc_anchored'   >= h_btc_anchored
        /\ h_engram_current' >= h_engram_current
        /\ real_time'        >= real_time 
      ]_serverVars

(* ======================== HYBRID INVARIANTS =============================== *)
\* Cross-layer consistency checks: every decided proposal must agree with the
\* current FSM and sensor state. These are checked in addition to CoreTendermintInv.

\* Decided FSM state must match the current circuit-breaker state
FSMStateConsistency ==
    \A p \in Corr :
        decision[p] /= NilDecision => decision[p].prop.fsm_state = state

\* DA attestation must be present in any decided ANCHORED or RECOVERING block
DAReceiptConsistency ==
    \A p \in Corr :
        (decision[p] /= NilDecision
         /\ decision[p].prop.fsm_state \in {"ANCHORED", "RECOVERING"})
        => decision[p].prop.da_receipt.attestation = TRUE

\* BTC anchor height in decided proposal must match the current anchored height
BTCConsistency ==
    \A p \in Corr :
        decision[p] /= NilDecision
        => decision[p].prop.btc_receipt.checkpoint_block_height = h_btc_anchored

\* ZK proof must be present in any RECOVERING block that completed hysteresis
ZKProofConsistency ==
    \A p \in Corr :
        (decision[p] /= NilDecision
         /\ decision[p].prop.fsm_state = "RECOVERING"
         /\ safe_blocks = HYSTERESIS_WAIT)
        => decision[p].prop.zk_proof_ref = TRUE

\* Master hybrid invariant — checked together with CoreTendermintInv in TLC
HybridTendermintInvariant ==
    /\ FSMStateConsistency
    /\ DAReceiptConsistency
    /\ BTCConsistency
    /\ ZKProofConsistency


(* ======================== LIVENESS PROPERTIES ============================ *)
\* At least one correct process eventually decides
ServerEventualDecision ==
    <>(\E p \in Corr : step[p] = "DECIDED")

\* All three FSM liveness properties from EngramFSM hold end-to-end
ServerFSMLiveness ==
    /\ CircuitBreakerLiveness
    /\ RecoveryAttemptLiveness
    /\ CompleteRecoveryLiveness

\* Every tx that is repeatedly proposed must eventually be decided
ForcedInclusionLiveness ==
    \A tx \in ValidValues :
        ([]<>(\E r \in Rounds, p \in Corr :
                  \E m \in msgs_propose[r] : m.src = p /\ m.proposal.value = tx))
        => <>(\E p \in Corr :
                  decision[p] /= NilDecision /\ decision[p].prop.value = tx)

\* Global Stabilisation Time predicate: clocks sync + enough peers + ANCHORED
GSTReached ==
    /\ SynchronizedLocalClocks
    /\ Cardinality(active_peers) >= MIN_PEERS
    /\ state = "ANCHORED"

\* Under repeated GST, the system must eventually reach a decision
EventualDecisionUnderGST ==
    ([]<> GSTReached) ~> (\E p \in Corr : step[p] = "DECIDED")

===================================================================
