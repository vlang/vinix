import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const baseline = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/priochange-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }
fn body(text string, name string) string {
 for line in text.split_into_lines() {
  if !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
   tail := text[index(text, line)..]
   return tail[..index(tail, '\n}\n') + 3]
  }
 }
 panic('Missing definition: ' + name)
}
fn safe(text string) {
 for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'v_free(', '__eq_lhs', '__eq_rhs', 'proc__Process __', '__ptr_eq'] {
  assert !text.contains(token), 'Allocation, free or structural comparison: ' + token
 }
}
fn locked(text string) {
 assert index(text, 'proc__lock_table();') < index(text, 'proc__threads_by_tid')
 assert index(text, 'proc__lock_table();') < index(text, 'proc__process_at(')
 for tail in text.split('proc__unlock_table();')[1..] {
  if !tail.contains('return ') { continue }
  before := tail[..index(tail, 'return ')]
  assert !before.contains('->') && !before.contains('proc__threads_by_tid') && !before.contains('proc__process_at(')
 }
}
fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/states/kernel-first-' + suffix + '-prod/blob.c'
  generated := os.read_file(path)!
  original := os.read_file(baseline + '/' + suffix + '/build/blob.c')!
  mut excerpt := ''
  for name in ['proc__nice_value', 'table__syscall_linux_getpriority', 'table__syscall_linux_setpriority',
   'proc__process_at', 'proc__pid_in', 'proc__tid_in', 'proc__pgid_in', 'proc__mac_peer_allowed', 'proc__current_pid_namespace'] {
   current := body(generated, name)
   assert current == body(original, name), 'Changed syscall/identity helper: ' + name
   excerpt += current
  }
  for name in ['proc__thread_nice', 'proc__set_thread_nice', 'proc__aggregate_nice', 'proc__set_aggregate_nice'] {
   current := body(generated, name)
   safe(current)
   locked(current)
   assert current.contains('retired_leader_nice') && current.contains('leader_nice_retired')
   excerpt += current
  }
  for name in ['proc__retire_leader_nice_locked', 'proc__detach_exiting_thread', 'proc__nice_permission', 'proc__apply_nice'] {
   current := body(generated, name)
   safe(current)
   excerpt += current
  }
  retire := body(generated, 'proc__retire_leader_nice_locked')
  assert retire.contains('(void*)(proc__process_at(owner->pid)) != (void*)(owner)')
  assert retire.contains('owner->leader_nice_retired') && retire.contains('owner->retired_leader_nice = proc__nice_value(t);')
  detach := body(generated, 'proc__detach_exiting_thread')
  assert detach == 'void proc__detach_exiting_thread(proc__Thread* t, proc__Process* replacement) {\n\tproc__lock_table();\n\tproc__retire_leader_nice_locked(t);\n\tt->process = replacement;\n\tproc__unlock_table();\n}\n'
  release := body(generated, 'proc__release_thread_slot')
  assert release.replace('\t\tproc__retire_leader_nice_locked(t);\n', '') == body(original, 'proc__release_thread_slot')
  bind := body(generated, 'proc__bind_tid_locked')
  reset := '\tif ((thrd->process != NULL) && (tid == thrd->process->pid)) {\n\t\tproc__Process* owner = thrd->process;\n\t\towner->leader_nice_retired = false;\n\t}\n'
  assert bind.contains(reset)
  assert bind.replace(reset, '') == body(original, 'proc__bind_tid_locked')
  excerpt += release + bind
  for name in ['userland__exit_process', 'userland__thread_exit_status'] {
   current := body(generated, name)
   assert current.replace('proc__detach_exiting_thread(current_thread, sched__kernel_process);', 'current_thread->process = sched__kernel_process;') == body(original, name)
   excerpt += current
  }
  assert generated.count('proc__retire_leader_nice_locked(') == 4 // declaration, definition, detach, release
  permission := body(generated, 'proc__nice_permission')
  assert permission.contains('return errno__eperm;') && permission.contains('return errno__eacces;')
  assert permission.contains('proc__limit_allows(owner, proc__rlimit_nice')
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, excerpt)!
  records << {
   'architecture': suffix, 'generated_c': path, 'generated_c_sha256': digest(path)!,
   'excerpt': output, 'excerpt_sha256': digest(output)!,
   'result': 'PASS: no new allocation, free or object lifetime; all retained state is scalar in the existing published Process; table lock serializes lookup, updates, retirement and detachment; release/bind/exit bodies otherwise unchanged; syscall and identity helper bodies unchanged',
   'scope': 'Native ELF64, initial PID namespace, unmapped UIDs, unrestricted MAC. Concurrent credential mutations and /proc stat nice rendering are not qualified.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated zombie priority review: PASS (both architectures)')
}
