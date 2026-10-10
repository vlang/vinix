// SPDX-License-Identifier: GPL-2.0-or-later
module bootcapture

fn test_capture_recognizes_every_marker_split_across_reads_and_keeps_results() {
	for marker in ['PLAN DONE\n', 'PLAN DONE\r', 'PLAN FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
		for split in 0 .. marker.len + 1 {
			mut capture := Capture{}
			capture.observe('unrelated serial line\n')
			capture.observe(marker[..split])
			capture.observe(marker[split..])
			assert capture.done == marker.starts_with('PLAN DONE')
			assert capture.failed == !marker.starts_with('PLAN DONE')
			capture.observe('later serial output')
			assert capture.done == marker.starts_with('PLAN DONE')
			assert capture.failed == !marker.starts_with('PLAN DONE')
		}
	}
}

fn test_capture_keeps_bounded_storage_through_large_logs_and_short_read_boundaries() {
	chunk := 'x'.repeat(4096)
	mut capture := Capture{}
	for _ in 0 .. 10000 {
		capture.observe(chunk)
		assert capture.used == 256 && !capture.done && !capture.failed
	}
	for byte in 'PLAN DONE\n'.bytes() {
		capture.observe(byte.ascii_str())
	}
	assert capture.done && !capture.failed && capture.used == 256
	capture.observe('FATAL EXCEPTION')
	assert capture.done && capture.failed
}

fn test_capture_does_not_join_distant_or_overwritten_partial_markers() {
	mut capture := Capture{}
	capture.observe('PLAN DO')
	capture.observe('x'.repeat(4096))
	capture.observe('NE\n')
	assert !capture.done && !capture.failed
	capture.observe('PLAN DONE')
	assert !capture.done
	capture.observe('\r')
	assert capture.done
}
