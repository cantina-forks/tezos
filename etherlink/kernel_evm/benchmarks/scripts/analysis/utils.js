// SPDX-FileCopyrightText: 2023 Marigold <contact@marigold.dev>
//
// SPDX-License-Identifier: MIT

const MLR = require("ml-regression-multivariate-linear")

const path = require('node:path')
const fs = require('fs');
const csv = require('csv-stringify/sync');
const pdfUtils = require('./pdf_utils');

module.exports = {
    is_scenario,
    is_run,
    is_blueprint_reading,
    is_transfer,
    is_call,
    is_create,
    is_transaction,
    make_lr,
    print_lr,
    print_summary_errors,
    print_model,
    predict_linear_model,
    print_csv
}

function is_transfer(record) {
    return record.tx_type === "TRANSFER"
}

function is_call(record) {
    return record.tx_type === "CALL"
}

function is_create(record) {
    return record.tx_type === "CREATE"
}

function is_transaction(record) {
    return !record.benchmark_name.includes("(all)")
        && !record.benchmark_name.includes("(bip)")
        && !record.benchmark_name.includes("(run)")
}

function is_scenario(record) {
    return record.benchmark_name.includes("(all)")
}

function is_run(record) {
    return record.benchmark_name.includes("(run)")
}

function is_blueprint_reading(record) {
    return record.benchmark_name.includes("(bip)")
}

function make_lr(data, select_x, select_y) {

    var X = []
    var Y = []
    for (datum of data) {
        let x = select_x(datum)
        let y = select_y(datum)
        if (!!x && !!y) {
            X.push([x])
            Y.push([y])
        }
    }
    if (X.length > 0) {
        let mlr = new MLR(X, Y)
        return mlr
    }
}

function print_lr(lr, var_name = "size") {
    if (!!lr) return `Y = ${lr.weights[1][0].toFixed()} + ${lr.weights[0][0].toFixed()} * ${var_name}`
    else return "no linear regression available"
}

function print_summary_errors(data, compute_error, prefix = "", doc = null) {
    if(data.length === 0){
        pdfUtils.output_msg(`[WARNING] no data for ${prefix}`, doc)
        return 0;
    }
    let max_error_current = 0;
    let nb_error = 0
    for (datum of data) {
        let error = compute_error(datum)
        if (error > 0) nb_error += 1
        if (!isNaN(error)) max_error_current = Math.max(max_error_current, error)
    }
    pdfUtils.output_msg(`${prefix} sample size: ${data.length}` , doc)
    pdfUtils.output_msg(`${prefix} nb of errors: ${nb_error} ; maximum error: ${max_error_current} ticks`, doc)
    return nb_error
}

function print_model(model, var_name) {
    return `Y = ${model.intercept} + ${model.coef} * ${var_name}`
}

function predict_linear_model(model, x) {
    if (isNaN(x)) return model.intercept
    return model.intercept + model.coef * x
}

function print_csv(dir, name, data_array, columns) {
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(path.format({ dir, name }), csv.stringify(data_array, {
        header: true,
        columns
    }))
}
