--------------------------- MODULE P2PGossip ---------------------------
EXTENDS Integers, Sequences, FiniteSets, TLC

\* Declare the set of Nodes in the network
CONSTANTS Nodes

\* node_state: Local state of each Node
\* queues: Independent message queues for each Node (Multiple Reader Queues)
\* votes_received: Set of votes that a Node has actually received and read
\* has_voted: Ensures each Node only sends a warning signal once to avoid infinite loops
VARIABLES node_state, queues, votes_received, has_voted

vars == <<node_state, queues, votes_received, has_voted>>

\* Define Quorum BFT (Greater than 2/3)
Quorum == (2 * Cardinality(Nodes) \div 3) + 1

States == {"ANCHORED", "SUSPICIOUS", "SOVEREIGN"}

\* -----------------------------------------------------------------------------
\* TYPE INVARIANTS
\* -----------------------------------------------------------------------------
TypeOK == 
    /\ node_state \in [Nodes -> States]
    /\ queues \in [Nodes -> Seq([type: {"VOTE"}, sender: Nodes])]
    /\ votes_received \in [Nodes -> SUBSET Nodes]
    /\ has_voted \in [Nodes -> BOOLEAN]

\* -----------------------------------------------------------------------------
\* INIT STATE
\* -----------------------------------------------------------------------------
Init ==
    /\ node_state = [n \in Nodes |-> "ANCHORED"]
    /\ queues = [n \in Nodes |-> <<>>]           \* Initialize empty queues for all Nodes
    /\ votes_received = [n \in Nodes |-> {}]
    /\ has_voted = [n \in Nodes |-> FALSE]

\* -----------------------------------------------------------------------------
\* ACTION 1: GOSSIP & PACKET LOSS
\* -----------------------------------------------------------------------------
\* A Node detects a local gray failure, transitions to SUSPICIOUS, and broadcasts a Vote.
CastVote(n) ==
    /\ has_voted[n] = FALSE
    /\ node_state[n] = "ANCHORED"
    /\ node_state' = [node_state EXCEPT ![n] = "SUSPICIOUS"]
    /\ has_voted' = [has_voted EXCEPT ![n] = TRUE]
    
    \* SIMULATE AT-MOST-ONCE DELIVERY (PACKET LOSS):
    \* Instead of sending to all Nodes, the system randomly selects a set of 'receivers'.
    \* Any Node NOT in the 'receivers' set is considered to have experienced PACKET LOSS.
    /\ \E receivers \in SUBSET Nodes:
        LET msg == [type |-> "VOTE", sender |-> n] IN
        queues' = [r \in Nodes |-> 
                      IF r \in receivers THEN Append(queues[r], msg) \* Message received
                      ELSE queues[r]]                                \* Message lost
    /\ UNCHANGED <<votes_received>>

\* -----------------------------------------------------------------------------
\* ACTION 2: READ QUEUES (Multiple Reader Queues)
\* -----------------------------------------------------------------------------
\* Each Node automatically pops messages from its own queue for processing
ReceiveVote(n) ==
    /\ Len(queues[n]) > 0
    /\ LET msg == Head(queues[n]) IN
        \* Update the local vote set of this Node
        votes_received' = [votes_received EXCEPT ![n] = votes_received[n] \cup {msg.sender}]
    \* Remove the processed message from the queue
    /\ queues' = [queues EXCEPT ![n] = Tail(queues[n])]
    /\ UNCHANGED <<node_state, has_voted>>

\* -----------------------------------------------------------------------------
\* ACTION 3: ACTIVATE AUTONOMOUS MODE (Circuit Breaker)
\* -----------------------------------------------------------------------------
\* If a Node collects enough votes (>= Quorum), it transitions to SOVEREIGN.
TriggerSovereign(n) ==
    /\ node_state[n] = "SUSPICIOUS"
    /\ Cardinality(votes_received[n]) >= Quorum
    /\ node_state' = [node_state EXCEPT ![n] = "SOVEREIGN"]
    /\ UNCHANGED <<queues, votes_received, has_voted>>

\* -----------------------------------------------------------------------------
\* STATE TRANSITIONS AND CONDITIONS
\* -----------------------------------------------------------------------------
Next == 
    \/ (\E n \in Nodes: CastVote(n))
    \/ (\E n \in Nodes: ReceiveVote(n))
    \/ (\E n \in Nodes: TriggerSovereign(n))

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* -----------------------------------------------------------------------------
\* SAFETY PROPERTY (Macro Safety Invariant)
\* -----------------------------------------------------------------------------
\* Regardless of chaotic packet loss, a Node is ONLY ALLOWED to activate the circuit breaker
\* (transition to SOVEREIGN) if it TRULY holds enough votes (>= Quorum).
ValidCircuitBreaker == 
    \A n \in Nodes: 
        (node_state[n] = "SOVEREIGN") => (Cardinality(votes_received[n]) >= Quorum)

Symmetry == Permutations(Nodes)

=============================================================================