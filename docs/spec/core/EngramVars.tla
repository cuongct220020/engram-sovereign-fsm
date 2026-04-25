--------------------------- MODULE EngramVars ---------------------------

\* --- 1. TENDERMINT CORE VARIABLES ---
VARIABLES 
    round, step, decision, lockedValue, lockedRound, validValue, validRound

coreVars == <<round, step, decision, lockedValue, lockedRound, validValue, validRound>>

\* --- 2. TIME / TEMPORAL VARIABLES ---
VARIABLES 
    localClock, realTime

temporalVars == <<localClock, realTime>>

\* --- 3. BOOKKEEPING VARIABLES ---
VARIABLES 
    msgsPropose, msgsPrevote, msgsPrecommit, evidence, action, 
    receivedTimelyProposal, inspectedProposal

bookkeepingVars == <<msgsPropose, msgsPrevote, msgsPrecommit, evidence, action, receivedTimelyProposal, inspectedProposal>>

\* --- 4. INVARIANT SUPPORT VARIABLES ---
VARIABLES 
    beginRound, endConsensus, lastBeginRound, proposalTime, proposalReceivedTime

invariantVars == <<beginRound, endConsensus, lastBeginRound, proposalTime, proposalReceivedTime>>

\* --- 5. FSM & ENVIRONMENT VARIABLES ---
VARIABLES 
    state, h_btc_current, h_btc_submitted, h_btc_anchored, 
    h_da_local, h_da_verified, is_das_failed, peer_count, 
    safe_blocks, reanchoring_proof_valid

\* Định nghĩa cho EngramTendermint sử dụng
fsmVars == <<state, h_btc_current, h_btc_submitted, h_btc_anchored, h_da_local, h_da_verified, is_das_failed, peer_count, safe_blocks, reanchoring_proof_valid>>

\* Định nghĩa cho EngramFSM sử dụng
envVars == <<h_da_local, h_da_verified, h_btc_current, h_btc_submitted, h_btc_anchored, peer_count, reanchoring_proof_valid, is_das_failed>>

\* --- 6. SERVER & TENDERMINT TUPLES ---
VARIABLES 
    qcs, tcs

\* Tuple chuẩn dùng cho EngramTendermint (gọi ở các dòng UNCHANGED vars, WF_vars)
tendermintVars == <<coreVars, temporalVars, bookkeepingVars, action, invariantVars, fsmVars>>

\* Tuple dùng cho EngramServer
serverVars == <<coreVars, temporalVars, invariantVars, bookkeepingVars, action, qcs, tcs, fsmVars>>

=========================================================================