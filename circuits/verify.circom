pragma circom 2.0.0;

include "fri.circom";
include "merkle.circom";
include "ood_consistency_check.circom";
include "public_coin.circom";
include "utils/arrays.circom";
include "utils/powers.circom";


/**
 * A circom verifier for STARKs.
 *
 * ARGUMENTS:
 * - ce_blowup_factor: constraint evaluation domain blowup factor
 * - domain_offset: domain generator (7 for BLS12-381)
 * - folding_factor: FRI folding factor
 * - lde_blowup_factor: Low Degree Extention blowup factor
 * - num_assertions: number of assertions that will be turned into boundary constraints.
 * - num_draws: number of draws needed in order to have less than a 2**-128 probability
     to not get enough distinct elements for your queries
 * - num_fri_layers: number of fri folds
 * - num_pub_coin_seed: length of the serialized public inputs and context needed
     to initialize the public coin
 * - num_public_inputs: number of public inputs. Public inputs usually contain the
     inputs and the result of the calculation
 * - num_queries: number of decommitments for trace states and and constraint evaluations
     to be used in DEEP polynomial composition
 * - num_transition_constraints: number of transitions constraints defined in the AIR.
 * - trace_length: number of steps in the proven calculation
 * - trace_width: number of registers need to prove the calculations
 * - tree_depth: trace and commitments tree depth log2(lde_domain_size)
 *
 * INPUTS:
 * - constraint_commitment: root of the constraint merkle tree.
 * - constraint_evaluations: constraint polynomials evaluations
 * - constraint_query_proofs: merkle authentication paths to check consistency between
     the commitment and the queries at pseudo-random position
 * - fri_commitments: the root of the evaluations merkle tree for each FRI layer
 * - fri_layer_proofs: authentication paths of the aforementionned merkle tree at the
     query_positions for each FRI layer
 * - fri_layer_queries: folded DEEP polynomial evaluations at the folded query positions
     for each FRI layer
 * - fri_remainder: complete evaluation of the FRI remainder over the LDE domain
 * - ood_constraint_evaluations: constraint out of domain evaluations to be
     checked during the OOD consistency check
 * - ood_trace_frame: out of domain frame to evaluate constraints to check
     consitency with the ood_constraint_evaluations
 * - pub_coin_seed: serialized public inputs and context to initialize the public coin.
 * - pow_nonce: nonce for the proof of work determined by the grinding factor in
     the proof options
 * - trace_commitment: root of the trace merkle tree
 * - trace_evaluations: trace polynomial evaluations at the query positions
 * - trace_query_proofs: authentication paths of the aforementionned merkle tree at
     the query positions
 */
template Verify(
    addicity,
    ce_blowup_factor,
    domain_offset,
    folding_factor,
    fri_tree_depths,
    grinding_factor,
    lde_blowup_factor,
    num_assertions,
    num_draws,
    num_fri_layers,
    num_pub_coin_seed,
    num_public_inputs,
    num_queries,
    num_transition_constraints,
    trace_length,
    trace_width,
    tree_depth
) {
    var remainder_size = (trace_length * lde_blowup_factor) \ (folding_factor ** num_fri_layers);

    signal input addicity_root;
    signal input constraint_commitment;
    signal input constraint_evaluations[num_queries][ce_blowup_factor];
    signal input constraint_query_proofs[num_queries][tree_depth];
    signal input fri_commitments[num_fri_layers + 1];
    signal input fri_layer_proofs[num_fri_layers][num_queries][tree_depth];
    signal input fri_layer_queries[num_fri_layers][num_queries * folding_factor];
    signal input fri_remainder[remainder_size];
    signal input ood_constraint_evaluations[ce_blowup_factor];
    signal input ood_frame_constraint_evaluation[num_transition_constraints];
    signal input ood_trace_frame[2][trace_width];
    signal input pub_coin_seed[num_pub_coin_seed];
    signal input public_inputs[num_public_inputs];
    signal input pow_nonce;
    signal input trace_commitment;
    signal input trace_evaluations[num_queries][trace_width];
    signal input trace_query_proofs[num_queries][tree_depth];

    signal constraint_div[num_queries][ce_blowup_factor];
    signal constraint_evalxcoeff[num_queries][ce_blowup_factor];
    signal deep_composition[num_queries];
    signal deep_deg_adjustment[num_queries];
    signal deep_evaluations[num_queries];
    signal deep_temp[num_queries][trace_width];
    signal g_lde;
    signal g_trace;
    signal trace_deep_composition[num_queries][trace_width][2];
    signal trace_div[num_queries][trace_width][2];
    signal x_coordinates[num_queries];
    signal x_pow[trace_length * lde_blowup_factor];

    component addicity_pow[3];
    component constraintCommitmentVerifier;
    component fri;
    component ood;
    component pub_coin;
    component multi_sel;
    component traceCommitmentVerifier;
    component x_pow_domain_offset;
    component z_m;


    // CALCULATE TRACE DOMAIN AND LDE DOMAIN GENERATORS
    addicity_pow[0] = Pow(2 ** addicity);
    addicity_pow[0].in <== addicity_root;
    addicity_pow[0].out === 1;

    var log2_trace_length = numbits(trace_length) - 1;
    assert(log2_trace_length <= addicity);
    addicity_pow[1] = Pow(2 ** (addicity - log2_trace_length));
    addicity_pow[1].in <== addicity_root;
    g_trace <== addicity_pow[1].out;

    var log2_lde_domain_size = numbits(trace_length * lde_blowup_factor) - 1;
    assert(log2_lde_domain_size <= addicity);
    addicity_pow[2] = Pow(2 ** (addicity - log2_lde_domain_size));
    addicity_pow[2].in <== addicity_root;
    g_lde <== addicity_pow[2].out;


    // PUBLIC COIN INITIALIZATION
    pub_coin = PublicCoin(
        ce_blowup_factor,
        grinding_factor,
        lde_blowup_factor,
        num_assertions,
        num_draws,
        num_fri_layers,
        num_pub_coin_seed,
        num_queries,
        num_transition_constraints,
        trace_length,
        trace_width
    );

    pub_coin.constraint_commitment <== constraint_commitment;

    for (var i = 0; i < num_fri_layers + 1; i++) {
        pub_coin.fri_commitments[i] <== fri_commitments[i];
    }

    for (var i = 0; i < ce_blowup_factor; i++) {
        pub_coin.ood_constraint_evaluations[i] <== ood_constraint_evaluations[i];
    }

    for (var i = 0; i < trace_width; i++) {
        pub_coin.ood_trace_frame[0][i] <== ood_trace_frame[0][i];
        pub_coin.ood_trace_frame[1][i] <== ood_trace_frame[1][i];
    }

    pub_coin.pow_nonce <== pow_nonce;

    for (var i = 0; i < num_pub_coin_seed; i++) {
        pub_coin.pub_coin_seed[i] <== pub_coin_seed[i];
    }

    pub_coin.trace_commitment <== trace_commitment;


    // TRACE COMMITMENT
    // ===========================================================================

    // Build random coefficients for the composition polynomial constraint coeffiscients
    ood = OodConsistencyCheck(
        addicity,
        ce_blowup_factor,
        num_assertions,
        num_public_inputs,
        num_transition_constraints,
        trace_length,
        trace_width
    );

    ood.addicity_root <== addicity_root;
    ood.g_trace <== g_trace;

    for (var i = 0; i < num_transition_constraints; i++) {
        for (var j = 0; j < 2; j++) {
            ood.transition_coeffs[i][j] <== pub_coin.transition_coeffs[i][j];
        }
    }

    for (var i = 0; i < num_assertions; i++) {
        for (var j = 0; j < 2; j++) {
            ood.boundary_coeffs[i][j] <== pub_coin.boundary_coeffs[i][j];
        }
    }


    // OOD CONSISTENCY CHECK
    // ===========================================================================
    // Check that the given out of domain evaluations are consistent when
    // re-evaluating them.


    for (var i = 0; i < num_public_inputs; i++) {
        ood.public_inputs[i] <== public_inputs[i];
    }
    ood.z <== pub_coin.z;
    for (var i = 0; i < trace_width; i++) {
        ood.frame[0][i] <== ood_trace_frame[0][i];
        ood.frame[1][i] <== ood_trace_frame[1][i];
    }
    for (var i = 0; i < num_transition_constraints; i++) {
        ood.ood_frame_constraint_evaluation[i] <== ood_frame_constraint_evaluation[i];
    }
    for (var i = 0; i < ce_blowup_factor; i++) {
        ood.channel_ood_evaluations[i] <== ood_constraint_evaluations[i];
    }


    // VERIFY TRACE AND CONSTRAINT COMMITMENTS
    // ===========================================================================

    traceCommitmentVerifier = MerkleOpeningsVerify(num_queries, tree_depth, trace_width);
    traceCommitmentVerifier.root <== trace_commitment;
    for (var i = 0; i < num_queries; i++) {
        traceCommitmentVerifier.indexes[i] <== pub_coin.query_positions[i];
        for (var j = 0; j < trace_width; j++) {
            traceCommitmentVerifier.leaves[i][j] <== trace_evaluations[i][j];
        }
        for (var j = 0; j < tree_depth; j++) {
            traceCommitmentVerifier.openings[i][j] <== trace_query_proofs[i][j];
        }
    }

    constraintCommitmentVerifier = MerkleOpeningsVerify(num_queries, tree_depth, ce_blowup_factor);
    constraintCommitmentVerifier.root <== constraint_commitment;
    for (var i = 0; i < num_queries; i++) {
        constraintCommitmentVerifier.indexes[i] <== pub_coin.query_positions[i];
        for (var j = 0; j < ce_blowup_factor; j++) {
            constraintCommitmentVerifier.leaves[i][j] <== constraint_evaluations[i][j];
        }
        for (var j = 0; j < tree_depth; j++) {
            constraintCommitmentVerifier.openings[i][j] <== constraint_query_proofs[i][j];
        }
    }


    // COMPUTE DEEP POLYNOMIAL EVALUATIONS at the query positions
    // ===========================================================================

    z_m = Pow(ce_blowup_factor);
    z_m.in <== pub_coin.z;

    multi_sel = MultiSelector(trace_length * lde_blowup_factor, num_queries);

    x_pow[0] <== 1;
    multi_sel.in[0] <== 1;

    for (var i = 1; i < trace_length * lde_blowup_factor; i++){
        x_pow[i] <== x_pow[i-1] * g_lde;
        multi_sel.in[i] <== x_pow[i] * domain_offset;
    }

    for(var i = 0; i < num_queries; i ++) {
        multi_sel.indexes[i] <== pub_coin.query_positions[i];
    }

    for (var i = 0; i < num_queries; i++) {
        // DEEP trace composition
        for (var j = 0; j < trace_width; j++) {
            trace_div[i][j][0] <-- (trace_evaluations[i][j] - ood_trace_frame[0][j]) / (multi_sel.out[i] - pub_coin.z);
            trace_div[i][j][0] * (multi_sel.out[i] - pub_coin.z) === trace_evaluations[i][j] - ood_trace_frame[0][j];

            deep_temp[i][j] <== multi_sel.out[i] - pub_coin.z * g_trace;
            trace_div[i][j][1] <-- (trace_evaluations[i][j] - ood_trace_frame[1][j]) / deep_temp[i][j];
            trace_div[i][j][1] * deep_temp[i][j] === trace_evaluations[i][j] - ood_trace_frame[1][j];

            trace_deep_composition[i][j][0] <== pub_coin.deep_trace_coefficients[j][0] * trace_div[i][j][0];

            if (j == 0) {
                trace_deep_composition[i][j][1] <== trace_deep_composition[i][j][0] + pub_coin.deep_trace_coefficients[j][1] * trace_div[i][j][1];
            } else {
                trace_deep_composition[i][j][1] <== trace_deep_composition[i][j-1][1] + trace_deep_composition[i][j][0]+ pub_coin.deep_trace_coefficients[j][1] * trace_div[i][j][1];
            }
        }

        // DEEP constraint composition
        for (var j = 0; j < ce_blowup_factor; j++) {
            if (j == 0) {
                constraint_div[i][j] <-- (constraint_evaluations[i][j] - ood_constraint_evaluations[j]) / (multi_sel.out[i] - z_m.out);
                constraint_div[i][j]  * (multi_sel.out[i] - z_m.out) ===  constraint_evaluations[i][j] - ood_constraint_evaluations[j];
                constraint_evalxcoeff[i][j] <== constraint_div[i][j] * pub_coin.deep_constraint_coefficients[j];
            } else {
                constraint_div[i][j] <-- (constraint_evaluations[i][j] - ood_constraint_evaluations[j]) / (multi_sel.out[i] - z_m.out);
                (constraint_div[i][j])  * (multi_sel.out[i] - z_m.out) ===  constraint_evaluations[i][j] - ood_constraint_evaluations[j];
                constraint_evalxcoeff[i][j] <== constraint_evalxcoeff[i][j-1] + constraint_div[i][j] * pub_coin.deep_constraint_coefficients[j];
            }
        }

        // final composition
        deep_composition[i] <== trace_deep_composition[i][trace_width - 1][1] + constraint_evalxcoeff[i][ce_blowup_factor - 1];

        deep_deg_adjustment[i] <== pub_coin.degree_adjustment_coefficients[0] + multi_sel.out[i] * pub_coin.degree_adjustment_coefficients[1];
        deep_evaluations[i] <== deep_composition[i] * deep_deg_adjustment[i];
    }


    // VERIFY FRI LOW-DEGREE PROOF
    // ===========================================================================

    fri = FriVerifier(
        addicity,
        domain_offset,
        folding_factor,
        fri_tree_depths,
        lde_blowup_factor,
        num_fri_layers,
        num_queries,
        trace_length,
        tree_depth
    );

    fri.addicity_root <== addicity_root;
    fri.g_lde <== g_lde;

    for (var i = 0; i < num_queries; i++) {
        fri.deep_evaluations[i] <== deep_evaluations[i];
        fri.query_positions[i] <== pub_coin.query_positions[i];
    }
    for (var i = 0; i < remainder_size; i++) {
        fri.fri_remainder[i] <== fri_remainder[i];
    }
    for (var i = 0; i < num_fri_layers; i++) {
        fri.fri_commitments[i] <== fri_commitments[i];
        fri.layer_alphas[i] <== pub_coin.layer_alphas[i];

        for (var j = 0; j < num_queries; j++) {
            for (var k = 0; k < folding_factor; k++) {
                fri.fri_layer_queries[i][j * folding_factor + k] <== fri_layer_queries[i][j * folding_factor + k];
            }
            for (var k = 0; k < tree_depth; k++) {
                fri.fri_layer_proofs[i][j][k] <== fri_layer_proofs[i][j][k];
            }
        }
    }
    fri.fri_commitments[num_fri_layers] <== fri_commitments[num_fri_layers];
}
