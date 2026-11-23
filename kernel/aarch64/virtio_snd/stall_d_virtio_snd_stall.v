// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module virtio_snd

// In test kernels only, hide 44.1 kHz PCM completions from the driver and
// withhold the STOP kick. The first reset also needs a retry.
__global (
	stall_test_stream = false
	stall_test_delay_reset = true
)
