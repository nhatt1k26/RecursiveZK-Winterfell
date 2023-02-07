const fs = require("fs");
const Scalar = require("ffjavascript").Scalar;
const SMTMemDB = require("circomlibjs").SMTMemDb;
const { stringifyBigInts } = require("ffjavascript").utils;

const RollupDB = require("@hermeznetwork/commonjs").RollupDB;
const Account = require("@hermeznetwork/commonjs").HermezAccount;
const Constants = require("@hermeznetwork/commonjs").Constants;
const utils = require("./helpers/gen-inputs-utils");
const { depositTx, assertBatch, assertAccountsBalances } = require("./helpers/helpers");
const ZqField = require("ffjavascript").ZqField;
const path = require("path");

// global vars
////////
const nTx      = 3;
const nLevels  = 16;
const maxL1Tx  = 2;
const maxFeeTx = 2;


const account1 = new Account(1);
const account2 = new Account(2);
const account3 = new Account(3);

const accounts = [];
// save idx that will be assigned during the test
account1.idx = Constants.firstIdx + 1;
account2.idx = Constants.firstIdx + 2;
account3.idx = Constants.firstIdx + 3;
accounts.push(account1);
accounts.push(account2);
accounts.push(account3);



async function newState(){
    const F = new ZqField(Scalar.fromString("21888242871839275222246405745257275088548364400416034343698204186575808495617"));
    const db = new SMTMemDB(F);
    const rollupDB = await RollupDB(db);
    return rollupDB;
}

async function generateInput(){
    const rollupDB = await newState();

    const bb = await rollupDB.buildBatch(circuitName);
    await depositTx(bb, account1, 1, 10);
    await depositTx(bb, account2, 2, 20);
    await bb.build();
    await rollupDB.consolidate(bb);

    // const bb2 = await rollupDB.buildBatch(circuitName);
    // await depositTx(bb2, account3, 1, 0);
    // await bb2.build();
    // await rollupDB.consolidate(bb2);
    // await assertBatch(bb2, circuit);

    const input = bb.getInput();

    const pathName = path.join(__dirname, `../inputs/rollup-${nTx}-${nLevels}-${maxL1Tx}-${maxFeeTx}`);
    if (!fs.existsSync(pathName))
        fs.mkdirSync(pathName);


    const inputFile = path.join(__dirname, `../inputs/rollup-${nTx}-${nLevels}-${maxL1Tx}-${maxFeeTx}/input-${nTx}-${nLevels}-${maxL1Tx}-${maxFeeTx}_2.json`);
    fs.writeFileSync(`${inputFile}`, JSON.stringify(stringifyBigInts(input), null, 1), "utf-8");
}

async function main(){
    console.log("Populating finished");
    console.log(accounts[0]);
    console.log("Generating inputs...");
    await generateInput();
    console.log("Finish input generation");
    //console.log(255||0)
}

main();
