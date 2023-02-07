use winter_circom_prover::{circom_create, utils::{LoggingLevel, WinterCircomError}};

#[allow(dead_code)]
mod prover;
use prover::WorkProver;

mod air;
use air::PROOF_OPTIONS;

fn main() -> Result<(), WinterCircomError> {
    println!("Make here");
    circom_create::<WorkProver, 2>(PROOF_OPTIONS, "sum", LoggingLevel::Default)
}
