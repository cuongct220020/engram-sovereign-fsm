--------------------------- MODULE EngramTypes ---------------------------
(*
 * EngramTypes — Domain Definitions & Nil Sentinels
 *
 * This module centralises ALL set/type definitions, record schemas, and Nil
 * sentinel values that are shared across EngramTendermint and EngramServer.
 * Extracting them here keeps EngramTendermint focused purely on protocol logic
 * and prevents circular-import issues in larger refinement hierarchies.
 *
 * Depends on: EngramVars (for constants MAX_ROUND, MAX_TIMESTAMP, etc.)
 *             EngramTendermint constants (imported via EXTENDS in callers)
 *)
EXTENDS Integers, EngramVars


(* ======================== CONSTANTS (consumed from EngramTendermint) ===== *)
\* These constants are declared in EngramTendermint; EngramTypes re-uses them
\* by being EXTEND-ed *after* EngramTendermint in each caller module.
\* They are listed here as documentation only — do NOT redeclare them.
\*
\*   MAX_ROUND, MAX_TIMESTAMP, MIN_TIMESTAMP  (numeric bounds)
\*   MAX_BTC_HEIGHT, MAX_ENGRAM_HEIGHT        (chain height bounds)
\*   N, T, Corr, Faulty, Proposer            (consensus parameters)
\*   Delay, Precision, TimeoutDuration       (timing parameters)


(* ======================== ROUND DOMAIN =================================== *)
\* @type: Set(ROUND);
Rounds == 0..MAX_ROUND

\* @type: ROUND;
NilRound == -1   \* Sentinel: no round (outside Rounds)

\* @type: Set(ROUND);
RoundsOrNil == Rounds \union {NilRound}


(* ======================== TIMESTAMP DOMAIN ================================ *)
\* @type: Set(TIME);
Timestamps == 0..MAX_TIMESTAMP

\* @type: TIME;
NilTimestamp == -1   \* Sentinel: no timestamp

\* @type: Set(TIME);
TimestampsOrNil == Timestamps \union {NilTimestamp}


(* ======================== TRANSACTION VALUE DOMAIN ======================== *)
\* @type: Set(STRING);
Values == {"TX_NORMAL", "TX_WITHDRAWAL"}

\* @type: Set(STRING);
ValidValues == Values

\* @type: STRING;
NilValue == "NIL_TX"

\* @type: Set(STRING);
ValuesOrNil == Values \union {NilValue}


(* ======================== FSM STATE DOMAIN ================================ *)
\* @type: Set(STR);
FSMStates == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN", "RECOVERING"}

\* @type: STR;
NilFSMState == "NONE"

\* @type: Set(STR);
FSMStatesOrNil == FSMStates \union {NilFSMState}


(* ======================== BITCOIN RECEIPT DOMAIN ========================= *)
\* @type: Set(Int);
BTCHeights == 0..MAX_BTC_HEIGHT

\* @type: Int;
NilBTCHeight == -1

\* @type: Set(BTC_RECEIPT);
BTCReceipts == [
    checkpoint_block_height : BTCHeights,
    checkpoint_block_hash   : STRING
]

\* @type: BTC_RECEIPT;
NilBTCReceipt == [
    checkpoint_block_height |-> NilBTCHeight,
    checkpoint_block_hash   |-> "NilHash"
]

\* @type: Set(BTC_RECEIPT);
BTCReceiptsOrNil == BTCReceipts \union {NilBTCReceipt}


(* ======================== DA RECEIPT DOMAIN ============================== *)
\* @type: Set(Int);
DAHeights == 0..MAX_ENGRAM_HEIGHT

\* @type: Int;
NilDAHeight == -1

\* @type: Set(DA_RECEIPT);
DAReceipts == [
    published_block_height : DAHeights,
    attestation            : BOOLEAN
]

\* @type: DA_RECEIPT;
NilDAReceipt == [
    published_block_height |-> NilDAHeight,
    attestation            |-> FALSE
]

\* @type: Set(DA_RECEIPT);
DAReceiptsOrNil == DAReceipts \union {NilDAReceipt}


(* ======================== PROPOSAL & DECISION RECORDS ==================== *)
\* @type: Set(PROPOSAL);
Proposals == [
    value        : ValuesOrNil,
    timestamp    : TimestampsOrNil,
    round        : RoundsOrNil,
    fsm_state    : FSMStatesOrNil,
    da_receipt   : DAReceiptsOrNil,
    btc_receipt  : BTCReceiptsOrNil,
    zk_proof_ref : BOOLEAN
]

\* @type: PROPOSAL;
NilProposal == [
    value        |-> NilValue,
    timestamp    |-> NilTimestamp,
    round        |-> NilRound,
    fsm_state    |-> NilFSMState,
    da_receipt   |-> NilDAReceipt,
    btc_receipt  |-> NilBTCReceipt,
    zk_proof_ref |-> FALSE
]

\* @type: Set(DECISION);
Decisions == [
    prop  : Proposals,
    round : Rounds
]

\* @type: DECISION;
NilDecision == [
    prop  |-> NilProposal,
    round |-> NilRound
]

=========================================================================
