// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

import os
import time

fn test_core_spawn_retires_argv_environment_pid_and_master() {
 mut before := 0
 for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD) >= 0 { before++ } }
 binding := os.real_path(@FILE).all_before_last('/') + '/../_native.py'
 for _ in 0 .. 100 {
  pid, master := core_spawn(['/usr/bin/true'], os.environ(), '/', '/usr/bin/python3', binding, '', false) or { panic(err) }
  mut done := false
  deadline := vm_now() + 5
  for vm_now() < deadline {
   waited, status := vm_wait(pid, C.WNOHANG) or { panic(err) }
   if waited { assert vm_child_exit_code(status) == 0; done = true; break }
   time.sleep(10 * time.millisecond)
  }
  if !done { vm_stop_child(pid, master, false) or { panic(err) } }
  assert C.close(master) == 0
  assert done
 }
 mut after := 0
 for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD) >= 0 { after++ } }
 assert after == before
}
