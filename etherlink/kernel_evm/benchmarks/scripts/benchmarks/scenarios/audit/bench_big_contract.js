//SPDX-License-Identifier: MIT

const utils = require('../../utils');
const { contracts_directory, compile_contract_file } = require("../../../lib/contract");
let faucet = require('../../players/faucet.json');
let player1 = require('../../players/player1.json');

let txs = [];
let contracts = compile_contract_file(contracts_directory, "audit/GovernorOLAS-flatten.sol");

let create_data = contracts[10].bytecode;

// player1 get 10_000 from faucet
txs.push(utils.transfer(faucet, player1, 10000000))
let create = utils.create(player1, 0, create_data);
txs.push(create.tx);

let mode = utils.bench_args(process.argv);

utils.print_bench([txs], mode)
