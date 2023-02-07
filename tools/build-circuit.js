const { createCircuit, compileCircuit, inputs,
    computeWitness, computeZkey,
    generateVerifier,generateProof,
    verifyProof} = require("./helpers/actions");

// Input parameters
const ProcessAll = process.argv[2];

const circuitName = process.argv[3];

const command = process.argv[4];

if (ProcessAll==0)
{
    if (command == "compileCircuit") {
        compileCircuit(circuitName);
    } else if (command == "computeWitness"){
        computeWitness(circuitName);
    } else if (command == "computeZkey"){
        computeZkey(circuitName);
    } 
    else if (command == "generateVerifier"){
        generateVerifier(circuitName);
    }
    else if (command == "generateProof"){
        generateProof(circuitName);
    }
    else if (command == "verifyProof"){
        verifyProof(circuitName);
    }
    else {
        console.error(`command "${command}" not accepted`);
    }
}
else 
{
    compileCircuit(circuitName);
    computeWitness(circuitName);
    computeZkey(circuitName);
    generateVerifier(circuitName);
    generateProof(circuitName);
    verifyProof(circuitName);
}
