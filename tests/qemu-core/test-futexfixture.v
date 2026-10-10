// SPDX-License-Identifier: BSD-2-Clause
import fixturecli
import os

fn main() { fixturecli.run('futex', os.args[1..]) }
