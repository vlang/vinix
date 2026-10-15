import os
const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/robustquery-20261015'
fn main() {
 old := os.read_file(root+'/tests/linux-compat/waitstatusfixture/core.v')!
 start := old.index('fn snapshot(') or {panic(err)}
 source := old[start..].replace('waitstatus','robustquery').replace('WAITSTATUS','ROBUSTQUERY')
 os.write_file(root+'/tests/linux-compat/robustqueryfixture/core.v',os.read_file(root+'/tests/linux-compat/robustqueryfixture/core.v')!+'\n'+source)!
 for paths in [['waitstatus-reference.v','robustquery-reference.v'],['waitstatusreferenceinit/core.v','robustqueryreferenceinit/core.v']] {
  target := root+'/tests/linux-compat/'+paths[1]; os.mkdir_all(os.dir(target))!
  mut text := os.read_file(root+'/tests/linux-compat/'+paths[0])!.replace('waitstatus','robustquery').replace('WAITSTATUS','ROBUSTQUERY')
  if paths[0] == 'waitstatus-reference.v' {
   previous := '\t\t\t72,\n\t\t\t96,\n\t\t\t96,\n\t\t\t168,\n\t\t\t72,\n\t\t\t120,'
   assert text.count(previous) == 1
   text = text.replace(previous,'\t\t\t264,\n\t\t\t360,\n\t\t\t288,\n\t\t\t288,\n\t\t\t288,\n\t\t\t24,')
  }
  os.write_file(target,text)!
 }
 run_path := root+'/tests/linux-compat/run.v'; run := os.read_file(run_path)!
 assert run.count('waitstatus]') == 1 && run.count("waitstatus').split") == 1 && run.count("'waitstatus']") == 1
 os.write_file(run_path,run.replace('waitstatus]','waitstatus,robustquery]').replace("waitstatus').split","waitstatus,robustquery').split").replace("'waitstatus']","'waitstatus', 'robustquery']"))!
 path := root+'/kernel/userland/linux_task.v'; before := os.read_file(path)!
 previous := '\tif head_ptr == 0 || len_ptr == 0 {\n\t\treturn errno.err, errno.efault\n\t}\n\n\tlen := robust_list_head_size\n\n\tif !usercopy.copy_to_user(head_ptr, voidptr(&head), sizeof(u64)) {\n\t\treturn errno.err, errno.efault\n\t}\n\tif !usercopy.copy_to_user(len_ptr, voidptr(&len), sizeof(u64)) {'
 replacement := '\t// Linux publishes the size before the head, including when outputs overlap\n\t// or the later head store faults. Resolve each complete scalar first so a\n\t// stable split-page fault leaves that scalar untouched.\n\tlen := robust_list_head_size\n\tif !usercopy.user_range(len_ptr, sizeof(u64))\n\t\t|| !usercopy.writable(len_ptr) || !usercopy.writable(len_ptr + 7)\n\t\t|| !usercopy.copy_to_user(len_ptr, voidptr(&len), sizeof(u64)) {\n\t\treturn errno.err, errno.efault\n\t}\n\tif !usercopy.user_range(head_ptr, sizeof(u64))\n\t\t|| !usercopy.writable(head_ptr) || !usercopy.writable(head_ptr + 7)\n\t\t|| !usercopy.copy_to_user(head_ptr, voidptr(&head), sizeof(u64)) {'
 assert before.count(previous) == 1
 os.write_file(area+'/source-previous.txt',previous)!; os.write_file(area+'/source-replacement.txt',replacement)!
 os.write_file(path,before.replace(previous,replacement))!
 os.cp(area+'/linux-futex-syscalls-v6.12.c',area+'/initial-primary-fetch-refusal.log')!
}
