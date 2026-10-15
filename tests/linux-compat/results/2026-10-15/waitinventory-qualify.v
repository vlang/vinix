import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/waitinventory-20261015'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'
struct Receipt {
 base_commit string
 inputs_before int
 inputs_after int
 dispatch_unchanged bool
 changed_wait_source_rejected bool
 changed_wait_source_sha256 string
 restored_source_accepted bool
 artifacts map[string]string
}
fn command(program string,args []string,folder string,log string,expected int) string {
 mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 if log != '' {os.write_file(area+'/'+log,output) or {panic(err)}}
 assert code == expected,output; return output.trim_space()
}
fn digest(path string) string {return sha256.sum(os.read_bytes(path) or {panic(err)}).hex()}
fn main() {
 resume := os.args.len == 2 && os.args[1] == '--resume'
 assert os.exists(area+'/tree') == resume
 base := if resume {os.read_file(area+'/base.txt')!.trim_space()} else {command('git',['rev-parse','HEAD'],root,'',0)}
 command('git',['merge-base','--is-ancestor','eb7de67a3b096418d97509832973eb2956af692e',base],root,'',0)
 tree := area+'/tree'
 if resume {
  assert command('git',['rev-parse','HEAD'],tree,'',0) == base
  assert os.read_file(area+'/host-tests.log')!.contains('EmbedFileData error: files "../../../tests/go/smoke.go"')
  os.cp(area+'/host-tests.log',area+'/host-tests-incomplete-sparse-view.log')!
  command('git',['sparse-checkout','add','tests/go','tests/java'],tree,'sparse-complete.log',0)
 } else {
  os.write_file(area+'/base.txt',base+'\n')!
  command('git',['worktree','add','--detach','--no-checkout',tree,base],root,'prepare.log',0)
  command('git',['sparse-checkout','set','kernel','tools','tests/linux-compat','docs','build-support'],tree,'sparse.log',0)
  command('git',['checkout','--detach',base],tree,'checkout.log',0)
 }
 for path in ['tools/linux-compat/coverage.v','tools/linux-compat/coverage_test.v'] {os.cp(root+'/'+path,tree+'/'+path)!}
 old := json2.decode[json2.Any](os.read_file(tree+'/docs/linux-syscall-coverage.json')!)!.as_map()
 original_inputs := old['inputs']!.as_map_of_strings(); assert original_inputs.len == 66 && 'kernel/userland/linux_task.v' !in original_inputs
 command(compiler,['-enable-globals','-nocache','test',tree+'/tools/linux-compat'],tree,'host-tests.log',0)
 generate := ['-enable-globals','-nocache','-gc','none','-cc','cc','-cflags','-O2','run',tree+'/tools/linux-compat/coverage.v']
 command(compiler,generate,tree,'generate.log',0)
 command(compiler,[...generate,'--check'],tree,'check.log',0)
 fresh := json2.decode[json2.Any](os.read_file(tree+'/docs/linux-syscall-coverage.json')!)!.as_map()
 inputs := fresh['inputs']!.as_map_of_strings(); assert inputs.len == 67 && fresh['syscalls']!.str() == old['syscalls']!.str()
 assert inputs['kernel/userland/linux_task.v'] == digest(tree+'/kernel/userland/linux_task.v')
 for path,hash in original_inputs {if path != 'tools/linux-compat/coverage.v' {assert inputs[path] == hash}}
 path := tree+'/kernel/userland/linux_task.v'; source := os.read_file(path)!
 assert source.count('pid := int(i32(pid_word))') == 1
 os.write_file(path,source.replace('pid := int(i32(pid_word))','pid := int(pid_word)'))!
 changed := digest(path); assert changed != inputs['kernel/userland/linux_task.v']
 refused := command(compiler,[...generate,'--check'],tree,'changed-source-refusal.log',1)
 assert refused.contains('Stale coverage: docs/linux-syscall-coverage.')
 os.write_file(path,source)!
 assert digest(path) == inputs['kernel/userland/linux_task.v']
 command(compiler,[...generate,'--check'],tree,'restored-source-check.log',0)
 mut hashes := map[string]string{}
 for name in ['host-tests.log','host-tests-incomplete-sparse-view.log','generate.log','check.log','changed-source-refusal.log','restored-source-check.log'] {hashes[name] = digest(area+'/'+name)}
 for name in ['tools/linux-compat/coverage.v','tools/linux-compat/coverage_test.v','docs/linux-syscall-coverage.json','docs/linux-syscall-coverage.md','kernel/userland/linux_task.v'] {hashes[name] = digest(tree+'/'+name)}
 os.write_file(area+'/receipt.json',json2.encode(Receipt{base,66,67,true,true,changed,true,hashes},prettify:true)+'\n')!
 println('Wait inventory fingerprints and freshness: PASS')
}
