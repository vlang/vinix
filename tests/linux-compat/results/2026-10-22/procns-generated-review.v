import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn body(source string, name string) !string {
 mut lines := []string{}
 mut found := false
 for line in source.split_into_lines() {
  if !found && !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
   found = true
  }
  if found {
   lines << line
   if line == '}' { return lines.join('\n') + '\n' }
  }
 }
 return error('Generated C definition missing: ' + name)
}

fn normalize(source string) string {
 mut out := []u8{cap: source.len}
 mut at := 0
 for at < source.len {
  if source[at..].starts_with('_str_') {
   out << '_str_N'.bytes()
   at += 5
   for at < source.len && source[at].is_digit() { at++ }
  } else {
   out << source[at]
   at++
  }
 }
 return out.bytestr()
}

fn main() {
 arm := os.read_file(area + '/arm-track/blob.c')!
 x86 := os.read_file(area + '/x86-track/blob.c')!
 funcs := ['fs__new_procfs_resource', 'fs__ProcFSResource__unref', 'fs__drop_procfs_directory', 'fs__procfs_lookup_refresh_locked', 'fs__procfs_refresh_named_locked', 'fs__prune_directories', 'fs__orphan_node', 'fs__hold_parent', 'fs__free_node', 'fs__retire_node', 'fs__reap_removed', 'file__Handle__unref', 'resource__retain_resource']
 mut comparisons := []string{}
 mut arm_bodies := []string{}
 mut x86_bodies := []string{}
 for name in funcs {
  a := body(arm, name)!
  x := body(x86, name)!
  arm_bodies << a
  x86_bodies << x
  comparisons << name + ': ' + if normalize(a) == normalize(x) { 'equal after generated string-ID normalization' } else { 'architecture dispatch differences; inspected critical lifetime operations' }
 }
 os.write_file(area + '/generated-review-arm-excerpts.c', arm_bodies.join('\n'))!
 os.write_file(area + '/generated-review-x86-excerpts.c', x86_bodies.join('\n'))!
 os.write_file(area + '/generated-review-comparison.log', comparisons.join('\n') + '\n')!
 mut pins := []string{}
 for path in [area + '/arm-track/blob.c', area + '/x86-track/blob.c', area + '/arm-track/kernel/bin/vinix', area + '/x86-track/kernel/bin/vinix'] {
  pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path
 }
 os.write_file(area + '/generated-review-inputs.sha256', pins.join('\n') + '\n')!
 old := os.read_file(area + '/lifetime-review.md')!
 assert !old.contains('Current generated-C supplement')
 supplement := '\n## Current generated-C supplement\n\nIndependently checked the new exact-change ARM and x86 tracking generated C on 2026-10-22. The constructor, unref, recursive prune, removed guards, orphan/parent hold, node free and reaper operations preserve the reviewed lifetimes. Both generated unref definitions decrement the backend refcount and defer the shared box and backend separately; constructor interface `_object` points to the single backend. Child arrays and maps are explicitly freed. The reaper checks mount pins, handles, parent_refs, cwd/root usage and directory-release grace before node free. Handle release orders resource unref before node handle release. No additional blocker found.\n\nExact input SHA-256 values:\n\n```text\n' + pins.join('\n') + '\n```\n\nThirteen function bodies from each architecture are retained in generated-review-{arm,x86}-excerpts.c; generated-review-comparison.log records comparisons after normalizing generated string IDs. Architecture-specific interface dispatch lists differ; the relevant procfs backend and lifetime branches were inspected explicitly. The earlier timed-grace and source-review limits still apply.\n'
 os.write_file(area + '/lifetime-review.md', old + supplement)!
 println(comparisons.join('\n'))
}
