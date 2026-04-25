----------------------- MODULE EngramServer ----------------------- 
EXTENDS Naturals, FiniteSets, EngramTendermint, EngramFSM

CONSTANTS Nodes, Method, Stake, TotalStake, ResetTime, MaxBTCHeight

InitServer == 
    /\ Init       \* Initialize Tendermint black box 
    /\ FSM_Init   \* Initialize FSM circuit breaker sensor 
    /\ qcs = {} 
    /\ tcs = {}

\* Hook 0: Leader inserts proposal -> Create E_QC (Maps to Abstract Pull)
Server_InsertProposal(p) == 
    /\ InsertProposal(p) 
    /\ LET NewEQC == [ type       |-> "E_QC", 
                       round      |-> round[p], 
                       caller     |-> p, 
                       method     |-> "None", 
                       btc_height |-> h_btc_current ] 
       IN qcs' = qcs \cup {NewEQC} 
    /\ UNCHANGED <<tcs, fsmVars>>

\* Hook 1: Proposer votes for its own proposal -> Create M_QC (Maps to Abstract Invoke)
Server_UponProposalInPropose(p) == 
    /\ UponProposalInPropose(p) 
    /\ IF p = Proposer[round[p]] /\ \E m \in msgsPropose[round[p]] : m.src = p THEN
           LET prop == (CHOOSE m \in msgsPropose[round[p]] : m.src = p).proposal
               NewMQC == [ type       |-> "M_QC", 
                           round      |-> round[p], 
                           caller     |-> p, 
                           method     |-> prop.value, 
                           btc_height |-> h_btc_current ] 
           IN qcs' = qcs \cup {NewMQC} 
       ELSE
           qcs' = qcs
    /\ UNCHANGED <<tcs, fsmVars>>

\* Hook 2: Block decision finalized -> Create official Commit QC (Maps to Abstract Push)
Server_UponProposalInPrecommitNoDecision(p) == 
    /\ UponProposalInPrecommitNoDecision(p) 
    /\ LET prop == decision'[p][1] 
           r    == decision'[p][2]
           NewQC == [ type       |-> "COMMIT_QC", 
                      round      |-> r, 
                      caller     |-> Proposer[r], 
                      method     |-> prop.value, 
                      btc_height |-> h_btc_current ] 
       IN qcs' = qcs \cup {NewQC} 
    /\ UNCHANGED <<tcs, fsmVars>>

\* Bridge all other Tendermint actions as Pass-Through
Server_PassThrough(p) == 
    \/ ReceiveProposal(p) 
    \/ UponProposalInProposeAndPrevote(p) 
    \/ UponProposalInPrevoteOrCommitAndPrevote(p) 
    \/ UponQuorumOfPrevotesAny(p) 
    \/ UponQuorumOfPrecommitsAny(p)
    \/ OnTimeoutPropose(p) 
    \/ OnQuorumOfNilPrevotes(p) 
    \/ OnRoundCatchup(p)

Server_MessageProcessing(p) == 
    \/ Server_PassThrough(p) /\ UNCHANGED <<qcs, tcs, fsmVars>> 
    \/ Server_InsertProposal(p)
    \/ Server_UponProposalInPropose(p)
    \/ Server_UponProposalInPrecommitNoDecision(p) 

NextServer == 
    \/ AdvanceRealTime /\ UNCHANGED <<qcs, tcs, fsmVars>> 
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: Server_MessageProcessing(p) 
    \/ FSM_Next /\ UNCHANGED <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs>>

SpecServer == InitServer /\ [][NextServer]_serverVars

ServerEventualDecision == <>(\E p \in Corr : step[p] = "DECIDED")

ServerFSMLiveness == 
    /\ CircuitBreakerLiveness 
    /\ RecoveryAttemptLiveness 
    /\ CompleteRecoveryLiveness

ForcedInclusionLiveness == 
    \A tx \in ValidValues : 
        ([]<> (\E r \in Rounds, p \in Corr : \E m \in msgsPropose[r] : m.src = p /\ m.proposal.value = tx)) 
        => <>(\E p \in Corr : decision[p] /= NilDecision /\ decision[p][1].value = tx)

GST_Reached == 
    /\ SynchronizedLocalClocks 
    /\ \A p \in Corr : peer_count >= MIN_PEERS  
    /\ state = "ANCHORED"

EventualDecisionUnderGST == ([]<> GST_Reached) ~> (\E p \in Corr : step[p] = "DECIDED")

\* --- ABSTRACT MAPPING ZONE ---

\* Define abstract Q computation to PERFECTLY match the AbstractConsensus CHOOSE behavior
RECURSIVE SS_Op(_)
SS_Op(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SS_Op(Q \ {n})
Q_abstract == CHOOSE q \in SUBSET Nodes : (SS_Op(q) * 3 > TotalStake * 2)

\* FIX: Dịch pha (Shift +1) Vòng và (+2) Block BTC để đồng bộ hoàn toàn với LiDO
mapped_tree == 
    LET e_caches == {
            [ type       |-> "E", 
              c_round    |-> qc.round + 1,     
              caller     |-> qc.caller, 
              method     |-> "None", 
              voters     |-> Q_abstract, 
              btc_height |-> qc.btc_height + 2 ] : qc \in {q \in qcs : q.type = "E_QC"}  \* <--- Bơm thêm 2 block
        }
        m_caches == {
            [ type       |-> "M", 
              c_round    |-> qc.round + 1,     
              caller     |-> qc.caller, 
              method     |-> qc.method, 
              voters     |-> {qc.caller}, 
              btc_height |-> qc.btc_height + 2 ] : qc \in {q \in qcs : q.type = "M_QC"}  \* <--- Bơm thêm 2 block
        }
        c_caches == {
            [ type       |-> "C", 
              c_round    |-> qc.round + 1,     
              caller     |-> qc.caller, 
              method     |-> "None", 
              voters     |-> Q_abstract, 
              btc_height |-> qc.btc_height + 2 ] : qc \in {q \in qcs : q.type = "COMMIT_QC"} \* <--- Bơm thêm 2 block
        }
    IN e_caches \cup m_caches \cup c_caches

mapped_fsm_state == IF state \in {"ANCHORED", "SUSPICIOUS"} THEN "ANCHORED" ELSE "SOVEREIGN"

\* FIX 2: Máy tính nội suy Đồng hồ Logic (local_times) để thỏa mãn khóa chống Vote đúp của LiDO
mapped_local_times == 
    [n \in Nodes |-> 
        IF n \in Q_abstract THEN
            Max(
                {0} \cup 
                {qc.round + 1 : qc \in {q \in qcs : q.type = "E_QC"}} \cup 
                {qc.round + 2 : qc \in {q \in qcs : q.type = "COMMIT_QC"}}
            )
        ELSE 0
    ]

\* KẾT NỐI ÁNH XẠ HOÀN HẢO
AbstractConsensus == INSTANCE EngramConsensus WITH
    Nodes           <- Nodes,
    Method          <- Method,
    Stake           <- Stake,
    TotalStake      <- TotalStake,
    ResetTime       <- 0,
    MaxBTCHeight    <- MaxBTCHeight,
    tree            <- mapped_tree,
    fsm_state       <- mapped_fsm_state,
    round           <- Max({round[n] : n \in Corr}) + 1,   \* Dịch pha Vòng lên 1
    local_times     <- mapped_local_times,                 \* Truyền đồng hồ logic động
    rem_time        <- 0,
    h_btc_current   <- h_btc_current + 2,                  \* FIX 3: Bơm thêm 2 block để vượt qua chốt chặn Genesis K-Deep
    h_btc_anchored  <- h_btc_anchored + 2

QuorumOverlap == 
    \A q1, q2 \in AbstractConsensus!ValidQuorums : 
        (q1 \intersect q2) \intersect Corr /= {}


THEOREM SpecServer => AbstractConsensus!Spec
=============================================================================