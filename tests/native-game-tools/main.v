// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import os

fn main() {
 guard := cachecli.own_commands()
 defer { guard.close() }
 if os.args.len < 2 { eprintln('Expected build, run or kekvm-control'); exit(2) }
 root := os.real_path(os.dir(@FILE) + '/../..')
 status := dispatch(root,os.args[1],os.args[2..]) or {
  eprintln(err)
  exit(if cachecli.cancelled() { cachecli.interrupt_status() } else if err.code() == 2 { 2 } else { 1 })
 }
 exit(status)
}

fn dispatch(root string, action string, argv []string) !int {
 return match action {
  'build' { gamehost.build_cli(root,argv)! }
  'run' { gamehost.run_cli(root,argv)! }
  'kekvm-control' { gamehost.agent_cli(argv)! }
  else { return error_with_code('Unknown game command',2) }
 }
}
