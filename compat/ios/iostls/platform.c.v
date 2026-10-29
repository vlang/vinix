// SPDX-License-Identifier: GPL-2.0-or-later
module iostls

#include <mbedtls/platform.h>

__global C.mbedtls_platform_dev_random &char

fn init() {
	$if linux {
		// Configure the documented library-wide entropy source before any TLS
		// worker starts. TLS 1.3's PSA generator also seeds through this path,
		// independently of the per-connection CTR-DRBG callback. Vinix supplies
		// its secure CSPRNG as /dev/urandom; /dev/random is not a device here.
		unsafe { C.mbedtls_platform_dev_random = c'/dev/urandom' }
	}
}
