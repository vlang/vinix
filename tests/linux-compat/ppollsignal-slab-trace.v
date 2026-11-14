// SPDX-License-Identifier: GPL-2.0-or-later
// Kernel-only attribution across the exact production probe's two root slab
// reads. No userspace probe mutation, extra warmup or changed storage oracle.
module main

import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: ppollsignal-slab-trace PROCFS-SOURCE FRESH-OUTPUT') }
	if os.exists(os.args[2]) { return error('Fresh output required') }
	mut source := os.read_file(os.args[1])!
	anchor := '.slabinfo {\n\t\t\treturn slabinfo_text()'
	if source.count(anchor) != 1 { return error('Different slabinfo branch') }
	source = source.replace(anchor,'.slabinfo {\n\t\t\tslab_attribution_sample()\n\t\t\treturn slabinfo_text()')
	source += '
// Qualification-only: the test guest has one privileged slab sampler.
__global slab_attribution_step u32
__global slab_attribution_buffer [262144]char
fn slab_attribution_sample() {
 if !proc.may_read_kernel_diagnostics() { return }
 step := katomic.inc(mut &slab_attribution_step)
 if step == 0 {
  C.alloc_track_start()
  C.kprintf(c\'SLAB-ATTRIBUTION: start before first root slab read\\n\')
 } else if step == 1 {
  unsafe {
  data := &slab_attribution_buffer[0]
  n := C.alloc_track_dump(data,262143,1)
  if n == 0 || n >= 262143 || data[n-1] != char(10) { panic(\'Truncated slab attribution\') }
  data[n] = 0
  mut start := u64(0)
  for i := u64(0); i < n; i++ {
   if data[i] != char(10) { continue }
   data[i] = 0
   C.kprintf(c\'PERF-SITE ppollsignal phase=after %s\\n\',&data[start])
   start = i+1
  }
  }
 }
}
'
	os.write_file(os.args[2],source)!
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
