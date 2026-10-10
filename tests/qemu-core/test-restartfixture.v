// SPDX-License-Identifier: BSD-2-Clause
import fixturecli
import os

fn main() {
	fixturecli.run('restart', os.args[1..])
}
