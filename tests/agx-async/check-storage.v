// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string, name string) !string {
 mut cursor := 0
 mut found := ''
 for cursor < source.len {
  start := source.index_after(' ' + name + '(', cursor) or { break }
  end := source.index_after('\n', start) or { return error('signature') }
  cursor = end + 1
  if !source[start..end].ends_with('{') { continue }
  finish := source.index_after('\n}\n', end) or { return error('body') }
  if found != '' { return error('duplicate ' + name) }
  found = source[start..finish + 3]; cursor = finish + 3
 }
 if found == '' { return error('missing ' + name) }
 return found
}

fn check(source string, prefix string) ! {
 for helper in ['G13SubmissionTimestamps__addresses', 'GpuFile__new_g13_submission_timestamps',
  'GpuFile__release_g13_submission_timestamps', 'GpuFile__submit_g13_staged', 'release_completed_g13_timestamps', 'discard_g13_completion'] {
  mut text := body(source, prefix + helper)!
  owned := if helper == 'GpuFile__new_g13_submission_timestamps' {
   'memory__malloc_packed_fallible((u64)(commands.len) * sizeof(' + prefix + 'G13TimestampReferences))'
  } else if helper == 'GpuFile__submit_g13_staged' {
   'memory__malloc_packed_fallible(sizeof(' + prefix + 'G13PendingSubmission))'
  } else { '' }
  if owned != '' {
   if text.count(owned) != 1 { return error('expected one bounded fallible owner allocation: ' + helper) }
   text = text.replace(owned, 'explicit_owner_storage')
  }
  for token in ['memdup', 'HEAP(', 'malloc', 'calloc', 'realloc', '__new_array', 'array_new(',
   'new_array_from', 'array_clone', 'array_slice', 'G13TimestampReferences entries[64]'] {
   if text.contains(token) { return error(helper + ': temporary storage: ' + token) }
  }
 }
}

fn main() {
 assert os.args.len == 2
 source := os.read_file(os.args[1])!
 prefix := if source.contains('i64 file__GpuFile__submit_g13_staged(') { 'file__' } else { 'gpu__agx__file__' }
 check(source, prefix)!
 for helper in ['G13SubmissionTimestamps__addresses', 'GpuFile__new_g13_submission_timestamps',
  'GpuFile__release_g13_submission_timestamps', 'GpuFile__submit_g13_staged', 'release_completed_g13_timestamps', 'discard_g13_completion'] {
  original := body(source, prefix + helper)!
  for allocation in ['memdup(0, 16);', 'memory__malloc_packed_fallible(16);', 'array_new(16, 64, 64);'] {
   mutant := source.replace(original, original.replace_once('{', '{ ' + allocation))
   if _ := check(mutant, prefix) { panic('accepted storage mutation: ' + helper) }
  }
 }
 println('AGX pending timestamp storage: 6 production helpers and 18 allocation counterexamples passed')
}
