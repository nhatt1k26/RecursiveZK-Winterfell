use std::{
    collections::HashMap,
    fs::{create_dir_all, File},
    io::Write,
};

use colored::Colorize;
use rug::{ops::Pow, Float};
use winterfell::{
    crypto::hashers::Poseidon,
    math::{fields::f256::BaseElement, log2, StarkField},
    Air, AirContext, HashFunction, Prover, TraceInfo,
};

use crate::{
    json::proof_to_json,
    utils::{
        canonicalize, check_file, command_execution, delete_directory, delete_file, Executable,
        LoggingLevel, WinterCircomError,
    },
    WinterCircomProofOptions, WinterPublicInputs,
};

/// Verify the Groth16 proof of the verification of the Winterfell proof.
///
/// This function should be used alongside the
/// [check_ood_frame](crate::check_ood_frame) function to really attest of the
/// validity of the original Winterfell proof.
///
/// ## Requirements
///
/// This function requires the `verification_key.json`, `proof.json` and
/// `public.json` files to be present in the directory
/// `target/circom/<circuit_name>`. These files can be generated by the
/// [circom_compile] and [circom_prove] functions.
///
/// [Verbose](LoggingLevel::Verbose) logging level is *highly* recommended.
pub fn circom_verify(
    circuit_name: &str,
    logging_level: LoggingLevel,
) -> Result<(), WinterCircomError> {
    check_file(
        format!("target/circom/{}/verification_key.json", circuit_name),
        Some("needed for verification"),
    )?;
    check_file(
        format!("target/circom/{}/public.json", circuit_name),
        Some("needed for verification"),
    )?;
    check_file(
        format!("target/circom/{}/proof.json", circuit_name),
        Some("needed for verification"),
    )?;

    command_execution(
        Executable::SnarkJS,
        &["g16v", "verification_key.json", "public.json", "proof.json"],
        Some(&format!("target/circom/{}", circuit_name)),
        &logging_level,
    )
}

/// Generate a Groth16 proof that the Winterfell proof is correct.
///
/// Only verifying the Groth16 proof attests of the validity of the Winterfell
/// proof. This makes this function the core of this crate.
///
/// This function only works if the Circom code has previously generated and
/// compiled and if the circuit-specific keys have been generated. This is
/// performed by the [circom_compile] function.
///
/// ## Steps
///
/// - Generate the Groth16 proof
/// - (Not in release mode) Verify the proof
/// - Parse the proof into a Circom-compatible JSON file
/// - Compute execution witness
/// - Generate proof
///
/// ## Soundness
///
/// The Groth16 proof generated is not self-sufficient. An additional check on
/// the out of domain trace frame and evaluations is required to ensure the
/// validity of the entire system.
///
/// This additional check, along with the Groth16 proof verification, is performed
/// by the [circom_verify] function.
///
/// See [crate documentation](crate) for more information.
pub fn circom_prove<P>(
    prover: P,
    trace: <P as Prover>::Trace,
    circuit_name: &str,
    logging_level: LoggingLevel,
) -> Result<(), WinterCircomError>
where
    P: Prover<BaseField = BaseElement>,
    <<P as Prover>::Air as Air>::PublicInputs: WinterPublicInputs,
{
    // CHECK FOR FILES
    // ===========================================================================

    // check_file(
    //     format!("target/circom/{}/verifier.r1cs", circuit_name),
    //     Some("did you run compile?"),
    // )?;
    // check_file(
    //     format!("target/circom/{}/verifier.zkey", circuit_name),
    //     Some("did you run compile?"),
    // )?;

    // BUILD PROOF
    // ===========================================================================

    if logging_level.print_big_steps() {
        println!("{}", "Building STARK proof...".green());
    }

    assert_eq!(prover.options().hash_fn(), HashFunction::Poseidon);

    let pub_inputs = prover.get_pub_inputs(&trace);
    let proof = prover
        .prove(trace)
        .map_err(|e| WinterCircomError::ProverError(e))?;

    // VERIFY PROOF
    // ===========================================================================

    #[cfg(debug_assertions)]
    {
        if logging_level.print_big_steps() {
            println!("{}", "Verifying STARK proof...".green());
        }

        winterfell::verify::<P::Air>(proof.clone(), pub_inputs.clone())
            .map_err(|err| WinterCircomError::InvalidProof(Some(err)))?;
    }

    // BUILD JSON OUTPUTS
    // ===========================================================================

    if logging_level.print_big_steps() {
        println!("{}", "Parsing proof to JSON...".green());
    }

    // retrieve air and proof options
    let air = P::Air::new(
        proof.get_trace_info(),
        pub_inputs.clone(),
        proof.options().clone(),
    );

    // convert proof to json object
    let mut fri_tree_depths = Vec::new();
    let json = proof_to_json::<P::Air, Poseidon<BaseElement>>(
        proof,
        &air,
        pub_inputs.clone(),
        &mut fri_tree_depths,
    );

    // print json to file
    let json_string = format!("{}", json);
    create_dir_all(format!("target/circom/{}", circuit_name)).map_err(|e| {
        WinterCircomError::IoError {
            io_error: e,
            comment: Some(String::from("creating Circom output directory")),
        }
    })?;
    let mut file =
        File::create(format!("target/circom/{}/input.json", circuit_name)).map_err(|e| {
            WinterCircomError::IoError {
                io_error: e,
                comment: Some(String::from("creating input.json")),
            }
        })?;
    file.write(&json_string.into_bytes())
        .map_err(|err| WinterCircomError::IoError {
            io_error: err,
            comment: Some(String::from("writing input.json")),
        })?;


    Ok(())
}

/// Generate and compile Circom code to verify a Winterfell proof with given
/// parameters.
///
/// The execution of this function, especially the generation of the circuit-specific keys, can last several minutes.
///
/// ## Powers of tau phase 1 transcript
///
/// This function requires a powers of tau phase 1 transcript that has been
/// prepared for phase 2 utilization. The file must be named `final.ptau` and
/// placed in the project root.
///
/// ## Transition constraints and assertions
///
/// This function requires that a file named `<circuit_name>.circom` be placed in
/// the `circuits/air/` directory. This file must contain two templates:
///
/// - `AIRTransitions` returning the degree of all transition constraints.
/// - `AIRAssertions` defining the assertions.
///
/// These definition are similar to the ones defined in the class implementing
/// the [Air] trait that is needed by the Winterfell prover and verifier.
///
/// There are examples already available in the `circuits/air/` directory.
///
/// ## Steps
///
/// - Generate Circom code to verify a Winterfell proof of given parameters.
/// - Compile the generated code.
/// - Generate circuit-specific keys from the powers of tau phase 1 transcript.
/// - Export a verification key
///
/// Generated files are placed in the `target/circom/<circuit_name>/` directory.
pub fn circom_create<P, const N: usize>(
    proof_options: WinterCircomProofOptions<N>,
    circuit_name: &str,
    logging_level: LoggingLevel,
) -> Result<(), WinterCircomError>
where
    P: Prover<BaseField = BaseElement>,
    <<P as Prover>::Air as Air>::PublicInputs: WinterPublicInputs,
{
    // CHECK FOR REQUIRED FILES

    check_file(
        String::from("final.ptau"),
        Some("required for the generation of circuit-specific keys"),
    )?;
    check_file(
        format!("circuits/air/{}.circom", circuit_name),
        Some("required for the compilation of Circom code"),
    )?;

    // CREATE OUTPUT DIRECTORY

    create_dir_all(format!("target/circom/{}", circuit_name)).map_err(|e| {
        WinterCircomError::IoError {
            io_error: e,
            comment: Some(String::from("creating Circom output directory")),
        }
    })?;

    // GENERATE CIRCOM CODE
    // ===========================================================================

    if logging_level.print_big_steps() {
        println!("{}", "Generating Circom code...".green());
    }

    generate_circom_main::<P::BaseField, P::Air, N>(proof_options, circuit_name)?;
    Ok(())
}

/// Generate a circom main file that defines the parameters for verifying a proof.
///
/// The main file is generated in the `target/circom/<circuit_name>/` directory,
/// with the `verifier.circom` name.
pub fn generate_circom_main<E, AIR, const N: usize>(
    proof_options: WinterCircomProofOptions<N>,
    circuit_name: &str,
) -> Result<(), WinterCircomError>
where
    E: StarkField,
    AIR: Air,
    AIR::PublicInputs: WinterPublicInputs,
{
    // FRI TREE DEPTHS
    let mut fri_tree_depths = vec![];
    let mut lde_domain_size = proof_options.trace_length * proof_options.lde_blowup_factor();
    while lde_domain_size > proof_options.fri_max_remainder_size {
        lde_domain_size /= proof_options.lde_blowup_factor();
        fri_tree_depths.push(log2(lde_domain_size));
    }

    let num_fri_layers = fri_tree_depths.len();

    let fri_tree_depths = if fri_tree_depths.len() == 0 {
        String::from("[0]")
    } else {
        format!(
            "[{}]",
            fri_tree_depths
                .iter()
                .map(|x| format!("{}", x))
                .collect::<Vec<_>>()
                .join(", ")
        )
    };

    // AIR CONTEXT

    let air_context = AirContext::<E>::new(
        TraceInfo::new(proof_options.trace_width, proof_options.trace_length),
        proof_options.transition_constraint_degrees().to_vec(),
        proof_options.num_assertions(),
        proof_options.get_proof_options(),
    );

    // CREATE FILE

    let mut file = File::create(format!("target/circom/{}/verifier.circom", circuit_name))
        .map_err(|e| WinterCircomError::IoError {
            io_error: e,
            comment: Some(String::from("trying to create circom main file")),
        })?;

    // WRITE TO FILE

    let arguments = format!(
        "{}, // addicity\n    \
            {}, // ce_blowup_factor\n    \
            {}, // domain_offset\n    \
            {}, // folding_factor\n    \
            {}, // fri_tree_depth\n    \
            {}, // grinding_factor\n    \
            {}, // lde_blowup_factor\n    \
            {}, // num_assertions\n    \
            {}, // num_draws\n    \
            {}, // num_fri_layers\n    \
            {}, // num_pub_coin_seed\n    \
            {}, // num_public_inputs\n    \
            {}, // num_queries\n    \
            {}, // num_transition_constraints\n    \
            {}, // trace_length\n    \
            {}, // trace_width\n    \
            {} // tree_depth",
        E::TWO_ADICITY,
        air_context.ce_domain_size() / proof_options.trace_length,
        E::GENERATOR,
        proof_options.fri_folding_factor(),
        fri_tree_depths,
        proof_options.grinding_factor(),
        proof_options.lde_blowup_factor(),
        proof_options.num_assertions,
        number_of_draws(
            proof_options.num_queries() as u128,
            (proof_options.trace_length * proof_options.fri_folding_factor()) as u128,
            128
        ),
        num_fri_layers,
        // 2 is the size of the serialized context in f256 field elements
        AIR::PublicInputs::NUM_PUB_INPUTS + 2,
        AIR::PublicInputs::NUM_PUB_INPUTS,
        proof_options.num_queries,
        air_context.num_transition_constraints(),
        proof_options.trace_length,
        proof_options.trace_width,
        log2(proof_options.trace_length * proof_options.fri_folding_factor()),
    );

    let file_contents = format!(
        "pragma circom 2.0.0;\n\
        \n\
        include \"../../../circuits/verify.circom\";\n\
        include \"../../../circuits/air/{}.circom\";\n\
        \n\
        component main {{public [ood_frame_constraint_evaluation, ood_trace_frame]}} = Verify(\n    \
            {}\n\
        );\n\
",
        circuit_name, arguments
    );

    file.write(file_contents.as_bytes())
        .map_err(|e| WinterCircomError::IoError {
            io_error: e,
            comment: Some(String::from("trying to write to circom main file")),
        })?;

    Ok(())
}

// HELPER FUNCTIONS
// ===========================================================================

fn number_of_draws(num_queries: u128, lde_domain_size: u128, security: i32) -> u128 {
    let mut num_draws: u128 = 0;
    let precision: u32 = security as u32 + 2;

    while {
        let st = step(
            0,
            num_draws,
            &mut HashMap::new(),
            num_queries,
            lde_domain_size,
            security,
        );
        num_draws += 1;
        1 - st > Float::with_val(precision, 2_f64).pow(-security)
    } {}

    num_draws
}

fn step(
    x: u128,
    n: u128,
    memo: &mut HashMap<(u128, u128), Float>,
    num_queries: u128,
    lde_domain_size: u128,
    security: i32,
) -> Float {
    let precision: u32 = security as u32 + 2;
    match memo.get(&(x, n)) {
        Some(val) => val.clone(),
        None => {
            let num: Float;
            if x == num_queries {
                num = Float::with_val(precision, 1f64);
            } else if n == 0 {
                num = Float::with_val(precision, 0f64);
            } else {
                let a = step(x + 1, n - 1, memo, num_queries, lde_domain_size, security);
                let b = step(x, n - 1, memo, num_queries, lde_domain_size, security);
                num = Float::with_val(precision, lde_domain_size - x)
                    / (Float::with_val(precision, lde_domain_size))
                    * a
                    + Float::with_val(precision, x) / (Float::with_val(precision, lde_domain_size))
                        * b;
            }
            memo.insert((x, n), num.clone());
            num
        }
    }
}