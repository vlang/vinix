// SPDX-License-Identifier: GPL-2.0-or-later
module file

import katomic

pub fn run_checks() {
 mut item := &G13PendingSubmission{command_count: 2}
 mut callback := &G13SubmitCompletion{submission: item}
 defer { unsafe { free(callback); free(item) } }
 for expected in [-2, -5, -12, -19, -22, -34, -110] {
  // Poison upper bits so a narrow store cannot pass through zero-init luck.
  unsafe { *(&u64(&item.commands[0].error)) = u64(0x12345678abcdef01) }
  finish_g13_submit(mut callback, false, expected)
  assert i64(item.commands[0].error) == i64(expected), 'native command errno storage'
  assert g13_pending_error(item) == expected, 'native command errno load'
  katomic.store(mut &item.commands[0].error, 0)
  item.commands[1].error = command_errno(expected)
  item.commands[1].done = false
  assert g13_pending_error(item) == 0, 'unfinished errors stay private'
  katomic.store(mut &item.commands[1].done, true)
  assert g13_pending_error(item) == expected, 'native neighboring command errno load'
  unsafe { *(&u64(&item.failure)) = u64(0x7abcdef012345678) }
  katomic.store(mut &item.failure, aggregate_errno(expected))
  finish_g13_submit(mut callback, true, 0)
  assert i64(item.commands[0].error) == i64(expected), 'native aggregate error override'
  assert g13_pending_error(item) == expected
  unsafe { *item = G13PendingSubmission{command_count: 2} }
 }
 println('AGX native errors: 7 negative errnos preserve full-width storage, callback loads, neighboring completion and aggregate overrides using production ARM atomics')
}
