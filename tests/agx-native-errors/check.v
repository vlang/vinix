// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn body(source string, name string) !string {
 mut position := 0
 for position < source.len {
  start := source.index_after(' ' + name + '(', position) or { break }
  end := source.index_after('\n', start) or { return error('signature') }
  position = end + 1
  if !source[start..end].ends_with('{') { continue }
  finish := source.index_after('\n}\n', end) or { return error('body') }
  return source[start..finish + 3]
 }
 return error('missing body: ' + name)
}
fn check(source string, probe bool) ! {
 prefix := if probe { 'file__' } else { 'gpu__agx__file__' }
 helpers := if probe { ['g13_pending_error', 'finish_g13_submit'] }
  else { ['g13_pending_error', 'cancel_g13_pending', 'poll_g13_pending', 'process_pending_submissions', 'finish_g13_submit', 'GpuFile__submit_g13_staged'] }
 for helper in helpers {
  text := body(source, prefix + helper)!
  if !text.contains('katomic__load_T_i64(') { return error(helper + ': missing full-width error load') }
  if text.contains('katomic__load_T_v_int(') || text.contains('katomic__store_T_v_int(') { return error(helper + ': native int error-width regression') }
  if helper in ['finish_g13_submit', 'cancel_g13_pending', 'poll_g13_pending'] && !text.contains('katomic__store_T_i64(') { return error(helper + ': missing full-width error store') }
 }
 for op in ['load', 'store'] {
  text := body(source, 'katomic__' + op + '_T_i64')!
  width := if op == 'load' { 'ldar' } else { 'stlr' }
  if !text.contains('vinix_' + width + '64(') || text.contains('vinix_' + width + '32(') { return error('incorrect native i64 instruction width') }
 }
}
fn main() {
 assert os.args.len == 3 && os.args[1] in ['--native', '--probe']
 source := os.read_file(os.args[2])!
 probe := os.args[1] == '--probe'
 check(source, probe)!
 for old, new in {'katomic__load_T_i64(': 'katomic__load_T_v_int(', 'katomic__store_T_i64(': 'katomic__store_T_v_int(', 'vinix_ldar64(': 'vinix_ldar32(', 'vinix_stlr64(': 'vinix_stlr32('} {
  assert source.contains(old)
  if _ := check(source.replace(old, new), probe) { panic('accepted native error-width mutation: ' + old) }
 }
 println('AGX native error widths: ' + (if probe { '2 probe' } else { '6 kernel' }) + ' callers, actual i64 instruction selection and 4 width mutations passed')
}
