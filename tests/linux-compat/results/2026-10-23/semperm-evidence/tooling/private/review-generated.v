import crypto.sha256
import json2
import os
import strings

const area = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'
const baseline = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/semrange-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }

fn body(text string, name string) string {
 for line in text.split_into_lines() {
  if line.contains(' sysvsem__' + name + '(') && line.ends_with(' {') {
   start := index(text, line)
   tail := text[start..]
   return tail[..index(tail, '\n}\n') + 3]
  }
 }
 panic('Missing definition: ' + name)
}

// Added branches change generated temporary sequence numbers only. Keep every
// instruction, source identifier and literal, normalizing compiler temporaries.
fn normalize(text string) string {
 mut out := strings.new_builder(text.len)
 mut i := 0
 for i < text.len {
  if text[i].is_letter() || text[i] == `_` {
   start := i
   for i < text.len && (text[i].is_alnum() || text[i] == `_`) { i++ }
   token := text[start..i]
   mut end := token.len
   if token.starts_with('_') {
    for end > 0 && token[end - 1].is_digit() { end-- }
   }
   out.write_string(token[..end])
  } else { out.write_u8(text[i]); i++ }
 }
 return out.str()
}

fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/states/kernel-first-' + suffix + '-prod/blob.c'
  generated := os.read_file(path)!
  original := os.read_file(baseline + '/' + suffix + '/build/blob.c')!
  mut excerpt := ''
  for name in ['capable', 'identity', 'in_group', 'may_use', 'may_remove'] {
   helper := body(generated, name)
   for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'v_free('] {
    assert !helper.contains(token), 'New allocation in ' + name
   }
   excerpt += helper
  }
  identity := body(generated, 'identity')
  assert identity.contains('sysvsem__Identity who = (sysvsem__Identity){')
  assert index(identity, 'proc__lock_table();') < index(identity, 'process->euid')
  assert index(identity, 'who.group_count++;') < index(identity, 'proc__unlock_table();')
  assert !generated.contains('(sysvsem__Identity*)memdup')
  for name in ['destroy_unlocked', 'find_id_unlocked', 'find_key_unlocked', 'evaluate_unlocked',
   'commit_unlocked', 'link_unlocked', 'unlink_unlocked', 'complete_unlocked', 'progress_unlocked', 'release_waiter_unlocked'] {
   current := body(generated, name)
   assert current == body(original, name), 'Changed lifetime/evaluation helper: ' + name
   excerpt += current
  }
  ctl := body(generated, 'syscall_semctl')
  old_ctl := body(original, 'syscall_semctl')
  assert normalize(ctl[index(ctl, '\t\tset->removed = true;')..]) == normalize(old_ctl[index(old_ctl, '\t\tset->removed = true;')..]), 'Changed command bodies'
  assert index(ctl, 'sysvsem__Identity who = sysvsem__identity();') < index(ctl, 'klock__Lock__acquire(')
  assert index(ctl, 'sysvsem__may_use(') < index(ctl, 'usercopy__copy_to_user(')
  assert !ctl.contains('__new_array')
  excerpt += ctl
  get := body(generated, 'syscall_semget')
  old_get := body(original, 'syscall_semget')
  fields := '.uid = who.uid, .gid = who.gid, .mode = (u32)(flags) & 0777, .user_ns = who.ipc_user_ns, '
  assert get.contains(fields)
  assert get[index(get, '\tArray values =')..].replace(fields, '') == old_get[index(old_get, '\tArray values =')..], 'Changed set allocation lifetime'
  for token in ['memdup', '__new_array', 'array_push', 'proc__reserve_kernel('] {
   assert get.count(token) == old_get.count(token), 'New set allocation: ' + token
  }
  excerpt += get
  operate := body(generated, 'operate')
  old_operate := body(original, 'operate')
  assert normalize(operate[index(operate, '\ti64 pid =')..]) == normalize(old_operate[index(old_operate, '\ti64 pid =')..]), 'Changed waiter lifetime or operation evaluation'
  assert operate[..index(operate, '\tsysvsem__Identity who =')].trim_space() == old_operate[..index(old_operate, '\tklock__Lock__acquire(')].trim_space(), 'Changed usercopy or timer setup'
  denied := operate[index(operate, '\tif (!sysvsem__may_use(')..index(operate, '\ti64 pid =')]
  assert denied.contains('klock__Lock__release(') && denied.contains('errno__eacces')
  assert denied.contains('time__Timer__disarm(timer);') && denied.contains('v_free(timer);')
  assert index(operate, 'sysvsem__Identity who = sysvsem__identity();') < index(operate, 'klock__Lock__acquire(')
  excerpt += operate
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, excerpt)!
  records << {
   'architecture': suffix,
   'generated_c': path,
   'generated_c_sha256': digest(path)!,
   'excerpt': output,
   'excerpt_sha256': digest(output)!,
   'result': 'PASS: scalar credential snapshot and fixed group array on stack; no new allocation; identity captured before sets_lock; unchanged allocation/destruction/evaluation/waiter helpers, command bodies and waiter tail; permission denial unlocks and frees existing timer',
   'scope': 'Set gains only inline credentials/mode/namespace ID with its existing lifetime. No borrowed namespace/group references survive the process-table lock. Compiler temporary numbers normalized only for unchanged command/waiter tails. IPC namespace isolation, ancestor namespace capability walks and filesystem IDs remain outside this change.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated semaphore permission review: PASS (both architectures)')
}
