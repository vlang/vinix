import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }

fn body(text string, signature string) !string {
 start := text.index(signature + ' {') or { return error('Missing function: ' + signature) }
 tail := text[start..]
 end := tail.index('\n}\n') or { return error('Missing function end') }
 return tail[..end + 3]
}

fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/kernel-' + suffix + '/kernel/obj/blob.c'
  text := os.read_file(path)!
  control := body(text, 'multi_return_u64_u64 sysvsem__syscall_semctl(void* _0, i32 id, i32 number, i32 command, u64 argument)')!
  assert control.count('u16 values[32];') == 2
  for forbidden in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'free('] {
   assert !control.contains(forbidden), 'New allocation or lifetime in control: ' + forbidden
  }
  get := control.all_after('} else if (command == sysvsem__getall) {').all_before('} else if (command == sysvsem__setall) {')
  assert get.count('set->') == 2
  assert index(get, 'klock__Lock__release(') < index(get, 'usercopy__copy_to_user(')
  assert !get.all_after('klock__Lock__release(').contains('set->')
  assert get.contains('(u64)(count) * sizeof(u16)')
  set := control.all_after('} else if (command == sysvsem__setall) {').all_before('} else if (command == sysvsem__getpid) {')
  assert set.count('klock__Lock__acquire(') == 1
  release := index(set, 'klock__Lock__release(')
  import_at := index(set, 'usercopy__copy_from_user(')
  range := index(set, 'errno__erange')
  acquire := index(set, 'klock__Lock__acquire(')
  lookup := index(set, 'set = sysvsem__find_id_unlocked(')
  removed := index(set, 'errno__eidrm')
  store := index(set, 'Array* __v3_internal_symbol_scalar_store_base_')
  wake := index(set, 'sysvsem__progress_unlocked(set);')
  assert release < import_at && import_at < range && range < acquire && acquire < lookup && lookup < removed && removed < store && store < wake
  assert !set[release..lookup].contains('set->')
  assert set.contains('(u64)(count) * sizeof(u16)')
  assert set.contains('set->last_pid[v_fixed_index(v_index, 32)] = pid;')
  getset := body(text, 'multi_return_u64_u64 sysvsem__syscall_semget(void* _0, i32 key, i32 nsems, i32 flags)')!
  assert getset.contains('i64 id = sysvsem__next_id;\n\tsysvsem__next_id++;')
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, control + '\n' + getset)!
  records << {
   'architecture': suffix,
   'generated_c': path,
   'generated_c_sha256': digest(path)!,
   'excerpt': output,
   'excerpt_sha256': digest(output)!,
   'result': 'PASS: two 64-byte stack arrays; exact ushort copy lengths; no allocation or new lifetime; user copies outside IPC lock; GETALL snapshots before unlock; SETALL relooks up monotonic ID before dereference; validates whole input before committing all values and PIDs then progressing waiters',
   'scope': 'No pointer is dereferenced across an unlocked user copy. No set/pending ownership, destruction or allocation path changes. SETALL removal during copy returns EIDRM. IDs are monotonic and are not reused by this implementation.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated semaphore array review: PASS (both architectures)')
}
