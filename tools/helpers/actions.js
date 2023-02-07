const fs = require("fs");
const path = require("path");
const process = require("child_process");
const { execSync } = require('child_process');
const util = require("util");
const exec = util.promisify(require("child_process").exec);
const { stringifyBigInts } = require("ffjavascript").utils;
const { performance } = require("perf_hooks");
const Scalar = require("ffjavascript").Scalar;
const buildZqField = require("ffiasm").buildZqField;

const ZqField = require("ffjavascript").ZqField;

const SMTMemDB = require("circomlibjs").SMTMemDb;
const RollupDb = require("@hermeznetwork/commonjs").RollupDB;

// Define name-files
const circuitName = "circuit";


async function compileCircuit(CircuitName) {
    const startTime = performance.now();
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    const cirName = path.join(pathName, `verifier.circom`);

    let flagsCircom;

    const cmd = `circom ${cirName} --r1cs --wasm --sym --output  ${pathName}`;
    console.log(cmd);
    execSync(cmd,{stdio:'inherit',stdin:'inherit'})

    const stopTime = performance.now();

    console.log(`Compile command took ${(stopTime - startTime)/1000} s`);
}


async function computeWitness(CircuitName){
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    // generate empty witness as an example
    const witnessName = path.join(pathName, `witness.wtns`);
    const inputName = path.join(pathName, `input.json`);
    const wasmName = path.join(pathName, `verifier_js/verifier.wasm`);
    

    const cmd = `node ${pathName}/verifier_js/generate_witness.js ${wasmName} ${inputName}  ${witnessName}`;
    console.log(cmd);
    console.log('Caculate witness....')

    console.log("Calculating witness example...");
    console.time("witness time");
    execSync(cmd,{stdio:'inherit',stdin:'inherit'})
    console.timeEnd("witness time");
    console.log("Witness example calculated");
}

async function computeZkey(CircuitName){
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    console.log(pathName);
    const r1csName = `${pathName}/verifier.r1cs`;
    const zkey0Name = `${pathName}/verifier_0.zkey`;
    const zkey1Name = `${pathName}/verifier_1.zkey`;
    const ptauName = path.join(__dirname, `../../final_21.ptau`);

    if (!fs.existsSync(r1csName)) {
        console.error(`Constraint file ${r1csName} doesnt exist`);
        return;
    }

    if (!fs.existsSync(ptauName)) {
        console.error(`Powers of Tau file ${ptauName} doesnt exist`);
        return;
    }

    console.log(`Powers of Tau file: ${ptauName}`);

    let zkeyCmd = `snarkjs groth16 setup ${r1csName} ${ptauName} ${zkey0Name} &&\
    snarkjs zkey contribute ${zkey0Name} ${zkey1Name} --name="1st Contributor Name" -v
    `;
    console.log(zkeyCmd);

    execSync(zkeyCmd,{stdio:'inherit',stdin:'inherit'});
}

async function generateVerifier(CircuitName){
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    const zkeyName = `${pathName}/verifier_1.zkey`;
    const vkeyName = `${pathName}/circuitVerifier.vkey`;
    const solName = `${pathName}/circuitVerifier.sol`;

    if (!fs.existsSync(zkeyName)) {
        console.log(`ZKey file ${zkeyName} doesnt exist`);
        return;
    }

    const vkeyCmd = `snarkjs zkey export verificationkey \
       ${zkeyName} \
       ${vkeyName}`;

    const solCmd = `snarkjs zkey export solidityverifier \
    ${zkeyName} \
    ${solName}`;

    execSync(vkeyCmd,{stdio:'inherit',stdin:'inherit'});
    execSync(solCmd,{stdio:'inherit',stdin:'inherit'});
}

async function generateProof(CircuitName){
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    const zkeyName = `${pathName}/verifier_1.zkey`;
    const proofName = `${pathName}/proof.json`;
    const publicName = `${pathName}/public.json`;
    const witnessName = `${pathName}/witness.wtns`;
    if (!fs.existsSync(zkeyName)) {
        console.log(`ZKey file ${zkeyName} doesnt exist`);
        return;
    }

    const cmd = `snarkjs groth16 prove\
    ${zkeyName} \
    ${witnessName} \
    ${proofName} \
    ${publicName}
    `;

    execSync(cmd,{stdio:'inherit',stdin:'inherit'});
}


async function verifyProof(CircuitName){
    const pathName = path.join(__dirname, `../../target/circom/${CircuitName}`);
    const vkeyName = `${pathName}/circuitVerifier.vkey`;
    const proofName = `${pathName}/proof.json`;
    const publicName = `${pathName}/public.json`;

    const cmd = `snarkjs groth16 verify\
    ${vkeyName} \
    ${publicName} \
    ${proofName} 
    `;

    execSync(cmd,{stdio:'inherit',stdin:'inherit'});
}

async function compileFr(pathC, platform){


    
    const p = Scalar.fromString("21888242871839275222246405745257275088548364400416034343698204186575808495617");

    const source = await buildZqField(p, "Fr");

    fs.writeFileSync(path.join(pathC, "fr.asm"), source.asm, "utf8");
    fs.writeFileSync(path.join(pathC, "fr.hpp"), source.hpp, "utf8");
    fs.writeFileSync(path.join(pathC, "fr.cpp"), source.cpp, "utf8");

    let pThread = "";

    if (platform === "darwin") {
        await exec("nasm -fmacho64 --prefix _ " +
            ` ${path.join(pathC,  "fr.asm")}`
        );
    }  else if (platform === "linux") {
        pThread = "-pthread";
        await exec("nasm -felf64 " +
            ` ${path.join(pathC,  "fr.asm")}`
        );
    } else throw("Unsupported platform");

    return pThread;
}

module.exports = {
    compileCircuit,
    computeWitness,
    computeZkey,
    generateVerifier,
    generateProof,
    verifyProof
};
