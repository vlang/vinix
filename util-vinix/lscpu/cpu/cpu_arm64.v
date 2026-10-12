// SPDX-License-Identifier: GPL-2.0-or-later
module cpu

import armcpu
import os

pub fn get_cpu_info() ?armcpu.Info {
	text := os.read_file('/proc/cpuinfo') or { return none }
	return armcpu.parse(text) or { return none }
}
