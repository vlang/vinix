// SPDX-License-Identifier: BSD-2-Clause
import fixturecli
import os

fn main() {
	fixturecli.run('epoll', os.args[1..])
}
