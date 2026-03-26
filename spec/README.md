# Formal Specification of Engram FSM (Draft)

This directory contains the formal mathematical specification of the **Adaptive Consensus FSM (Finite State Machine)** for the Engram Protocol network. The model is written in **TLA+** to verify the correctness of the system design under network partition scenarios.


Việc thực thi của một hệ thống máy tính có thể được biểu diễn bằng một chuỗi các trạng thái (states) rời rạc
- Trạng thái (State): Là một phép gán giá trị cho tất cả các biến trong hệ thống 
- Hành vi (Behavior): Là một chuỗi (sequence) vô hạn các trạng thái.
  - Chuỗi hợp lệ là một chuỗi mô tả đúng hành vi mà hệ thống vận hành. 

$$Spec_{Engram} \triangleq \text{Init} \land \Box[\text{Next}]_{vars}$$


- Tập không gian trạng thái
$$S \triangleq S_i:i \in \{ANCHORED, SUSPICIOUS, SOVEREIGN, RECOVERING\}$$

- Trạng thái ban đầu (trạng thái khởi tạo)
$$Init \triangleq S_{ANCHORED} \land (\Delta H = 0)$$


- Tập các hàm chuyển đổi trạng thái
$$\text{Next} \triangleq \text{AnchoredToSuspicious} \lor \text{SuspciousToSovereign} \lor \text{SovereignToRecovering} \lor \text{RecoveringToAnchored} \lor \text{AnchoredToSovereign}$$

## 1. System Model Overview

The FSM governs the consensus mechanism of Engram based on three core states:
- **ANCHORED**: The network operates normally, securely anchored to Bitcoin via Babylon.
- **SUSPICIOUS**: The validation gap ($\Delta H$) exceeds the threshold $T_1$ (100 blocks). The protocol begins restricting high-risk transactions.
- **SOVEREIGN**: The validation gap exceeds the threshold $T_2$ (500 blocks). The network becomes isolated (Network Partition) and automatically activates the Local PoS mechanism to maintain Liveness, while also triggering the Circuit Breaker.

## 2. Verified Properties

This model uses the TLC Model Checker to prove two core mathematical theorems of the paper:

1. **Safety (`TypeOK`)**: Proves $Safety_{Anchored} \cap Safety_{Sovereign} \neq \emptyset$. The FSM never exists in two states simultaneously, completely eliminating the risk of Double-spending between modes.
2. **Liveness (`Liveness`)**: Proves `WF_vars(SovereignToAnchored)`. Regardless of how long the network is partitioned, the system always has a valid mathematical path to recover (Re-anchoring) to the `ANCHORED` state when external connectivity is restored.

## 3. How to Run Verification

To verify this model, you need to install the TLA+ Toolbox or use the TLC CLI.

### Using Command Line (CLI):
Run the following command in the project root directory:
```bash
# Compile and run the TLC Model Checker with the EngramFSM.cfg configuration file
java -jar tlacli.jar -config EngramFSM.cfg EngramFSM.tla
```
