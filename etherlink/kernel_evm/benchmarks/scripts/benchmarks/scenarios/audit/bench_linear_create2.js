// SPDX-License-Identifier: MIT

const utils = require('../../utils');
const { contracts_directory, compile_contract_file } = require("../../../lib/contract");
let faucet = require('../../players/faucet.json');
let player1 = require('../../players/player1.json');
let player2 = require('../../players/player2.json');

let txs = [];
txs.push(utils.transfer(faucet, player1, 10000000))

let contract_cre = compile_contract_file(contracts_directory, "audit/create2_ext.sol")[0];
let create_data_cre = contract_cre.bytecode;
let create_cre = utils.create(player1, 0, create_data_cre);
txs.push(create_cre.tx);

let contracts_large = compile_contract_file(contracts_directory, "audit/GovernorOLAS-flatten.sol");
let create_data_large = contracts_large[10].bytecode;
let create_large = utils.create(player1, 0, create_data_large);
txs.push(create_large.tx);

const run = function (runs, contractCode) {
    return contract_cre.interface.encodeFunctionData("run", [runs, contractCode])
}

let mode = utils.bench_args(process.argv, [{flag: '--count <n>', desc: 'Number of transfers', default: 0}]);
txs.push(utils.send(player1, create_cre.addr, 0, run(mode.extra.count, create_data_large)))

utils.print_bench([txs], mode)
