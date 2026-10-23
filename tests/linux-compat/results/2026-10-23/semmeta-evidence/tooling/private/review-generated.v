import crypto.sha256
import json2
import os
import strings

const area = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
const baseline = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/semperm-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }
fn body(text string, name string) string {
 for line in text.split_into_lines() {
  if line.contains(' sysvsem__' + name + '(') && line.ends_with(' {') {
   tail := text[index(text, line)..]
   return tail[..index(tail, '\n}\n') + 3]
  }
 }
 panic('Missing definition: ' + name)
}
fn normalize(text string) string {
 mut out := strings.new_builder(text.len)
 mut i := 0
 for i < text.len {
  if text[i].is_letter() || text[i] == `_` {
   start := i
   for i < text.len && (text[i].is_alnum() || text[i] == `_`) { i++ }
   token := text[start..i]
   mut end := token.len
   if token.starts_with('_') { for end > 0 && token[end - 1].is_digit() { end-- } }
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
  for name in ['semid_size', 'realtime_seconds', 'may_use', 'may_remove'] {
   helper := body(generated, name)
   for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'v_free('] {
    assert !helper.contains(token), 'New allocation in ' + name
   }
   excerpt += helper
  }
  for name in ['capable', 'identity', 'in_group', 'destroy_unlocked', 'find_id_unlocked',
   'find_key_unlocked', 'evaluate_unlocked', 'link_unlocked', 'unlink_unlocked',
   'complete_unlocked', 'progress_unlocked', 'release_waiter_unlocked', 'operate'] {
   current := body(generated, name)
   assert current == body(original, name), 'Changed lifetime/evaluation helper: ' + name
   excerpt += current
  }
  commit := body(generated, 'commit_unlocked')
  assert commit.replace('\tset->otime = sysvsem__realtime_seconds();\n', '') == body(original, 'commit_unlocked')
  excerpt += commit
  ctl := body(generated, 'syscall_semctl')
  old_ctl := body(original, 'syscall_semctl')
  assert ctl.contains('sysvsem__SemIdDs info = (sysvsem__SemIdDs){0};')
  assert !ctl.contains('(sysvsem__SemIdDs*)memdup')
  for token in ['memdup', '__new_array', 'array_push', 'v_free('] {
   assert ctl.count(token) == old_ctl.count(token), 'New semctl allocation/free: ' + token
  }
  assert index(ctl, 'usercopy__copy_from_user((void*)(&info)') < index(ctl, 'sysvsem__Identity who =')
  assert index(ctl, 'sysvsem__Identity who =') < index(ctl, 'klock__Lock__acquire(')
  stat_start := index(ctl, '\t\tinfo.perm.key = set->key;')
  stat_tail := ctl[stat_start..]
  release := index(stat_tail, 'klock__Lock__release(')
  copy_start := index(stat_tail, 'usercopy__copy_to_user(')
  assert release < copy_start
  assert !stat_tail[release..copy_start].contains('set->')
  assert !stat_tail[copy_start..index(stat_tail, '\t} else if (command == sysvsem__ipc_rmid)')].contains('set->')
  // Existing removal, GET/SETALL and SETVAL bodies differ only in ctime writes.
  current_tail := ctl[index(ctl, '\t\tset->removed = true;')..].replace('\t\tset->ctime = sysvsem__realtime_seconds();\n', '')
  assert normalize(current_tail) == normalize(old_ctl[index(old_ctl, '\t\tset->removed = true;')..])
  excerpt += ctl
  get := body(generated, 'syscall_semget')
  old_get := body(original, 'syscall_semget')
  for token in ['memdup', '__new_array', 'array_push', 'proc__reserve_kernel(', 'v_free('] {
   assert get.count(token) == old_get.count(token), 'New set allocation/free: ' + token
  }
  trimmed := get.replace('.cuid = who.uid, .cgid = who.gid, ', '').replace('.ctime = sysvsem__realtime_seconds(), ', '')
  assert trimmed == old_get, 'Changed set allocation lifetime'
  excerpt += get
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, excerpt)!
  records << {
   'architecture': suffix,
   'generated_c': path,
   'generated_c_sha256': digest(path)!,
   'excerpt': output,
   'excerpt_sha256': digest(output)!,
   'result': 'PASS: native metadata is a zeroed stack value; no new allocation/free; full IPC_SET import precedes identity/sets_lock; IPC_STAT snapshots scalar fields before unlocking and copies out without a borrowed set pointer; existing set destruction and waiter/evaluation helpers unchanged; added scalar creator credentials and clock writes only',
   'scope': 'No new lifetime. Native 64-bit ABI metadata only; namespace isolation, mapped credentials, foreign layouts, SEM_UNDO and inventory commands remain outside this change.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated semaphore metadata review: PASS (both architectures)')
}
