// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import cachecli
import crypto.sha256
import hosttest
import os
import sourcecommand
import time

pub struct Tools {
pub:
 root string
 command_hook fn ([]string, bool, voidptr) !sourcecommand.Output = unsafe { nil }
 context voidptr
}

pub fn (tools Tools) command(argv []string, capture bool) !sourcecommand.Output {
 if argv.len == 0 || argv[0].all_after_last('/') in ['python', 'python3'] { return error('expected native command') }
 if tools.command_hook != unsafe { nil } { return tools.command_hook(argv, capture, tools.context) }
 result := if capture {
  sourcecommand.capture_stdout_preferred(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled, '')!
 } else {
  sourcecommand.run_preferred(argv, os.environ(), cachecli.cancelled, '')!
 }
 return result
}

pub fn (tools Tools) run(argv []string) ! {
 result := tools.command(argv, false)!
 if result.status != 0 { return error('command failed (${result.status}): ' + hosttest.shell_join(argv)) }
}

pub fn (tools Tools) output(argv []string) !string {
 result := tools.command(argv, true)!
 if result.status != 0 { return error('command failed (${result.status}): ' + hosttest.shell_join(argv)) }
 return result.stdout
}

pub fn path(base string, child string) string { return base.trim_right('/') + '/' + child }

pub fn parent(name string) string {
 at := name.last_index('/') or { return '.' }
 return if at == 0 { '/' } else { name[..at] }
}

pub fn mkdir(name string) ! {
 if os.is_dir(name) { return }
 previous := parent(name)
 if previous != name { mkdir(previous)! }
 os.mkdir(name)!
}

pub fn remove(name string) ! {
 if os.is_link(name) || os.is_file(name) { os.rm(name)!; return }
 if os.is_dir(name) {
  for entry in os.ls(name)! { remove(path(name,entry))! }
  os.rmdir(name)!
 }
}

pub fn copy_file(source string, destination string) ! {
 mkdir(parent(destination))!
 if os.exists(destination) || os.is_link(destination) { os.rm(destination)! }
 if os.is_link(source) {
  os.symlink(os.readlink(source)!, destination)!
 } else { hosttest.module_copy_file_preserving_stat(source, destination)! }
}

// Layer merges preserve links; installation copytree follows links and retains
// directory metadata, matching the original two distinct copy operations.
pub fn copy_tree(source string, destination string, follow bool) ! {
 mkdir(destination)!
 for name in os.ls(source)! {
  from := path(source,name); to := path(destination,name)
  if os.is_link(from) && !follow { copy_file(from,to)! }
  else if os.is_dir(from) { copy_tree(from,to,follow)! }
  else {
   if os.exists(to) || os.is_link(to) { os.rm(to)! }
   hosttest.module_copy_file_preserving_stat(from,to)!
  }
 }
 if follow { hosttest.module_copy_directory_stat(source,destination)! }
}

pub fn files(directory string) ![]string {
 mut result := []string{}
 if !os.is_dir(directory) { return result }
 for name in os.ls(directory)! {
  value := path(directory,name); result << value
  if os.is_dir(value) && !os.is_link(value) { result << files(value)! }
 }
 return result
}

pub fn digest(name string) !string {
 mut file := os.open(name)!; defer { file.close() }
 mut sum := sha256.new(); mut buffer := []u8{len: 1024 * 1024}
 for {
  count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
  if count == 0 { break }
  sum.write(buffer[..count])!
 }
 return sum.sum([]u8{}).hex()
}

pub fn pause(seconds f64) ! {
 until := time.sys_mono_now() + u64(seconds * f64(time.second))
 for time.sys_mono_now() < until {
  cachecli.checkpoint()!
  now := time.sys_mono_now()
  if now >= until { break }
  time.sleep(time.Duration(if until - now > 10 * time.millisecond { 10 * time.millisecond } else { until - now }))
 }
}

pub fn env(name string, fallback string) string { return os.getenv_opt(name) or { fallback } }
