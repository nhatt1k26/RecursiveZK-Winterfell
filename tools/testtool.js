import { argv } from 'node:process';

const command = process.argv[2];

const nTx = Number(process.argv[3]);
const nLevels = Number(process.argv[4]);
const maxL1Tx = Number(process.argv[5]);

console.log(command,"-",nTx," ",maxL1Tx);