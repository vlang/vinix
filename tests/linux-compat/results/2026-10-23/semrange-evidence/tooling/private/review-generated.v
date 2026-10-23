import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const prior = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn index(text string, needle string) int { return text.index(needle) or { panic('Missing: ' + needle) } }

fn body(text string) !string {
 signature := 'multi_return_u64_u64 sysvsem__syscall_semctl(void* _0, i32 id, i32 number, i32 command, u64 argument)'
 start := text.index(signature + ' {') or { return error('Missing function') }
 tail := text[start..]
 end := tail.index('\n}\n') or { return error('Missing function end') }
 return tail[..end + 3]
}

fn main() {
 mut records := []map[string]string{}
 for suffix in ['arm', 'x86'] {
  path := area + '/states/kernel-first-' + suffix + '-prod/blob.c'
  control := body(os.read_file(path)!)!
  original := body(os.read_file(prior + '/states/kernel-first-' + suffix + '-prod/blob.c')!)!
  negative := index(control, 'if (id < 0)')
  range := index(control, 'errno__erange')
  acquire := index(control, 'klock__Lock__acquire(')
  lookup := index(control, 'sysvsem__find_id_unlocked(')
  number := index(control, 'number < 0')
  assert negative < range && range < acquire && acquire < lookup && lookup < number
  assert control[..acquire].contains('(i32)(argument) < 0') && control[..acquire].contains('(i32)(argument) > sysvsem__semvmx')
  assert control.count('errno__erange') == original.count('errno__erange')
  assert control.count('klock__Lock__release(') == original.count('klock__Lock__release(') - 1
  original_range := '\t\tif ((value < 0) || (value > sysvsem__semvmx)) {\n\t\t\tklock__Lock__release(&sysvsem__sets_lock);\n\t\t\treturn (multi_return_u64_u64){errno__err, errno__erange};\n\t\t}\n'
  assert original.contains(original_range)
  // After relocating scalar validation, every instruction from lock onward
  // matches the baseline except its now-unnecessary range-error unlock.
  assert control[acquire..] == original[index(original, 'klock__Lock__acquire(')..].replace(original_range, '')
  for token in ['memdup', 'malloc', '__new_array', 'array_push', 'string__', 'free(', 'usercopy__', 'klock__Lock__acquire(', 'sysvsem__progress_unlocked('] {
   assert control.count(token) == original.count(token), 'Allocation/lifetime/locking change: ' + token
  }
  output := area + '/generated-review-' + suffix + '.c.txt'
  os.write_file(output, control)!
  records << {
   'architecture': suffix,
   'generated_c': path,
   'generated_c_sha256': digest(path)!,
   'excerpt': output,
   'excerpt_sha256': digest(output)!,
   'result': 'PASS: negative signed ID before SETVAL signed-int range before first lock/ID lookup/index validation; one range check relocated; no new allocation, usercopy, ownership or object lifetime; existing successful update and queue progress preserved',
   'scope': 'Only scalar validation moves before sets_lock. Existing ownership, destruction, user copies, SETALL relookup and pending-wait paths are unchanged.'
  }
 }
 os.write_file(area + '/generated-review.json', json2.encode(records, prettify: true) + '\n')!
 println('Generated SETVAL validation review: PASS (both architectures)')
}
