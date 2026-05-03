-------------------- MODULE EngramTendermint ---------------------------
EXTENDS Integers, FiniteSets, EngramVars, EngramFSM

(***************************************************************************)
(* TODO [FUTURE WORK - APPENDIX]: PIPELINED TENDERMINT (PHASE MERGING)     *)
(* Goal: Block time < 2s (Optimistic Pre-Confirmations) via LiDO Appx D.   *)
(*                                                                         *)
(* Implementation Steps:                                                   *)
(* 1. REMOVE PRECOMMIT: Delete `msgsPrecommit` and related actions.        *)
(* 2. OVERLOAD PREVOTE: A `PREVOTE` referencing `r-1` acts as its commit.  *)
(* 3. DELEGATE COMMIT: Leader[r] delegates block commit to Proposer[r+1].  *)
(* 4. UPDATE LIVENESS: Committing now needs 2 consecutive honest leaders.  *)
(***************************************************************************)


(* ======================== PROTOCOL PARAMETERS ============================= *)
\* General consensus parameters
CONSTANTS
    \* @type: Set(PROCESS);
    Corr,           \* Set of correct (non-faulty) processes
    \* @type: Set(PROCESS);
    Faulty,         \* Set of Byzantine processes (may be empty)
    \* @type: Int;
    N,              \* Total number of processes: |Corr| + |Faulty|
    \* @type: Int;
    T,              \* Upper bound on the number of Byzantine processes
    \* @type: ROUND;
    MAX_ROUND,      \* Maximum round number (bounds state space for TLC)
    \* @type: ROUND -> PROCESS;
    Proposer        \* Proposer schedule: maps each round to a process


\* Timing parameters
CONSTANTS
    \* @type: TIME;
    MAX_TIMESTAMP,  \* Maximum clock value (set to large number or \infty)
    \* @type: TIME;
    MIN_TIMESTAMP,  \* Minimum clock value (starting offset)
    \* @type: TIME;
    Delay,          \* Maximum message delivery delay
    \* @type: TIME;
    Precision,      \* Maximum skew between any two correct local clocks
    \* @type: TIME;
    TimeoutDuration \* Propose-step timeout duration


\* External chain height bounds
CONSTANTS
    \* @type: Int;
    MAX_BTC_HEIGHT,     \* Bitcoin block height upper bound for TLC
    \* @type: Int;
    MAX_ENGRAM_HEIGHT,  \* Engram block height upper bound for TLC
    \* @type: Int;
    MAX_IGNORE_ROUNDS   \* Censorship threshold: rounds a tx can be ignored

ASSUME(N = Cardinality(Corr \union Faulty))


(* ======================== BASIC DEFINITIONS ============================= *)
\* @type: Set(PROCESS);
AllProcs == Corr \union Faulty      \* the set of all processes

\* @type: Set(ROUND);
Rounds == 0..MaxRound               \* the set of potential rounds
\* @type: ROUND;
NilRound == -1   \* a special value to denote a nil round, outside of Rounds
\* @type: Set(ROUND);
RoundsOrNil == Rounds \union {NilRound}

\* @type: Set(TIME);
Timestamps == 0..MaxTimestamp       \* the set of clock ticks
\* @type: TIME;
NilTimestamp == -1 \* a special value to denote a nil timestamp, outside of Ticks
\* @type: Set(TIME);
TimestampsOrNil == Timestamps \union {NilTimestamp}

\* @type: Set(STRING);
Values == {"TX_NORMAL", "TX_WITHDRAWAL"} 
\* @type: Set(STRING);
ValidValues == Values 
\* @type: STRING;
NilValue == "NIL_TX"
\* @type: SET(STRING)
ValuesOrNil == Values \union {NilValue}


(* ======================== ENGRAM TYPE VARS ============================= *)
\* @type: Set(STR);
FSMStates == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}
\* @type: STR
NilFSMState == "NONE"
\* @type: Set(STR);
FSMStatesOrNil == FSMState \union NilFSMState


\* @type: Set(Int);
BTCHeights == 0..MaxBTCHeight
\* @type: Int;
NilBTCHeight == -1
\* @type: Set(BTC_RECEIPT);
BTCReceipts == [ 
    checkpoint_block_height : BTCHeights,   \* Height of the Bitcoin block containing the OP_RETURN tx
    checkpoint_block_hash   : STRING        \* Hash of the Bitcoin block containing the Engram Checkpoint (OP_RETURN tx)
]
\* @type: BTC_RECEIPT;
NilBTCReceipt == [ 
    checkpoint_block_height     |-> NilBTCHeight, 
    checkpoint_block_hash       |-> "NilHash" 
]
\* @type: Set(BTC_RECEIPT);
BTCReceiptsOrNil == BTCReceipts \union NilBTC_Receipt


\* @type: Set(Int);
DAHeights == 0..MaxEngramHeight
\* @type: Int;
NilDAHeights == -1
\* @type: Set(DA_RECEIPT);
DAReceipts == [
    published_block_height: DAHeights,       \* Height of published block N-k
    attestation: BOOLEAN                     \* Verification from Blobstream
]
\* @type: DA_RECEIPT;
NilDAReceipt == [
    published_block_height      |-> -1,
    attestation                 |-> FALSE 
]
\* @type: Set(DA_RECEIPT);
DAReceiptsOrNil == DA_Heights \union NilDA_Receipt

(* ======================== PROPOSAL & DECISION STRUCTURE ============================= *)
\* @type: Set(PROPOSAL);
Proposals == [
    value: ValuesOrNil,
    timestamp: TimestampsOrNil,
    round: RoundsOrNil,
    fsm_state: FSMStatesOrNil,
    da_receipt: DAReceiptsOrNil,
    btc_receipt: BTCReceiptsOrNil,
    zk_proof_ref: BOOLEAN 
]
\* @type: PROPOSAL;
NilProposal == [ 
    value           |-> NilValue, 
    timestamp       |-> NilTimestamp, 
    round           |-> NilRound, 
    fsm_state       |-> NilFSMState, 
    da_receipt      |-> NilDAReceipt, 
    btc_receipt     |-> NilBTCReceipt,
    zk_proof_ref    |-> FALSE   
]
\* @type: Set(DECISION);
Decisions == [
    prop: Proposals,
    round: Rounds  \* The round where the decision is made
]
\* @type: DECISION;
NilDecision == [
    prop  |-> NilProposal,
    round |-> NilRound
]

(* ======================== QUORUM THRESHOLDS ============================== *)
\* @type: Int;
THRESHOLD1 == T + 1       \* f+1: at least one correct process
\* @type: Int;
THRESHOLD2 == 2 * T + 1   \* 2f+1: quorum (requires N > 3T)

(* ======================== BASIC MATH HELPERS ============================= *)
\* a value hash is modeled as identity
\* @type: (t) => t;
Id(v) == v

\* @type: (TIME, TIME) => TIME;
Min2(a,b) == IF a <= b THEN a ELSE b
\* @type: (Set(TIME)) => TIME;
\* Min(S) == FoldSet( Min2, MaxTimestamp, S )
Min(S) == CHOOSE x \in S : \A y \in S : x <= y

\* @type: (TIME, TIME) => TIME;
Max2(a,b) == IF a >= b THEN a ELSE b
\* @type: (Set(TIME)) => TIME;
\* Max(S) == FoldSet( Max2, NilTimestamp, S )
Max(S) == CHOOSE x \in S : \A y \in S : y <= x

\* @type: (Set(MESSAGE)) => Int;
\* Card(S) == 
\*   LET 
\*     \* @type: (Int, MESSAGE) => Int;
\*     PlusOne(i, m) == i + 1
\*   IN FoldSet( PlusOne, 0, S )
Card(S) == Cardinality(S)


(********************* TIME UTILITIES ******************************)
\* Checks that t has not exceeded the model's timestamp bound.
\* Set MAX_TIMESTAMP to a large value to model an unbounded clock.
\* @type: (TIME) => Bool;
ValidTime(t) == t < MAX_TIMESTAMP


\* Clock-synchrony predicate: a message is timely if it arrives within the
\* [messageTime - Precision, messageTime + Precision + Delay] window.
\* @type: (TIME, TIME) => Bool;
IsTimely(processTime, messageTime) ==
    /\ processTime >= messageTime - Precision
    /\ processTime <= messageTime + Precision + Delay


\* TRUE if all pairs of correct clocks are within Precision of each other.
\* @type: Bool;
SynchronizedLocalClocks ==
    \A p \in Corr : \A q \in Corr :
        p /= q =>
            \/ /\ local_clock[p] >= local_clock[q]
               /\ local_clock[p] - local_clock[q] < Precision
            \/ /\ local_clock[p] <  local_clock[q]
               /\ local_clock[q] - local_clock[p] < Precision

(********************* DYNAMIC TOLERANCE CALCULATION *********************)
\* The tolerance expands dynamically based on the Consensus Round.
\* It only applies to exogenous physical metrics (DA Blobstream & Bitcoin SPV).
DATolerance(round) ==
    CASE round <= 1 -> 0
      [] round = 2  -> 2
      [] round >= 3 -> 4
      [] OTHER  -> 0

BTCTolerance(round) ==
    CASE round <= 2 -> 0
      [] round >= 3 -> 1
      [] OTHER  -> 0



(* ======================== PROPOSAL HELPERS ================================ *)
\* TRUE if the proposal value is a cross-chain withdrawal transaction
\* @type: (STRING) => Bool;
ContainsWithdrawal(propVal) == propVal = "TX_WITHDRAWAL"

\* Black-box verification: O(1) time complexity simulation for ZK-Proofs
\* @type: (PROPOSAL) => Bool;
VerifyZkProof(prop) == 
    /\ prop.zk_proof_ref = TRUE                                     \* Leader claims proof exists
    /\ prop.da_receipt.attestation = TRUE                           \* DA layer confirms data is available
    /\ prop.da_receipt.published_block_height > h_engram_verified   \* Check if the proof corresponds to the recovery target


(********************* CORE PROPOSAL VALIDITY (SEMANTIC FIREWALL) ******************************)
\* The core validity predicate for proposals
\* @type: (PROPOSAL) => Bool;
IsValidProposal(prop) == 
    LET 
        da_tol  == DATolerance(prop.round)
        btc_tol == BTCTolerance(prop.round)
    IN
        /\ prop.value \in ValidValues
        /\ prop.timestamp \in MinTimestamp..MaxTimestamp
        /\ prop.fsm_state = CalculateNextFSMState   \* Cross-check
        
        \* DA Pipeline Check: Data must be available and within the allowed gap
        /\ (prop.fsm_state \in {"ANCHORED", "RECOVERING"}) => 
            /\ prop.da_receipt.attestation = TRUE
            /\ prop.da_receipt.published_block_height <= h_engram_current
            /\ prop.da_receipt.published_block_height >= (h_engram_current - T_DA - da_tol)

        
        \* Settlement Monotonicity Check: BTC anchor height cannot go backwards
        /\ prop.btc_receipt.checkpoint_block_height >= h_btc_anchored
        /\ prop.btc_receipt.checkpoint_block_height >= (h_btc_current - btc_tol)
        /\ prop.btc_receipt.checkpoint_block_height <= h_btc_current

        \* Verify hash code against Bitcoin Reorg/Eclipse
        \* /\ prop.btc_receipt.blockHash = ExpectedBlockHash(prop.btc_receipt.blockHeight)

        \* Economic Circuit Breaker: Halt all cross-chain withdrawals during partition
        /\ (prop.fsm_state = "SOVEREIGN") => ~ContainsWithdrawal(prop.value)
        
        \* RE-ANCHORING LOGIC: Mandatory ZK-Proof when hysteresis wait is met
        \* If not met, strict enforcement that no fake ZK-proof is attached.
        /\ IF prop.fsm_state = "RECOVERING" /\ safe_blocks = HYSTERESIS_WAIT 
        THEN VerifyZkProof(prop)
        ELSE prop.zk_proof_ref = FALSE


\* Censorship sensor: TRUE iff process p should reject proposal for being censored
\* @type: (PROCESS, PROPOSAL) => Bool;
IsCensoring(p, prop) ==
    \E tx \in forced_tx_queue :
        /\ tx_ignored_rounds[p][tx] >= MAX_IGNORE_ROUNDS
        /\ prop.value /= tx


(* ======================== RECORD CONSTRUCTORS ============================ *)
\* @type: (VALUE, TIME, ROUND, STRING, DA_RECEIPT, Int, Bool) => PROPOSAL;
Proposal(v, t, r, fsm_s, da_receipt, h_btc, has_proof) ==
    [
        value        |-> v,
        timestamp    |-> t,
        round        |-> r,
        fsm_state    |-> fsm_s,
        da_receipt   |-> da_receipt,
        \* TODO: refactor all things related to Proposal
        btc_receipt  |-> [ checkpoint_block_height |-> h_btc,
                            checkpoint_block_hash   |-> "hash" ],
        zk_proof_ref |-> has_proof
    ]

\* @type: (PROPOSAL, ROUND) => DECISION;
Decision(prop, r) ==
    [
        prop  |-> prop,
        round |-> r
    ]


(* ======================== BYZANTINE MESSAGE SETS ========================= *)
\* Pre-populate message buffers with faulty nodes' default messages so they
\* can immediately contribute to quorums (modelling BFT adversary capability).
\* Only T × MAX_ROUND messages total — negligible state space cost.

\* @type: (ROUND) => Set(MESSAGE);
FaultyTimeouts(r) ==
    { [type |-> "TIMEOUT",    src |-> f, round |-> r] : f \in Faulty }

\* @type: (ROUND) => Set(MESSAGE);
FaultyPrevotes(r) ==
    { [type |-> "PREVOTE",   src |-> f, round |-> r, id |-> Id(NilProposal)] : f \in Faulty }

\* @type: (ROUND) => Set(MESSAGE);
FaultyPrecommits(r) ==
    { [type |-> "PRECOMMIT", src |-> f, round |-> r, id |-> Id(NilProposal)] : f \in Faulty }

(* ======================== INITIALIZATION ================================= *)
\* Helper: set of all structurally valid proposal messages for round r
\* @type: (ROUND) => Set(PROPMESSAGE);
RoundProposals(r) ==
    [
    type      : {"PROPOSAL"}, 
    src       : AllProcs,
    round     : {r}, 
    proposal  : Proposals, 
    validRound: RoundsOrNil
    ]

\* Sanity check: message function contains only messages for their own round
\* @type: (ROUND -> Set(MESSAGE)) => Bool;
BenignRoundsInMessages(msgfun) ==
  \* the message function never contains a message for a wrong round
  \A r \in Rounds:
    \A m \in msgfun[r]:
      r = m.round

\* Initial state — some Byzantine messages may already be present
TM_Init ==
    /\ round              = [p \in Corr |-> 0]
    /\ local_clock       \in [Corr -> MIN_TIMESTAMP..(MIN_TIMESTAMP + Precision)]
    /\ local_rem_time     = [p \in Corr |-> TimeoutDuration]
    /\ real_time          = 0
    /\ step               = [p \in Corr |-> "PROPOSE"]
    /\ decision           = [p \in Corr |-> NilDecision]
    /\ lockedValue        = [p \in Corr |-> NilValue]
    /\ lockedRound        = [p \in Corr |-> NilRound]
    /\ validValue         = [p \in Corr |-> NilProposal]
    /\ validRound         = [p \in Corr |-> NilRound]
    /\ msgsPropose        = [r \in Rounds |-> {}]
    /\ msgsPrevote        = [r \in Rounds |-> FaultyPrevotes(r)]
    /\ msgsPrecommit      = [r \in Rounds |-> FaultyPrecommits(r)]
    /\ msgsTimeout        = [r \in Rounds |-> FaultyTimeouts(r)]
    /\ receivedTimelyProposal = [p \in Corr |-> {}]
    /\ inspectedProposal      = [r \in Rounds, p \in Corr |-> NilTimestamp]
    /\ BenignRoundsInMessages(msgsPropose)
    /\ BenignRoundsInMessages(msgsPrevote)
    /\ BenignRoundsInMessages(msgsPrecommit)
    /\ evidence           = {}
    /\ action             = "Init"
    /\ beginRound         = [r \in Rounds |->
                                IF r = 0
                                THEN Min({local_clock[p] : p \in Corr})
                                ELSE MAX_TIMESTAMP]
    /\ endConsensus       = [p \in Corr |-> NilTimestamp]
    /\ lastBeginRound     = [r \in Rounds |->
                                IF r = 0
                                THEN Max({local_clock[p] : p \in Corr})
                                ELSE NilTimestamp]
    /\ proposalTime         = [r \in Rounds |-> NilTimestamp]
    /\ proposalReceivedTime = [r \in Rounds |-> NilTimestamp]
    /\ forced_tx_queue      = {"TX_NORMAL"}
    /\ tx_ignored_rounds    = [p \in Corr |-> [tx \in ValidValues |-> 0]]


(* ======================== MESSAGE BROADCAST HELPERS ====================== *)
\* @type: (PROCESS, ROUND, PROPOSAL, ROUND) => Bool;
BroadcastProposal(pSrc, pRound, pProposal, pValidRound) ==
    LET
        \* @type: PROPMESSAGE;
        newMsg == [
            type       |-> "PROPOSAL",
            src        |-> pSrc,
            round      |-> pRound,
            proposal   |-> pProposal,
            validRound |-> pValidRound
        ]
    IN
    msgsPropose' = [msgsPropose EXCEPT ![pRound] = msgsPropose[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND, PROPOSAL) => Bool;
BroadcastPrevote(pSrc, pRound, pId) ==
    LET
        \* @type: PREMESSAGE;
        newMsg == [
            type  |-> "PREVOTE",
            src   |-> pSrc,
            round |-> pRound,
            id    |-> pId
        ]
    IN
    msgsPrevote' = [msgsPrevote EXCEPT ![pRound] = msgsPrevote[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND, PROPOSAL) => Bool;
BroadcastPrecommit(pSrc, pRound, pId) ==
    LET
        \* @type: PREMESSAGE;
        newMsg == [
            type  |-> "PRECOMMIT",
            src   |-> pSrc,
            round |-> pRound,
            id    |-> pId
        ]
    IN
    msgsPrecommit' = [msgsPrecommit EXCEPT ![pRound] = msgsPrecommit[pRound] \union {newMsg}]

\* @type: (PROCESS, ROUND) => Bool;
BroadcastTimeout(pSrc, pRound) ==
    LET
        newMsg == [
            type  |-> "TIMEOUT",
            src   |-> pSrc,
            round |-> pRound
        ]
    IN
    msgsTimeout' = [msgsTimeout EXCEPT ![pRound] = msgsTimeout[pRound] \union {newMsg}]


(* ======================== ROUND MANAGEMENT ================================ *)
\* Increment ignored-round counters for all pending forced transactions
UpdateIgnoredRounds(p) ==
    tx_ignored_rounds' = [tx_ignored_rounds EXCEPT ![p] = 
        [tx \in ValidValues |-> 
            IF tx \in forced_tx_queue 
            THEN tx_ignored_rounds[p][tx] + 1 
            ELSE tx_ignored_rounds[p][tx]
        ]
    ]

\* Move process p to round r, resetting its step and timeout
\* @type: (PROCESS, ROUND) => Bool;
StartRound(p, r) ==
   /\ step[p] /= "DECIDED" \* a decided process does not participate in consensus
   /\ round' = [round EXCEPT ![p] = r]
   /\ step' = [step EXCEPT ![p] = "PROPOSE"]
   \* We only need to update (last)beginRound[r] once a process enters round `r`
   /\ beginRound' = [beginRound EXCEPT ![r] = Min2(@, localClock[p])]
   /\ lastBeginRound' = [lastBeginRound EXCEPT ![r] = Max2(@, localClock[p])]

   /\ localRemTime' = [localRemTime EXCEPT ![p] = TimeoutDuration]
   /\ UpdateIgnoredRounds(p)

(* ======================== PROTOCOL ACTIONS ================================ *)

\* -- InsertProposal: called by EngramServer to inject a pre-built proposal --
\* @type: (PROCESS, PROPOSAL) => Bool;
InsertProposal(p, prop) ==
    LET r == round[p] IN
    /\ p = Proposer[r]
    /\ step[p] = "PROPOSE"
    /\ \A m \in msgsPropose[r] : m.src /= p
    /\ BroadcastProposal(p, r, prop, validRound[p])
    /\ IsValidProposal(prop)
    /\ proposalTime' = [proposalTime EXCEPT ![r] = real_time]
    /\ UNCHANGED <<temporalVars, coreVars, fsmVars, censorVars>>
    /\ UNCHANGED <<msgsPrevote, msgsPrecommit, msgsTimeout, evidence,
                   receivedTimelyProposal, inspectedProposal>>
    /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalReceivedTime>>
    /\ action' = "InsertProposal"


\* -- ReceiveProposal: time-bounded proposal buffer (IsTimely filter) --
\* @type: (PROCESS) => Bool;
ReceiveProposal(p) ==
    LET r == round[p] IN
    \E msg \in msgsPropose[r] :
        /\ msg.type       = "PROPOSAL"
        /\ msg.src        = Proposer[r]
        /\ msg.validRound = NilRound
        /\ inspectedProposal[r, p] = NilTimestamp
        /\ msg \notin receivedTimelyProposal[p]
        /\ inspectedProposal' = [inspectedProposal EXCEPT ![r, p] = local_clock[p]]
        /\ LET isTimely == IsTimely(local_clock[p], msg.proposal.timestamp) IN
               \/ /\ isTimely
                  /\ receivedTimelyProposal' =
                         [receivedTimelyProposal EXCEPT ![p] = @ \union {msg}]
                  /\ LET isNilTimestamp == proposalReceivedTime[r] = NilTimestamp IN
                         \/ /\ isNilTimestamp
                            /\ proposalReceivedTime' =
                                   [proposalReceivedTime EXCEPT ![r] = real_time]
                         \/ /\ ~isNilTimestamp
                            /\ UNCHANGED proposalReceivedTime
               \/ /\ ~isTimely
                  /\ UNCHANGED <<receivedTimelyProposal, proposalReceivedTime>>
        /\ UNCHANGED <<temporalVars, coreVars, fsmVars, censorVars>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence>>
        /\ UNCHANGED <<beginRound, endConsensus, lastBeginRound, proposalTime>>
        /\ action' = "ReceiveProposal"


\* -- UponProposalInPropose: gatekeeper — evaluates proposal validity and votes --
\* If censorship detected: broadcast timeout and skip to next round.
\* Otherwise: PREVOTE for the proposal (or Nil if invalid).
\* @type: (PROCESS) => Bool;
UponProposalInPropose(p) ==
    LET r == round[p] IN
    \E msg \in receivedTimelyProposal[p] :
        /\ msg.type       = "PROPOSAL"
        /\ msg.round      = r
        /\ msg.src        = Proposer[r]
        /\ msg.validRound = NilRound
        /\ step[p]        = "PROPOSE"
        /\ evidence' = {msg} \union evidence
        /\ LET
               prop == msg.proposal
           IN
           IF IsCensoring(p, prop)
           THEN
               \* Censorship branch: reject and force round advance
               /\ BroadcastTimeout(p, r)
               /\ StartRound(p, r + 1)
               /\ UNCHANGED <<lockedValue, lockedRound, validValue, validRound, decision>>
               /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit,
                              receivedTimelyProposal, inspectedProposal>>
               /\ UNCHANGED <<local_clock, real_time>>
               /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
               /\ UNCHANGED <<fsmVars, forced_tx_queue>>
           ELSE
               \* Normal branch: vote for proposal or Nil
               /\ LET vote_target ==
                      IF IsValidProposal(prop)
                         /\ (lockedRound[p] = NilRound \/ lockedValue[p] = prop.value)
                      THEN prop
                      ELSE NilProposal
                  IN BroadcastPrevote(p, r, vote_target)
               /\ step' = [step EXCEPT ![p] = "PREVOTE"]
               /\ UNCHANGED <<round, decision, lockedValue, lockedRound,
                              validValue, validRound>>
               /\ UNCHANGED <<msgsPropose, msgsPrecommit, msgsTimeout,
                              receivedTimelyProposal, inspectedProposal>>
               /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
        /\ action' = "UponProposalInPropose"


\* -- UponProposalInProposeAndPrevote: handles re-proposed locked values --
\* Triggered when proposal.validRound >= 0 (network locked in a prior round).
\* @type: (PROCESS) => Bool;
UponProposalInProposeAndPrevote(p) ==
    LET r == round[p] IN
    \E msg \in msgsPropose[r] :
        /\ msg.type       = "PROPOSAL"
        /\ msg.src        = Proposer[r]
        /\ msg.validRound >= 0 /\ msg.validRound < r
        /\ step[p]        = "PROPOSE"
        /\ LET
               prop == msg.proposal
               vr   == msg.validRound
               PV   == { m \in msgsPrevote[vr] : m.id = Id(prop) }
           IN
           /\ Cardinality(PV) >= THRESHOLD2
           /\ evidence' = PV \union {msg} \union evidence
           /\ LET mid ==
                  IF IsValidProposal(prop)
                     /\ (lockedRound[p] <= vr \/ lockedValue[p] = prop.value)
                  THEN Id(prop)
                  ELSE NilProposal
              IN BroadcastPrevote(p, r, mid)
        /\ step' = [step EXCEPT ![p] = "PREVOTE"]
        /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
        /\ UNCHANGED <<msgsPropose, msgsPrecommit, msgsTimeout,
                       receivedTimelyProposal, inspectedProposal>>
        /\ action' = "UponProposalInProposeAndPrevote"


\* -- UponQuorumOfPrevotesAny: 2f+1 PREVOTEs for anything -> advance to PRECOMMIT --
\* @type: (PROCESS) => Bool;
UponQuorumOfPrevotesAny(p) ==
    /\ step[p] = "PREVOTE"
    /\ \E MyEvidence \in SUBSET msgsPrevote[round[p]] :
           LET Voters == { m.src : m \in MyEvidence } IN
           /\ Cardinality(Voters) >= THRESHOLD2
           /\ evidence' = MyEvidence \union evidence
           /\ BroadcastPrecommit(p, round[p], NilProposal)
           /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
           /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
           /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
           /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsTimeout,
                          receivedTimelyProposal, inspectedProposal>>
           /\ action' = "UponQuorumOfPrevotesAny"


\* -- UponProposalInPrevoteOrCommitAndPrevote: 2f+1 PREVOTEs for a specific value -> LOCK --
\* @type: (PROCESS) => Bool;
UponProposalInPrevoteOrCommitAndPrevote(p) ==
    LET r == round[p] IN
    \E msg \in msgsPropose[r] :
        /\ msg.type = "PROPOSAL"
        /\ msg.src  = Proposer[r]
        /\ step[p] \in {"PREVOTE", "PRECOMMIT"}
        /\ LET
               prop == msg.proposal
               PV   == { m \in msgsPrevote[r] : m.id = Id(prop) }
           IN
           /\ Cardinality(PV) >= THRESHOLD2
           /\ evidence' = PV \union {msg} \union evidence
           /\ IF step[p] = "PREVOTE"
              THEN
                  /\ lockedValue'  = [lockedValue  EXCEPT ![p] = prop.value]
                  /\ lockedRound'  = [lockedRound  EXCEPT ![p] = r]
                  /\ BroadcastPrecommit(p, r, Id(prop))
                  /\ step'         = [step EXCEPT ![p] = "PRECOMMIT"]
                  /\ UNCHANGED <<validValue, validRound>>
              ELSE
                  /\ validValue'   = [validValue  EXCEPT ![p] = prop]
                  /\ validRound'   = [validRound  EXCEPT ![p] = r]
                  /\ UNCHANGED <<lockedValue, lockedRound, msgsPrecommit, step>>
        /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED <<round, decision>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsTimeout,
                       receivedTimelyProposal, inspectedProposal>>
        /\ action' = "UponProposalInPrevoteOrCommitAndPrevote"


\* -- UponQuorumOfPrecommitsAny: 2f+1 PRECOMMITs without decision -> next round --
\* @type: (PROCESS) => Bool;
UponQuorumOfPrecommitsAny(p) ==
    /\ \E MyEvidence \in SUBSET msgsPrecommit[round[p]] :
           LET Committers == { m.src : m \in MyEvidence } IN
           /\ Cardinality(Committers) >= THRESHOLD2
           /\ evidence' = MyEvidence \union evidence
           /\ round[p] + 1 \in Rounds
           /\ StartRound(p, round[p] + 1)
           /\ UNCHANGED <<local_clock, real_time>>
           /\ UNCHANGED <<fsmVars>>
           /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
           /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound>>
           /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout,
                          receivedTimelyProposal, inspectedProposal>>
           /\ UNCHANGED <<forced_tx_queue>>
           /\ action' = "UponQuorumOfPrecommitsAny"
                        


\* -- UponProposalInPrecommitNoDecision: commit function — 2f+1 PRECOMMITs for a value --
\* @type: (PROCESS) => Bool;
UponProposalInPrecommitNoDecision(p) ==
    LET r == round[p] IN
    \E msg \in msgsPropose[r] :
        /\ msg.type  = "PROPOSAL"
        /\ msg.src   = Proposer[r]
        /\ decision[p] = NilDecision
        /\ inspectedProposal[r, p] /= NilTimestamp
        /\ LET
               prop == msg.proposal
               PV   == { m \in msgsPrecommit[r] : m.id = Id(prop) }
           IN
           /\ Cardinality(PV) >= THRESHOLD2
           /\ evidence' = PV \union {msg} \union evidence
           /\ decision' = [decision EXCEPT ![p] = Decision(prop, r)]
        /\ endConsensus' = [endConsensus EXCEPT ![p] = local_clock[p]]
        /\ step'         = [step EXCEPT ![p] = "DECIDED"]
        /\ UNCHANGED <<temporalVars, fsmVars, censorVars>>
        /\ UNCHANGED <<round, lockedValue, lockedRound, validValue, validRound>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout,
                       receivedTimelyProposal, inspectedProposal>>
        /\ UNCHANGED <<beginRound, lastBeginRound, proposalTime, proposalReceivedTime>>
        /\ action' = "UponProposalInPrecommitNoDecision"


\* -- OnTimeoutPropose: node is not leader, proposal timed out -> PREVOTE Nil --
\* @type: (PROCESS) => Bool;
OnTimeoutPropose(p) ==
    /\ step[p] = "PROPOSE"
    /\ p /= Proposer[round[p]]
    /\ BroadcastPrevote(p, round[p], NilProposal)
    /\ step' = [step EXCEPT ![p] = "PREVOTE"]
    /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
    /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
    /\ UNCHANGED <<msgsPropose, msgsPrecommit, msgsTimeout,
                   evidence, receivedTimelyProposal, inspectedProposal>>
    /\ action' = "OnTimeoutPropose"


\* -- OnQuorumOfNilPrevotes: 2f+1 nil PREVOTEs -> PRECOMMIT Nil --
\* @type: (PROCESS) => Bool;
OnQuorumOfNilPrevotes(p) ==
    /\ step[p] = "PREVOTE"
    /\ LET PV == { m \in msgsPrevote[round[p]] : m.id = Id(NilProposal) } IN
           /\ Cardinality(PV) >= THRESHOLD2
           /\ evidence' = PV \union evidence
           /\ BroadcastPrecommit(p, round[p], Id(NilProposal))
           /\ step' = [step EXCEPT ![p] = "PRECOMMIT"]
           /\ UNCHANGED <<temporalVars, invariantVars, fsmVars, censorVars>>
           /\ UNCHANGED <<round, decision, lockedValue, lockedRound, validValue, validRound>>
           /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsTimeout,
                          receivedTimelyProposal, inspectedProposal>>
           /\ action' = "OnQuorumOfNilPrevotes"


\* -- OnRoundCatchup: fast-forward — f+1 messages from higher round observed --
\* @type: (PROCESS) => Bool;
OnRoundCatchup(p) ==
    \E r \in {rr \in Rounds : rr > round[p]} :
        LET RoundMsgs ==
                msgsPropose[r] \union msgsPrevote[r] \union msgsPrecommit[r]
        IN
        \E MyEvidence \in SUBSET RoundMsgs :
            LET Faster == { m.src : m \in MyEvidence } IN
            /\ Cardinality(Faster) >= THRESHOLD1
            /\ evidence' = MyEvidence \union evidence
            /\ StartRound(p, r)
            /\ UNCHANGED <<temporalVars, fsmVars>>
            /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
            /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound>>
            /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout,
                           receivedTimelyProposal, inspectedProposal>>
            /\ UNCHANGED <<forced_tx_queue>>
            /\ action' = "OnRoundCatchup"


\* -- UponfPlusOneTimeoutsAny: f+1 timeout messages from higher round -> advance --
\* @type: (PROCESS) => Bool;
UponfPlusOneTimeoutsAny(p) ==
    \E r \in {rr \in Rounds : rr > round[p]} :
        \E MyEvidence \in SUBSET msgsTimeout[r] :
            LET Timers == { m.src : m \in MyEvidence } IN
            /\ Cardinality(Timers) >= THRESHOLD1
            /\ evidence' = MyEvidence \union evidence
            /\ StartRound(p, r)
            /\ UNCHANGED <<local_clock, real_time>>
            /\ UNCHANGED <<endConsensus, proposalTime, proposalReceivedTime>>
            /\ UNCHANGED <<decision, lockedValue, lockedRound, validValue, validRound>>
            /\ UNCHANGED <<forced_tx_queue>>
            /\ UNCHANGED <<fsmVars>>
            /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout,
                           receivedTimelyProposal, inspectedProposal>>
            /\ action' = "UponfPlusOneTimeoutsAny"

\* -- OnLocalTimerExpire: local countdown reached zero → broadcast timeout --
\* @type: (PROCESS) => Bool;
OnLocalTimerExpire(p) ==
    /\ local_rem_time[p] = 0
    /\ BroadcastTimeout(p, round[p])
    /\ UNCHANGED <<coreVars, temporalVars, fsmVars, invariantVars, censorVars>>
    /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, evidence,
                   receivedTimelyProposal, inspectedProposal>>
    /\ action' = "OnLocalTimerExpire"


(* ======================== CLOCK ADVANCE ==================================== *)
\* Advance the global real_time and update all local clocks and timers accordingly
AdvanceRealTime ==
    /\ ValidTime(realTime)
    /\ \E t \in Timestamps:
        /\ t > realTime
        /\ realTime' = t
        /\ localClock' = [p \in Corr |-> localClock[p] + (t - realTime)]
        /\ localRemTime' = [p \in Corr |->
               IF localRemTime[p] > 0 /\ ~\E m \in msgsPropose[round[p]]: m.src = Proposer[round[p]]
               THEN localRemTime[p] - 1
               ELSE localRemTime[p]]
        /\ UNCHANGED <<coreVars, invariantVars, fsmVars, censorVars>>
        /\ UNCHANGED <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout, evidence, receivedTimelyProposal, inspectedProposal>>
        /\ action' = "AdvanceRealTime"
    

(* ======================== MESSAGE DISPATCH ================================= *)
\* Aggregate all per-process message-processing actions
\* process timely messages
\* @type: (PROCESS) => Bool;
MessageProcessing(p) ==
    \* start round
    \* \/ InsertProposal(p)
    \* reception step
    \/ ReceiveProposal(p)
    \* processing step
    \/ UponProposalInPropose(p)
    \/ UponProposalInProposeAndPrevote(p)
    \/ UponQuorumOfPrevotesAny(p)
    \/ UponProposalInPrevoteOrCommitAndPrevote(p)
    \/ UponQuorumOfPrecommitsAny(p)
    \/ UponProposalInPrecommitNoDecision(p)
    \* the actions below are not essential for safety, but added for completeness
    \/ OnTimeoutPropose(p)
    \/ OnQuorumOfNilPrevotes(p)
    \/ OnRoundCatchup(p)
    \/ UponfPlusOneTimeoutsAny(p)
    \/ OnLocalTimerExpire(p)


(* ======================== ADVERSARY ACTIONS ================================ *)
\* Byzantine Data-Withholding Attack: faulty leader broadcasts a structurally
\* valid proposal but sets attestation = FALSE (data is not actually available).
Byzantine_Data_Withholding ==
    \E r \in Rounds :
        /\ Proposer[r] \in Faulty
        /\ msgsPropose[r] = {}
        /\ LET
               bad_da   == [published_block_height |-> 999, attestation |-> FALSE]
               bad_prop == Proposal("TX_NORMAL", MIN_TIMESTAMP, r, state,
                                    bad_da, h_btc_current, FALSE)
               bad_msg  == [type       |-> "PROPOSAL",
                            src        |-> Proposer[r],
                            round      |-> r,
                            proposal   |-> bad_prop,
                            validRound |-> NilRound]
           IN
           /\ msgsPropose' = [msgsPropose EXCEPT ![r] = msgsPropose[r] \union {bad_msg}]
           /\ UNCHANGED <<coreVars, temporalVars, fsmVars, invariantVars, censorVars>>
           /\ UNCHANGED <<msgsPrevote, msgsPrecommit, msgsTimeout>>
           /\ UNCHANGED <<evidence, action, receivedTimelyProposal, inspectedProposal>>


\* Censorship Resistance: injects a new transaction into the forced inclusion queue
SubmitToCelestiaDA ==
    \E tx \in ValidValues \ forced_tx_queue :
        /\ forced_tx_queue' = forced_tx_queue \union {tx}
        /\ UNCHANGED <<coreVars, temporalVars, bookkeepingVars, invariantVars, fsmVars>>
        /\ UNCHANGED <<tx_ignored_rounds>>


(* ======================== NEXT-STATE RELATION ============================= *)
(*
 * Note: the system may eventually deadlock (e.g., all processes decide).
 * This is intentional — the spec focuses on safety, not liveness.
 *)
TM_Next ==
    \/ AdvanceRealTime
    \/ /\ SynchronizedLocalClocks
       /\ \E p \in Corr : MessageProcessing(p)
    \/ Byzantine_Data_Withholding
    \/ SubmitToCelestiaDA


(* ======================== SAFETY INVARIANTS =============================== *)
\* TypeOK: type domain for all Tendermint-owned variables
TypeOK ==
    /\ \A p \in Corr :
           /\ round[p]       \in Rounds
           /\ step[p]        \in {"PROPOSE", "PREVOTE", "PRECOMMIT", "DECIDED"}
           /\ decision[p]    \in Decisions \union {NilDecision}
           /\ lockedValue[p] \in ValuesOrNil
           /\ lockedRound[p] \in RoundsOrNil
           /\ validValue[p]  \in Proposals \union {NilProposal}
           /\ validRound[p]  \in RoundsOrNil
    /\ \A r \in Rounds :
           /\ \A m \in msgsPropose[r]   : m.round = r
           /\ \A m \in msgsPrevote[r]   : m.round = r
           /\ \A m \in msgsPrecommit[r] : m.round = r

\* I1: All decided correct processes agree on the same value
AgreementOnValue ==
    \A p, q \in Corr :
        /\ decision[p] /= NilDecision
        /\ decision[q] /= NilDecision
        => decision[p].prop.value = decision[q].prop.value

\* I2: Decided timestamp falls within the consensus round interval
ConsensusTimeValid ==
    \A p \in Corr :
        decision[p] /= NilDecision =>
            LET
                r == decision[p].prop.round
                t == decision[p].prop.timestamp
            IN
            /\ beginRound[r] - Precision - Delay <= t
            /\ t <= endConsensus[p] + Precision

\* I3: If the proposer is correct, timestamp >= round begin time
ConsensusSafeValidCorrProp ==
    \A p \in Corr :
        decision[p] /= NilDecision =>
            LET
                pr == decision[p].prop.round
                t  == decision[p].prop.timestamp
            IN
            (Proposer[pr] \in Corr) => beginRound[pr] <= t

\* I4: Every decided proposal must pass the application-level validity predicate
HybridSafety ==
    \A p \in Corr :
        decision[p] /= NilDecision => IsValidProposal(decision[p].prop)

\* I5: Only valid domain values can be decided (no garbage)
ExternalValidity ==
    \A p \in Corr :
        decision[p] /= NilDecision => decision[p].prop.value \in ValidValues


(* ======================== EOTS SLASHING / ACCOUNTABILITY ================== *)
\* Double-signing evidence: two distinct messages from the same process in the
\* same round — triggers EOTS slashing in the Babylon layer.
DoubleSigningEvidence ==
    \E r \in Rounds, p \in AllProcs :
        \/ \E m1, m2 \in msgsPrevote[r] :
               /\ m1.src = p /\ m2.src = p /\ m1.id /= m2.id
        \/ \E m1, m2 \in msgsPrecommit[r] :
               /\ m1.src = p /\ m2.src = p /\ m1.id /= m2.id
        \/ \E m1, m2 \in msgsPropose[r] :
               /\ m1.src = p /\ m2.src = p /\ m1.proposal /= m2.proposal

\* I6: Fork accountability — if agreement breaks, a double-signer exists
Accountability ==
    (~AgreementOnValue) => DoubleSigningEvidence


(* ======================== MASTER INVARIANT ================================ *)
\* Combine all core invariants for convenient TLC checking
CoreTendermintInv ==
    /\ TypeOK
    /\ AgreementOnValue
    /\ ConsensusTimeValid
    /\ ConsensusSafeValidCorrProp
    /\ HybridSafety
    /\ ExternalValidity
    /\ Accountability


(* ======================== SPECIFICATION ================================== *)
\* Pure safety spec — liveness fairness is handled in EngramServer
TM_Spec == TM_Init /\ [][TM_Next]_tendermintVars

=============================================================================