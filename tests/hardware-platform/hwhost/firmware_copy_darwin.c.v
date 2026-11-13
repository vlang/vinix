// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

#include <sys/clonefile.h>
#include <errno.h>
#define vinix_firmware_clonefile clonefile
fn C.vinix_firmware_clonefile(&char, &char, u32) i32

fn clone_firmware_variables(source string, target string) ! {
	if C.vinix_firmware_clonefile(source.str, target.str, 0) == 0 { return }
	code := C.errno
	if code == C.ENOTSUP || code == C.EXDEV { return os.cp(source, target) }
	return error('cannot clone firmware variables into fresh target')
}
