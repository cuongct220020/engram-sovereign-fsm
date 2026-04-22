---------------- MODULE MC_ConsensusLiveness ----------------
EXTENDS EngramConsensus, TLC

CONSTANTS n1, n2, n3, tx1

MC_Nodes == {n1, n2, n3}
MC_Method == {tx1}
MC_Stake == [n \in MC_Nodes |-> 10]

\* LIDO LIVENESS-TO-SAFETY REDUCTION
PacemakerProgress == [][rem_time = 0 => round' > round]_vars

\* HARD TIMEOUT PATTERN: Ép buộc hệ thống chỉ được chuyển vòng khi hết giờ.
MC_Next == 
    IF rem_time = 0 
    THEN TimeoutStartNext \/ EarlyStartNext 
    ELSE Next

MC_Spec == Init /\ [][MC_Next]_vars

\* GIỚI HẠN KHÔNG GIAN TRẠNG THÁI (State Space Pruning)
\* Ngăn TLC chạy vô hạn bằng cách giới hạn số vòng
StateSpaceLimit == round <= 3
=================================================================