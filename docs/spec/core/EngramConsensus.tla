----------------------- MODULE EngramConsensus -----------------------
EXTENDS Naturals, FiniteSets

(********************* INTERFACE & CONSTANTS ************************)
CONSTANTS Nodes, ResetTime, Method, Stake, TotalStake

(********************* CONSENSUS LAYER VARIABLES (LAYER 2) ***********)
VARIABLES 
    tree,                 \* Buffer tree (AdoB)
    local_times,          \* Logical time of each node
    round,                \* Current consensus round
    rem_time,             \* Countdown timer
    fsm_state             \* ABSTRACTION: Only 1 environment variable is needed

vars == <<tree, local_times, round, rem_time, fsm_state>>

(********************* QUORUM OPTIMIZATION (MEMOIZATION) ****************)
RECURSIVE SumStakeOp(_)
SumStakeOp(Q) == IF Q = {} THEN 0 ELSE LET n == CHOOSE x \in Q : TRUE IN Stake[n] + SumStakeOp(Q \ {n})

SumStake[Q \in SUBSET Nodes] == SumStakeOp(Q)

\* Precompute the set of valid Quorums once
ValidQuorums == {q \in SUBSET Nodes : SumStake[q] * 3 > TotalStake * 2}

isSQuorum(Q) == Q \in ValidQuorums

(********************* INITIALIZATION ***********************************) 
Init == 
    /\ tree = {} 
    /\ local_times = [n \in Nodes |-> 0] 
    /\ round = 0        
    /\ rem_time = 0
    /\ fsm_state = "ANCHORED"

(********************* ABSTRACT PACEMAKER (LiDO) ******************)
Elapse == 
    /\ rem_time > 0
    /\ rem_time' = rem_time - 1
    /\ UNCHANGED <<tree, local_times, round, fsm_state>>

TimeoutStartNext == 
    /\ rem_time = 0
    /\ round' = round + 1
    /\ rem_time' = ResetTime
    /\ UNCHANGED <<tree, local_times, fsm_state>>

EarlyStartNext ==
    /\ \E c \in tree : c.type = "C" /\ c.round = round
    /\ round' = round + 1
    /\ rem_time' = ResetTime
    /\ UNCHANGED <<tree, local_times, fsm_state>>

(********************* ADOB CORE OPERATIONS ***********************)
Pull(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN
        /\ round > local_times[n]
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "E", round |-> round, caller |-> n, method |-> "None", voters |-> Q]}
        /\ UNCHANGED <<round, rem_time, fsm_state>>

Invoke(n, m) == 
    /\ m \in Method
    /\ \E c \in tree : c.type = "E" /\ c.caller = n /\ c.round = round
    /\ tree' = tree \cup {[type |-> "M", round |-> round, caller |-> n, method |-> m, voters |-> {n}]}
    /\ UNCHANGED <<local_times, round, rem_time, fsm_state>>

Push(n) == 
    LET Q == CHOOSE q \in SUBSET Nodes : isSQuorum(q) IN 
        /\ \E c \in tree : c.type = "M" /\ c.caller = n /\ c.round = round
        /\ local_times' = [s \in Nodes |-> IF s \in Q THEN round + 1 ELSE local_times[s]]
        /\ tree' = tree \cup {[type |-> "C", round |-> round, caller |-> n, method |-> "None", voters |-> Q]}
        /\ UNCHANGED <<round, rem_time, fsm_state>>

(********************* OPTIMIZED ENVIRONMENT ******************)
UpdateEnv == 
    /\ rem_time = 0  \* ONLY CHANGE STATE ON TIMEOUT (Suppress state explosion)
    /\ fsm_state' \in {"ANCHORED", "SOVEREIGN"}
    /\ UNCHANGED <<tree, local_times, round, rem_time>>

(********************* NEXT STATE  ****************)
Next == 
    \/ Elapse
    \/ TimeoutStartNext
    \/ EarlyStartNext
    \/ \E n \in Nodes : Pull(n)
    \/ \E n \in Nodes, m \in Method : Invoke(n, m)
    \/ \E n \in Nodes : Push(n)
    \/ UpdateEnv

(********************* FAIRNESS (LIVENESS) ************************)
Safety == Init /\ [][Next]_vars


Liveness == 
    /\ WF_vars(TimeoutStartNext)
    /\ WF_vars(EarlyStartNext)
    /\ \A n \in Nodes : WF_vars(Pull(n)) /\ WF_vars(Push(n))
    /\ \A n \in Nodes, m \in Method : WF_vars(Invoke(n, m))


Spec == Safety /\ Liveness
=====================================================================