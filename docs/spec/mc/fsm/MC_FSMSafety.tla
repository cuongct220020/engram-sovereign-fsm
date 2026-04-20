------------------- MODULE MC_FSMSafety -------------------
EXTENDS EngramFSM

\* Limit the state space to avoid TLC explosions.
StateSpaceLimit == h_btc_current < 15 /\ h_da_local < 15
=============================================================