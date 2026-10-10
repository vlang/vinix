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
fn unix_parent(path string) string {
 index := path.last_index('/') or { return '.' }
 return if index == 0 { '/' } else { path[..index] }
}
fn unix_mkdir_parents(path string) ! {
 os.mkdir(path) or {
  if os.is_dir(path) { return }
  // pathlib retries a missing parent, while other errors keep their order.
  if err.code() != 2 { return err }
  parent := unix_parent(path)
  if parent == path { return err }
  unix_mkdir_parents(parent)!
  os.mkdir(path) or { if os.is_dir(path) { return }; return err }
 }
}

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

fn generate(root string, work string) ! {
 os.write_file(unix_path(work,'v.mod'), "Module { name: 'scheduler_qos_test' }\n")!
 names := ['katomic','klock','errno']
 contents := [$embed_file('policytemplates/katomic.v').to_string(),
  $embed_file('policytemplates/klock.v').to_string(),
  $embed_file('policytemplates/errno.v').to_string()]
 for i,name in names {
  directory:=unix_path(work,name)
  if os.exists(directory) { return error('Module directory already exists: '+directory) }
  os.mkdir(directory)!
  os.write_file(unix_path(directory,name+'.v'),contents[i])!
 }
 priority:=read_source(unix_path(root,'kernel','proc','priority.v'))!
 mut proc_source := $embed_file('policytemplates/proc.v').to_string()
 for name in ['effective_sched_rank(', 'priority_donations_active(', 'recompute_donations(',
  'donate_priority(', 'remove_priority_donation(', 'retarget_priority_donation(',
  'refresh_priority_donations('] { proc_source += source_function(priority,name)! }
 directory:=unix_path(work,'proc')
 if os.exists(directory) { return error('Module directory already exists: '+directory) }
 os.mkdir(directory)!
 os.write_file(unix_path(directory,'proc.v'),proc_source)!
 source:=read_source(unix_path(root,'kernel','sched','runqueue.v'))!
 mut main_source := $embed_file('policytemplates/head.v').to_string()
 for name in ['cpu_capacity(', 'set_cpu_capacity(', 'placement_cpu(', 'capacity_preferred('] {
  main_source += source_function(source,name)!
 }
 timer:=read_source(unix_path(root,'kernel','time','time.v'))!
 main_source += $embed_file('policytemplates/timer.v').to_string()
 for name in ['(mut this Timer) disarm(', '(mut this Timer) arm(', 'timer_deadline(', 'next_wakeup_us('] {
  main_source += source_function(timer,name)!
 }
 main_source += $embed_file('policytemplates/assertions.v').to_string()
 os.write_file(unix_path(work,'main.v'),main_source)!
}

fn main() {
 if os.args.len==4 && os.args[1]=='--extract' {
  source:=read_source(os.args[2]) or { eprintln(err);exit(1) }
  print(source_function(source,os.args[3]) or { eprintln(err);exit(1) })
  return
 }
 if os.args.len!=3 { eprintln('Usage: scheduler-qos-generator REPOSITORY WORK');exit(2) }
 generate(os.args[1],os.args[2]) or { eprintln(err);exit(1) }
}
