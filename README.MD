# STARK - SNARK recursive proofs

The point of this library is to combine the SNARK and STARK computation arguments of knowledge, namely the [Winterfell](https://github.com/novifinancial/winterfell) library for the generation of STARKs and the [Circom](https://docs.circom.io/) language, combined with the Groth16 protocol for SNARKs.

They allow the combinaison of advantages of both proof systems:

- Groth16 (SNARK): constant-time proofs, constant-time verification, etc.
- Winterfell: flexibility of the AIR construct

## 🗝️ Powers of tau phase 1 transcript

Before anything, a powers of tau phase 1 transcript must be placed in the root of the workspace, named `final.ptau`.

You can download the ones from the Hermez ceremony [here](https://www.dropbox.com/sh/mn47gnepqu88mzl/AACaJkBU7mmCq8uU8ml0-0fma?dl=0). Hopefully this link will not die.

## ⚙️ Example Executables

A few example crates are provided as proof-of-concept and usage examples, located in the `examples` folder.

- `sum` : Computation of the sum of integers from 0 to n.

Each crate contains three executables:

- `compile`: generates and compile Circom code, and generates the circuit-specific keys.  
  This must be run once before the the other two executables, and every time the proof options are changed.
- `prove`: generate a STARK - SNARK recursive proof.
- `verify`: verify the previously generated proof.

Therefore, the complete execution of the example `sum` is as follows:

```bash
cargo build --release -p example-sum
cargo run --release -p example-sum --bin create
cargo run --release -p example-sum --bin prove
```
To create Compile Circuit File, Create groth16 Proof and Verify, process as follows:
`````
cd tools
node build-circuit.js 0 sum compileCircuit
node build-circuit.js 0 sum computeWitness
node build-circuit.js 0 sum computeZkey
node build-circuit.js 0 sum generateVerifier
node build-circuit.js 0 sum generateProof
node build-circuit.js 0 sum verifyProof
`````
or compile, prove and verify in only command:

``````
cd tools
node build-circuit.js 1 sum