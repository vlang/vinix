import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const baseline = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/prioquery-evidence'
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
fn locked(text string, unlocks int) {
 assert index(text, 'proc__lock_table();') < index(text, 'proc__Process* caller')
 assert text.count('proc__unlock_table();') == unlocks
 for tail in text.split('proc__unlock_table();')[1..] {
  // The compiler emits an unreachable defer after the final scalar return.
  if !tail.contains('return ') { continue }
  before := tail[..index(tail, 'return ')]
  assert !before.contains('->') && !before.contains('proc__threads_by_tid')
 }
}
fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/states/kernel-third-' + suffix + '-prod/blob.c'
  generated := os.read_file(path)!
  original := os.read_file(baseline + '/' + suffix + '/build/blob.c')!
  mut excerpt := ''
  for name in ['proc__nice_value', 'proc__thread_nice', 'proc__aggregate_nice',
   'table__syscall_linux_getpriority', 'proc__process_at', 'proc__pid_in', 'proc__tid_in',
   'proc__pgid_in', 'proc__mac_peer_allowed', 'proc__current_pid_namespace'] {
   current := body(generated, name)
   assert current == body(original, name), 'Changed query/identity helper: ' + name
   excerpt += current
  }
  helper := body(generated, 'proc__set_aggregate_nice')
  setter := body(generated, 'proc__set_thread_nice')
  apply := body(generated, 'proc__apply_nice')
  syscall := body(generated, 'table__syscall_linux_setpriority')
  for changed in [helper, setter, apply, syscall] {
   for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'v_free(',
    '__eq_lhs', '__eq_rhs', 'proc__Process __', '__ptr_eq'] {
    assert !changed.contains(token), 'Allocation, free or structural comparison: ' + token
   }
  }
  assert helper.contains('(void*)(proc__process_at(owner->pid)) != (void*)(owner)')
  locked(helper, 3)
  locked(setter, 4)
  assert helper.count('proc__apply_nice(') == 1 && setter.count('proc__apply_nice(') == 1
  // Definition plus the two locked callers are the only generated references.
  assert generated.count('proc__apply_nice(') == 4
  assert apply.contains('return errno__eperm;') && apply.contains('return errno__eacces;')
  assert apply.contains('katomic__store_T_v_int(&t->sched_nice_override, wanted);')
  assert syscall.contains('proc__set_aggregate_nice(local_who, which == 1, wanted)')
  assert syscall.contains('(i32)(raw_which)') && syscall.contains('(i32)(raw_local_who)') && syscall.contains('(i32)(raw_prio)')
  excerpt += helper + setter + apply + syscall
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, excerpt)!
  records << {
   'architecture': suffix, 'generated_c': path, 'generated_c_sha256': digest(path)!,
   'excerpt': output, 'excerpt_sha256': digest(output)!,
   'result': 'PASS: no new allocation, free or object lifetime; explicit process address identity; table lock covers borrowed tasks, process owners and all apply_nice calls; all error and success paths unlock and return scalars; existing query and identity helper bodies are unchanged',
   'scope': 'Live native ELF64 tasks, initial PID namespace, unmapped UIDs, unrestricted MAC policy; concurrent credentials/teardown, zombies, GNU libc and foreign/ELF32 paths remain unqualified.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated priority change review: PASS (both architectures)')
}
