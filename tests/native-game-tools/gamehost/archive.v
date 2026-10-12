// SPDX-License-Identifier: GPL-2.0-or-later
module gamehost

import os
import tarcore

#include <pwd.h>
#include <grp.h>
struct C.passwd { pw_name &char }
struct C.group { gr_name &char }
fn C.getpwuid(u32) &C.passwd
fn C.getgrgid(u32) &C.group

pub fn archive(root string, destination string) ! {
 mut writer := tarcore.create_stream(destination)!; defer { writer.close() }
 mut inodes := map[string]string{}
 add_tree(mut writer,root,'.',mut inodes)!
 writer.finish()!; writer.close_checked()!
}

fn add_tree(mut writer tarcore.Writer, source string, name string, mut inodes map[string]string) ! {
 state := os.lstat(source)!
 mut member := tarcore.Member{name:name,mode:i64(state.mode & 0o7777),uid:state.uid,gid:state.gid,mtime:state.mtime}
 user := C.getpwuid(state.uid); if user != unsafe { nil } { member.uname = unsafe { user.pw_name.vstring().clone() } }
 group := C.getgrgid(state.gid); if group != unsafe { nil } { member.gname = unsafe { group.gr_name.vstring().clone() } }
 match state.get_filetype() {
  .directory { member.kind = `5` }
  .symbolic_link { member.kind = `2`; member.linkname = os.readlink(source)! }
  .regular {
   key := '${state.dev}:${state.inode}'
   if previous := inodes[key] { member.kind = `1`; member.linkname = previous }
   else { member.size = i64(state.size); if state.nlink > 1 { inodes[key] = name } }
  }
  .fifo { member.kind = `6` }
  .character_device, .block_device {
   member.kind = if state.get_filetype() == .character_device { u8(`3`) } else { u8(`4`) }
   member.major = i64(C.major(state.rdev)); member.minor = i64(C.minor(state.rdev))
  }
  else { return }
 }
 writer.write(tarcore.header(member)!)!
 if member.regular() {
  mut file := os.open(source)!; defer { file.close() }
  mut remaining := member.size; mut buffer := []u8{len:1024 * 1024}
  for remaining > 0 {
   count := file.read(mut buffer[..int(if remaining < buffer.len { remaining } else { buffer.len })])!
   if count == 0 { return error('archive input truncated: ' + source) }
   writer.write(buffer[..count])!; remaining -= count
  }
  writer.padding(member.size)!
 }
 if member.kind == `5` {
  mut children := os.ls(source)!; children.sort()
  for child in children { add_tree(mut writer,path(source,child),path(name,child),mut inodes)! }
 }
}
