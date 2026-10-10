// SPDX-License-Identifier: BSD-2-Clause
import fixturecli
import os

fn main() {
	fixturecli.run('generate', os.args[1..])
}
