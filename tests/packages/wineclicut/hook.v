// SPDX-License-Identifier: GPL-2.0-or-later
// Copied beside the unchanged CLI entrypoint for the power-cut test build only.
module main

import os
import time

#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
fn C.syscall(i64, ...) i64

__global (
	cli_cut_configured bool
	cli_cut_point int
	cli_cut_calls int
)

@[export: 'vinix_wine_cli_cut_fsync']
fn cli_cut_fsync(fd i32) i32 {
	result := i32(C.syscall(i64(C.SYS_fsync), fd))
	if result != 0 { return result }
	if !cli_cut_configured {
		cli_cut_configured = true
		if os.geteuid() == 1000 && os.args.len == 4 && os.args[1] == 'wine-prefix-migrate'
			&& os.args[2] == 'app' && os.exists('/tmp/wine-cli-cut') {
			text := os.read_file('/tmp/wine-cli-cut') or { C.errno = C.EINVAL; return -1 }
			if text !in ['1', '2', '3'] { C.errno = C.EINVAL; return -1 }
			cli_cut_point = text.int()
		}
	}
	if cli_cut_point > 0 {
		if cli_cut_calls == 0 {
			stage := os.args[3] + '/wine/.vinix-builtin-next'
			pending := os.is_link(stage)
			unsafe { stage.free() }
			if !pending { return result }
		}
		cli_cut_calls++
		if cli_cut_calls == cli_cut_point {
			println('WINE POWER CUT READY point=${cli_cut_point}')
			for { time.sleep(time.second) }
		}
	}
	return result
}
