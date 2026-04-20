----------------------- MODULE EngramServer -----------------------
EXTENDS Naturals, FiniteSets, EngramTendermint, EngramFSM

CONSTANTS 
    Nodes, 
    Method, 
    Stake, 
    TotalStake, 
    ResetTime


VARIABLES 
    qcs,           \* Set of Quorum Certificates (QC)
    tcs            \* Set of Timeout Certificates (TC)

\* Combine state spaces of Tendermint, Layer 3 and FSM
vars_server == <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs, vars_fsm>>

(* 1. SERVER LAYER INITIALIZATION *)
InitServer == 
    /\ Init       \* Initialize Tendermint black box
    /\ FSM_Init   \* Initialize FSM circuit breaker sensor
    /\ qcs = {}
    /\ tcs = {}

(* 2. HOOKS USING POST-STATE (EVIDENCE') TO AVOID GHOST ERRORS *)

\* Hook 1: Supermajority Prevote reached -> Create temporary QC
Server_UponQuorumOfPrevotesAny(p) == 
    /\ UponQuorumOfPrevotesAny(p)
    \* Get the exact votes that Tendermint just added to evidence
    /\ LET NewEvidence == evidence' \ evidence 
           Voters == { m.src : m \in NewEvidence } IN
       qcs' = qcs \cup {[type |-> "QC", round |-> round[p], signers |-> Voters]}
    /\ UNCHANGED <<tcs, vars_fsm>>



\* Hook 2: Block decision finalized -> Create official Commit QC
Server_UponProposalInPrecommitNoDecision(p) ==
    /\ UponProposalInPrecommitNoDecision(p)
    /\ LET NewEvidence == evidence' \ evidence
           Committers == { m.src : m \in NewEvidence } IN
       \* Get the decision Tendermint just created to attach to the QC
       qcs' = qcs \cup {[type |-> "COMMIT_QC", round |-> decision'[p].round, method |-> decision'[p].proposal[1], signers |-> Committers]}
    /\ UNCHANGED <<tcs, vars_fsm>>



\* Hook 3: Supermajority Precommit Timeout reached -> Create TC 
Server_UponQuorumOfPrecommitsAny(p) ==
    /\ UponQuorumOfPrecommitsAny(p)
    /\ LET NewEvidence == evidence' \ evidence
           Committers == { m.src : m \in NewEvidence } IN
       tcs' = tcs \cup {[type |-> "TC", round |-> round[p], signers |-> Committers]}
    /\ UNCHANGED <<qcs, vars_fsm>>



(* 3. BRIDGE TENDERMINT ACTIONS *)
Server_PassThrough(p) ==
    \/ ReceiveProposal(p)
    \/ UponProposalInPropose(p)
    \/ UponProposalInProposeAndPrevote(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)



Server_MessageProcessing(p) ==
    \/ Server_PassThrough(p) /\ UNCHANGED <<qcs, tcs, vars_fsm>>
    \/ Server_UponQuorumOfPrevotesAny(p)
    \/ Server_UponProposalInPrecommitNoDecision(p)
    \/ Server_UponQuorumOfPrecommitsAny(p)


(* 5. GLOBAL STATE TRANSITION FUNCTION *)
NextServer == 
    \/ AdvanceRealTime /\ UNCHANGED <<qcs, tcs, vars_fsm>>
    \/ /\ SynchronizedLocalClocks 
       /\ \E p \in Corr: Server_MessageProcessing(p)
    \/ FSM_Next /\ UNCHANGED <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs>>

SpecServer == InitServer /\ [][NextServer]_vars_server



(* 6. REFINEMENT MAPPING FUNCTION *)

\* Cast to Record type to match the structure of Layer 2 (EngramConsensus)
mapped_tree == 
    LET commit_caches == {
        [
            type    |-> "C", 
            round   |-> qc.round, 
            caller  |-> CHOOSE x \in qc.signers : TRUE, \* Randomly choose one signer as caller
            method  |-> "None", 
            voters  |-> qc.signers
        ] : qc \in {q \in qcs : q.type = "COMMIT_QC"}
    }

    timeout_caches == {
        [
            type    |-> "T", 
            round   |-> tc.round,
            caller  |-> CHOOSE x \in tc.signers : TRUE, 
            method  |-> "None", 
            voters  |-> tc.signers
        ] : tc \in tcs
    }
    IN commit_caches \cup timeout_caches


mapped_fsm_state == 
    IF state \in {"ANCHORED", "SUSPICIOUS"} THEN "ANCHORED" ELSE "SOVEREIGN"



(* 7. LAYER 2 INITIALIZATION AND REFINEMENT THEOREM *)
AbstractConsensus == INSTANCE EngramConsensus WITH
    Nodes <- Nodes,
    Method <- Method,
    Stake <- Stake,
    TotalStake <- TotalStake,
    ResetTime <- ResetTime,
    tree <- mapped_tree,
    fsm_state <- mapped_fsm_state,
    round <- Max({round[n] : n \in Corr}),
    local_times <- [n \in Nodes |-> 0],
    rem_time <- 0

THEOREM Server_Refines_Consensus == SpecServer => AbstractConsensus!Spec
===================================================================