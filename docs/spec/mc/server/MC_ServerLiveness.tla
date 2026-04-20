---------------- MODULE MC_ServerLiveness ----------------
EXTENDS EngramServer, TLC

CONSTANTS n1, n2, n3, n4, tx1, tx2

MC_Nodes == {n1, n2, n3, n4}
MC_Method == {tx1, tx2}
MC_Corr == MC_Nodes
MC_Faulty == {}
MC_Proposer == [r \in 0..5 |-> n1] 
MC_Stake == [n \in MC_Nodes |-> 10]

\* Giới hạn không gian trạng thái cực kỳ chặt chẽ cho Liveness
StateSpaceLimit == 
    /\ Max({round[n] : n \in MC_Corr}) <= 3
    /\ Cardinality(qcs) <= 5

\* Kích hoạt khối Fairness của FSM và Tendermint để hệ thống không bị đứng im
LivenessSpec == 
    /\ SpecServer 
    /\ Fairness \* Khối WF_vars của EngramFSM
    \* /\ ... (thêm Fairness của Tendermint nếu bạn có định nghĩa)

\* Thuộc tính cần kiểm tra: Tầng 3 phải thỏa mãn Liveness của Tầng 2 (ADO/LiDO)
RefinementLiveness == AbstractConsensus!Spec
=============================================================================