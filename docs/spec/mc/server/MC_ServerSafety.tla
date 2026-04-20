---------------- MODULE MC_ServerSafety ----------------
EXTENDS EngramServer, TLC

CONSTANTS n1, n2, n3, n4, tx1, tx2

\* Khởi tạo các biến môi trường phức tạp để ánh xạ vào file .cfg
MC_Nodes == {n1, n2, n3, n4}
MC_Method == {tx1, tx2}
MC_Stake == [n \in MC_Nodes |-> 10]

MC_Corr == MC_Nodes
MC_Faulty == {}
MC_Proposer == [r \in 0..5 |-> n1] \* Giả định đơn giản n1 luôn làm Proposer

\* Bounding: Chỉ cho phép server chạy tối đa 3 vòng
\* (Trong Tendermint, 'round' là một mảng map từ Node -> Integer)
StateSpaceLimit == \A n \in MC_Nodes : round[n] <= 3

\* Symmetry Breaking để giảm không gian trạng thái n! lần
SymmetryPerms == Permutations(MC_Nodes)

\* Thuộc tính chứng minh Tầng 3 tuân thủ Tầng 2
RefinementProperty == AbstractConsensus!Safety
========================================================