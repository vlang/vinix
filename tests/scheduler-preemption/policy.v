// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import os

// The host fixtures use POSIX Path semantics: backslashes are filename bytes.
fn unix_path(base string, parts ...string) string {
 mut result := base.trim_right('/')
 for part in parts { result += '/' + part }
 return result
}
// Count every brace, preserving the original start position inside its line.
fn source_function(source string, name string) !string {
 start:=source.index('fn '+name+'(') or { return error('substring not found') }
 opening:=source[start..].index('{') or { return error('substring not found') }
 mut end:=start+opening+1
 mut depth:=1
 for depth!=0 {
  if end>=source.len { return error('string index out of range') }
  if source[end]==`{` { depth++ }
  if source[end]==`}` { depth-- }
  end++
 }
 return source[start..end]+'\n'
}

fn read_source(path string) !string {
 text := os.read_file(path)!
 if !utf8.validate_str(text) { return error('Invalid UTF-8 source: ' + path) }
 // Path.read_text uses universal newlines in the original host controller.
 return text.replace('\r\n', '\n').replace('\r', '\n')
}

fn assemble(root string) !string {
 source:=read_source(unix_path(root,'kernel','sched','preemption.v'))!
 mut program:=$embed_file('policytemplates/head.v').to_string()
 for name in ['enqueue_outranks','request_enqueue_preemption','consume_reschedule'] {
  program+=source_function(source,name)!
 }
 return program+$embed_file('policytemplates/assertions.v').to_string()
}
fn modules(work string) ! {
 proc_dir:=unix_path(work,'proc')
 if os.exists(proc_dir) { return error('Module directory already exists: '+proc_dir) }
 os.mkdir(proc_dir)!
 os.write_file(unix_path(proc_dir,'proc.v'),$embed_file('policytemplates/proc.v').to_string())!
 atomic_dir:=unix_path(work,'katomic')
 if os.exists(atomic_dir) { return error('Module directory already exists: '+atomic_dir) }
 os.mkdir(atomic_dir)!
 os.write_file(unix_path(atomic_dir,'katomic.v'),$embed_file('policytemplates/katomic.v').to_string())!
}
fn main() {
 if os.args.len==4 && os.args[1]=='--extract' {
  source:=read_source(os.args[2]) or { eprintln(err);exit(1) }
  print(source_function(source,os.args[3]) or { eprintln(err);exit(1) });return
 }
 if os.args.len!=3 { eprintln('Usage: preemption-generator --assemble ROOT | --modules WORK');exit(2) }
 match os.args[1] {
  '--assemble' { print(assemble(os.args[2]) or { eprintln(err);exit(1) }) }
  '--modules' { modules(os.args[2]) or { eprintln(err);exit(1) } }
  else { eprintln('Unknown generator phase: '+os.args[1]);exit(2) }
 }
}
