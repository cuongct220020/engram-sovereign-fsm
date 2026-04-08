# Engram Sovereign FSM (in-progress)

## Prerequisites
- IDE: VSCode
- Extensions: `TLA+ (Temporal Logic of Actions)`, `Graphviz Interactive Preview`, `Markdown All in One`, `Noir Language Support`.




```bash
git clone <repo-url>
cd engram-sovereign-fsm

python3 -m venv .venv
source .venv/bin/activate 
pip install requirements.txt
```






## The Big Merge

### Prototype Deployment Strategy (Avoid Full ZK-Rollup Implementation)
Writing a complete ZK circuit to prove state transitions for the entire Cosmos SDK (with thousands of transaction types) is the workload of a multi-million-dollar project, not a scientific paper.

#### Solution: Dummy Circuit Benchmarking
Use a "Dummy Circuit Benchmarking" method. Write a ZK circuit simulating the verification of a hash chain of 1,000 block headers. This represents the computational complexity of aggregation.

- **Theoretical Basis**: Based on Jens Groth's (2016) theory of ultra-small SNARK proofs (3 group elements) combined with Recursive SNARK composition to compress multiple proofs into a fully succinct SNARK.

### Core Metrics for Experiment 2

#### A. Proof Generation Time (Prover)
- **Theory**: Computational complexity for the Prover to generate ZK-Aggregation Proof is $O(N \cdot \log N)$, where $N$ is the number of transactions or blocks in the Sovereign phase.
- **Experiment**: In `scripts/the_big_merge/`, write code (using Go's `gnark` library or Rust's `snarkjs`) to create a proof for 1,000 Poseidon or SHA-256 hashes. Measure CPU/RAM usage in seconds/minutes to generate proof $\pi_{RA}$.

#### B. Parent Chain Acceptance Time (Verifier)
- **Theory**: Verifier complexity is $O(1)$ or $O(\log N)$, highly optimized for the DA layer. Proof size $\pi_{RA}$ (based on Groth16) is a tiny constant (~128 bytes).
- **Experiment (Simulated Time)**:
  - **On Celestia (DA Layer)**: The 128-byte proof occupies minimal space. Acceptance time equals Celestia's block creation time (~10-15 seconds).
  - **On Bitcoin (Payment Layer via Babylon)**: The compressed proof $\pi_{RA}$ can be attached to the payload of an `OP_RETURN` transaction. Acceptance time equals the thermodynamic finality of $k$ Bitcoin blocks (typically $k=6$, ~60 minutes).