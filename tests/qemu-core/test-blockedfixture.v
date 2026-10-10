// SPDX-License-Identifier: BSD-2-Clause
import fixturecli
import os

fn main() {
	fixturecli.run('blocked', os.args[1..])
}
