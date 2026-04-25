------------------ MODULE MC_FSMLiveness ------------------
EXTENDS EngramFSM

\* Sensor override: Assign a random sensor within a finite range (e.g., 0..15) to create a loop.
LivenessUpdateSensors ==
    /\ h_btc_current' \in 0..15
    /\ h_btc_submitted' \in 0..h_btc_current'
    /\ h_btc_anchored' \in 0..h_btc_submitted'
    /\ h_da_local' \in 0..15
    /\ h_da_verified' \in 0..h_da_local'
    /\ is_das_failed' \in BOOLEAN
    /\ peer_count' \in 0..(MIN_PEERS * 2)
    /\ reanchoring_proof_valid' \in BOOLEAN
    /\ UNCHANGED <<state, safe_blocks>>

\* Create Next and Spec tailored for Liveness
LivenessNext == (FSM_Transition /\ UNCHANGED envVars) \/ LivenessUpdateSensors
LivenessSpec == FSM_Init /\ [][LivenessNext]_fsmVars /\ FSM_Fairness
=============================================================