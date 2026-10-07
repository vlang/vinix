// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

// The general host suite links this module once, without native C objects.
// Native generation omits this compiler-only include entirely.
$if linuxkpi_host_test ? {
	#include "linuxkpi_smp_masks_host_data.h"
}
