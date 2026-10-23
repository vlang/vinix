import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const baseline = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/semmeta-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }
fn body(text string, name string) string {
 for line in text.split_into_lines() {
  if line.contains(' ' + name + '(') && line.ends_with(' {') {
   tail := text[index(text, line)..]
   return tail[..index(tail, '\n}\n') + 3]
  }
 }
 panic('Missing definition: ' + name)
}
fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/states/kernel-second-' + suffix + '-prod/blob.c'
  generated := os.read_file(path)!
  original := os.read_file(baseline + '/' + suffix + '/build/blob.c')!
  mut excerpt := ''
  for name in ['proc__nice_value', 'proc__thread_nice', 'proc__set_thread_nice',
   'table__syscall_linux_setpriority', 'proc__process_at', 'proc__pid_in', 'proc__tid_in',
   'proc__pgid_in', 'proc__mac_peer_allowed', 'proc__current_pid_namespace'] {
   current := body(generated, name)
   assert current == body(original, name), 'Changed existing helper: ' + name
   excerpt += current
  }
  helper := body(generated, 'proc__aggregate_nice')
  query := body(generated, 'table__syscall_linux_getpriority')
  for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'v_free(',
   '__eq_lhs', '__eq_rhs', 'proc__Process __', '__ptr_eq'] {
   assert !helper.contains(token) && !query.contains(token), 'Allocation, free or structural comparison: ' + token
  }
  assert helper.contains('(void*)(proc__process_at(owner->pid)) != (void*)(owner)')
  assert index(helper, 'proc__lock_table();') < index(helper, 'proc__Process* caller')
  assert helper.count('proc__unlock_table();') == 4
  // V also emits an unreachable option fallback after the scalar success.
  assert helper.count('return ') == 4
  for tail in helper.split('proc__unlock_table();')[1..] {
   before := tail[..index(tail, 'return ')]
   assert !before.contains('->') && !before.contains('proc__threads_by_tid')
  }
  assert query.contains('i64 which = (i64)((i32)(raw_which));') || query.contains('int which = (int)((i32)(raw_which));')
  assert query.contains('proc__aggregate_nice(local_who, which == 1)')
  excerpt += helper + query
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, excerpt)!
  records << {
   'architecture': suffix,
   'generated_c': path,
   'generated_c_sha256': digest(path)!,
   'excerpt': output,
   'excerpt_sha256': digest(output)!,
   'result': 'PASS: no new allocation/free or object lifetime; process identity uses explicit address comparison; table lock covers all borrowed task/owner dereferences; both error returns and scalar success unlock, as does the unreachable option fallback; process and nice helpers and setpriority unchanged',
   'scope': 'Live native ELF64 task queries in the initial PID namespace with unmapped UIDs and unrestricted MAC domain; group/user mutation, zombies, namespaces, foreign layouts and GNU libc remain separate.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated priority query review: PASS (both architectures)')
}
