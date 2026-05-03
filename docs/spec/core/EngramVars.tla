--------------------------- MODULE EngramVars ---------------------------
(*
 * EngramVars — Shared Variable Declarations
 *
 * This module declares ALL variables used across the Engram specification.
 * It is the single source of truth for variable groupings (tuples) that are
 * referenced in UNCHANGED clauses and WF_vars fairness conditions throughout
 * EngramFSM, EngramTendermint, and EngramServer.
 *
 * Dependencies: none (no EXTENDS, no CONSTANTS of its own beyond what is
 * declared below and used by callers).
 *)

CONSTANTS
    HYSTERESIS_WAIT,    \* Consecutive safe blocks required for successful recovery
    T_DA                \* Max allowed block gap since last DA publication verification


(* ======================== TENDERMINT CORE VARIABLES ======================== *)
\* Tendermint BFT state machine variables (per-process maps over Corr).
VARIABLES
    round,          \* Current consensus round of each correct process
    step,           \* Current step: "PROPOSE" | "PREVOTE" | "PRECOMMIT" | "DECIDED"
    decision,       \* Decided value (NilDecision if not yet decided)
    lockedValue,    \* Value locked by the process in the last lock round
    lockedRound,    \* Round in which lockedValue was locked
    validValue,     \* Most recent valid proposal seen
    validRound      \* Round in which validValue was observed

coreVars == <<round, step, decision, lockedValue, lockedRound, validValue, validRound>>


(* ======================== TEMPORAL / CLOCK VARIABLES ======================= *)
\* Physical and logical time tracking for clock-synchrony proofs.
VARIABLES
    local_clock,    \* Each correct process's local clock reading
    real_time,      \* Global "wall clock" (advanced by AdvanceRealTime)
    local_rem_time  \* Remaining timeout countdown per process

temporalVars == <<local_clock, real_time, local_rem_time>>


(* ======================== BOOKKEEPING VARIABLES ============================ *)
\* Message buffers and audit log.
VARIABLES
    msgsPropose,              \* Proposal messages indexed by round
    msgsPrevote,              \* Prevote messages indexed by round
    msgsPrecommit,            \* Precommit messages indexed by round
    msgsTimeout,              \* Timeout messages indexed by round
    evidence,                 \* Set of collected evidence (for accountability)
    action,                   \* String label of last executed action (for TLC tracing)
    receivedTimelyProposal,   \* Per-process set of timely proposal messages
    inspectedProposal         \* Per-(round,process) timestamp of last inspection

bookkeepingVars ==
    <<msgsPropose, msgsPrevote, msgsPrecommit, msgsTimeout,
      evidence, action, receivedTimelyProposal, inspectedProposal>>


(* ======================== INVARIANT SUPPORT VARIABLES ====================== *)
\* Ghost variables used exclusively to express timing invariants.
\* These are never read by the protocol logic itself.
VARIABLES
    beginRound,            \* Earliest local clock when any process entered round r
    endConsensus,          \* Local clock when process p decided
    lastBeginRound,        \* Latest local clock when any process entered round r
    proposalTime,          \* Real time at which the proposal for round r was broadcast
    proposalReceivedTime   \* Real time at which the first timely proposal was received

invariantVars ==
    <<beginRound, endConsensus, lastBeginRound,
      proposalTime, proposalReceivedTime>>


(* ======================== FSM & ENVIRONMENT VARIABLES ====================== *)
\* Circuit-breaker FSM state and all environment sensor readings.
VARIABLES
    state,                   \* FSM state: "ANCHORED"|"SUSPICIOUS"|"SOVEREIGN"|"RECOVERING"
    h_btc_current,           \* Latest observed Bitcoin block height
    h_btc_submitted,         \* Height at which the ZK re-anchoring proof was submitted
    h_btc_anchored,          \* Last confirmed Engram checkpoint height on Bitcoin
    h_engram_current,        \* Latest Engram chain block height
    h_engram_verified,       \* Last DA-verified Engram block height
    is_das_failed,           \* Boolean: DAS failure flag from Blobstream
    active_peers,            \* Set of currently connected peers
    anchor_peers,            \* Statically configured bootstrap/anchor peer set
    blacklisted_peers,       \* Peers identified as malicious and blacklisted
    safe_blocks,             \* Consecutive healthy blocks counted during RECOVERING
    reanchoring_proof_valid, \* Boolean: ZK re-anchoring proof confirmed on-chain
    forced_tx_queue,         \* Transactions pending forced inclusion (censorship resistance)
    tx_ignored_rounds        \* Per-(process,tx) counter of rounds where tx was ignored

\* Sub-tuples for granular UNCHANGED grouping
btcSensorVars  == <<h_btc_current, h_btc_submitted, h_btc_anchored>>
daSensorVars   == <<h_engram_current, h_engram_verified, is_das_failed>>
p2pSensorVars  == <<active_peers, anchor_peers, blacklisted_peers>>
censorVars     == <<forced_tx_queue, tx_ignored_rounds>>

\* Top-level FSM tuple consumed by EngramTendermint actions
fsmVars ==
    <<state, btcSensorVars, daSensorVars, p2pSensorVars,
      safe_blocks, reanchoring_proof_valid>>

\* Environment-only tuple consumed by EngramFSM (excludes consensus state)
envVars ==
    <<btcSensorVars, daSensorVars, p2pSensorVars,
      censorVars, reanchoring_proof_valid>>


(* ======================== SERVER / LIDO CERTIFICATE VARIABLES ============== *)
\* Abstract pacemaker certificates used by EngramServer and the LiDO refinement.
VARIABLES
    qcs,    \* Set of Quorum Certificates (E_QC, M_QC)
    tcs     \* Set of Timeout Certificates (T_QC)

\* Aggregate tuple for EngramTendermint (UNCHANGED / WF_vars references)
tendermintVars ==
    <<coreVars, temporalVars, bookkeepingVars,
      invariantVars, fsmVars, censorVars>>

\* Aggregate tuple for EngramServer (superset of tendermintVars + qcs/tcs)
serverVars ==
    <<coreVars, temporalVars, invariantVars, bookkeepingVars,
      qcs, tcs, fsmVars, censorVars>>

=========================================================================
