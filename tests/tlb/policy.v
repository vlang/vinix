// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import os

// Match the maintained extractor: count every brace, including those in text.
// The host adapters are independent fixtures; production function bodies are
// taken verbatim from the kernel under the supplied repository root.
fn source_function(source string, name string) !string {
 position := source.index('fn ' + name) or { return error('substring not found') }
 start := (source[..position].last_index('\n') or { -1 }) + 1
 opening := source[start..].index('{') or { return error('substring not found') }
 mut end := start + opening + 1
 mut depth := 1
 for depth != 0 {
  if end >= source.len { return error('string index out of range') }
  if source[end] == `{` { depth++ }
  if source[end] == `}` { depth-- }
  end++
 }
 return source[start..end] + '\n'
}

fn read_source(path string) !string {
 text := os.read_file(path)!
 if !utf8.validate_str(text) { return error('Invalid UTF-8 source: ' + path) }
 // Path.read_text uses universal newlines in the original host controller.
 return text.replace('\r\n', '\n').replace('\r', '\n')
}

fn source_functions(root string, file string, names []string) !string {
 mut result := ''
 source := read_source(os.join_path(root, 'kernel', 'memory', file))!
 for name in names { result += source_function(source, name)! }
 return result
}

fn generate(root string, work string) ! {
 os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'address_space_test' }\n")!
 names := ['limine', 'katomic', 'klock', 'x86/cpu']
 modules := [
  $embed_file('policytemplates/limine.v').to_string(),
  $embed_file('policytemplates/katomic.v').to_string(),
  $embed_file('policytemplates/klock.v').to_string(),
  $embed_file('policytemplates/x86/cpu.v').to_string(),
 ]
 for i,name in names {
  path := os.join_path(work, name)
  // Each module directory is new, just as in the disposable Python fixture.
  if os.exists(path) { return error('Module directory already exists: ' + path) }
  os.mkdir_all(path)!
  os.write_file(os.join_path(path, os.base(path) + '.v'), modules[i])!
 }
 mut main_source := $embed_file('policytemplates/head.v').to_string()
 main_source += source_functions(root,'pcid_amd64.v',[
  'enable_pcid(', 'take_pcid(', '(pagemap &Pagemap) tagged_root(',
  'switch_cr3(', 'invalidate_local_tlb(', '(pagemap &Pagemap) prepare_tlb_teardown(',
  '(pagemap &Pagemap) invalidate_context(', '(mut pagemap Pagemap) release_tlb_tag(',
  'pcid_selftest(',
 ])!
 main_source += source_functions(root,'direct_cache_amd64.v',[
  'record_direct_mtrr(', 'direct_cache_uniform(', 'direct_large_eligible(',
 ])!
 main_source += source_functions(root,'largepage_amd64.v',[
  'small_leaf_flags(', 'large_leaf_phys(', 'amd64_leaf_level(',
  '(pagemap &Pagemap) kernel_pde(', '(pagemap &Pagemap) kernel_block_matches(',
  '(pagemap &Pagemap) split_kernel_leaf(', '(pagemap &Pagemap) kernel_leaf_phys(', 'map_direct_span(',
 ])!
 main_source += source_functions(root,'virtual_amd64.v',[
  'get_next_level(', '(pagemap &Pagemap) virt2pte(', '(pagemap &Pagemap) virt2phys(',
  '(mut pagemap Pagemap) map_page(', '(mut pagemap Pagemap) map_page_unlocked(',
  '(mut pagemap Pagemap) flag_page(', 'table_empty_after_clear(',
  '(mut pagemap Pagemap) unmap_page(', '(mut pagemap Pagemap) unmap_page_unlocked(',
 ])!
 main_source += $embed_file('policytemplates/assertions.v').to_string()
 os.write_file(os.join_path(work, 'main.v'), main_source)!
}

fn main() {
 if os.args.len == 4 && os.args[1] == '--extract' {
  source := read_source(os.args[2]) or { eprintln(err); exit(1) }
  result := source_function(source,os.args[3]) or { eprintln(err); exit(1) }
  print(result)
  return
 }
 if os.args.len != 3 { eprintln('Usage: policy-generator REPOSITORY WORK'); exit(2) }
 generate(os.args[1],os.args[2]) or { eprintln(err); exit(1) }
}
