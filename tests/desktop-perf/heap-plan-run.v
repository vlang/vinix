// SPDX-License-Identifier: GPL-2.0-or-later
// Execute reviewed heap compiler qualification actions with endpoint receipts.
module main

import crypto.sha256
import json2
import os
import sourcecommand
import time

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
fn C.open(&char, i32, ...int) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

struct Action {
 id string
 cwd string
 argv []string
 exit int
 marker string
 environment map[string]string
}
struct Phase { id string environment map[string]string actions []Action }
struct Bounds { charged_roots []string allocated_and_apparent_ceiling_kib u64
 reserve_inside_ceiling_kib u64 new_phase_free_floor_kib u64 action_endpoint_free_floor_kib u64
 each_log_limit_bytes int aggregate_log_limit_bytes int }
struct Parent { root string executable_sha256 string complete_literal_manifest string manifest_sha256 string }
struct Sealer { path string sha256 string parent_check_argv []string source_seal_before_argv []string source_check_after_argv []string require_marker string }
struct Environments { preparer map[string]string }
struct Plan { worktree string state string prior_state string source_revision string source_pins map[string]string
 derived_root string derived_manifest string derived_sha256 string derived_manifest_sha256 string
 bounds Bounds parent Parent original_sealer Sealer environments Environments phases []Phase }
struct Receipt { argv []string environment map[string]string cwd string status int elapsed_ms i64 output_sha256 string }
struct Endpoint { free_kib u64 allocated_kib u64 apparent_kib u64 }

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn never_cancel() bool { return false }
fn ignored_spawn(_ int, _ voidptr) ! {}
struct LogContext { fd i32 }
fn preserve_chunk(chunk string, context voidptr) ! {
 ctx := unsafe { &LogContext(context) }
 mut offset := 0
 for offset < chunk.len {
  count := C.write(ctx.fd, unsafe { chunk.str + offset }, usize(chunk.len - offset))
  if count < 0 && C.errno == C.EINTR { continue }
  require(count > 0 && count <= chunk.len - offset, 'action log write failed')!
  offset += int(count)
 }
}
fn capture(argv []string, environment map[string]string, cwd string, timeout f64, limit int) !sourcecommand.Output {
 return sourcecommand.capture_combined_owned(argv, environment, timeout, limit, never_cancel,
  unsafe { nil }, ignored_spawn, unsafe { nil }, 5, cwd)
}
fn run(plan Plan, name string, argv []string, environment map[string]string, cwd string, expected int, marker string) ! {
 path := plan.state + '/' + name
 require(!os.exists(path + '.log') && !os.exists(path + '.status.json'), 'action receipt exists: ' + name)!
 os.write_file(path + '.argv.json', json2.encode(argv) + '\n')!
 os.write_file(path + '.environment.json', json2.encode(environment) + '\n')!
 fd := C.open((path + '.log').str, C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
 require(fd >= 0, 'cannot exclusively open action log')!
 defer { C.close(fd) }
 context := LogContext{fd}
 start := time.sys_mono_now()
 result := sourcecommand.capture_combined_owned(argv, environment, 1000,
  plan.bounds.each_log_limit_bytes, never_cancel, preserve_chunk, ignored_spawn,
  unsafe { &context }, 5, cwd) or {
  os.write_file(path + '.failure.txt', err.msg() + '\n')!
  return err
 }
 require(os.read_file(path + '.log')! == result.stdout, 'preserved action output differs')!
 os.write_file(path + '.status.json', json2.encode(Receipt{argv, environment, cwd,
  result.status, (time.sys_mono_now() - start) / time.millisecond, sha256.hexhash(result.stdout)}) + '\n')!
 require(result.status == expected, 'unexpected status for ' + name + ': ' + result.status.str())!
 require(marker == '' || result.stdout.contains(marker), 'required marker absent: ' + name)!
 println(name + ' status=' + result.status.str() + ' PASS')
}
fn small(argv []string) !string {
 result := capture(argv, {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'}, '/', 10, 1024 * 1024)!
 require(result.status == 0, 'endpoint probe failed: ' + argv.str())!
 return result.stdout
}
fn decimal(text string) !u64 {
 require(text.len > 0 && text.bytes().all(it >= `0` && it <= `9`), 'invalid probe decimal')!
 return text.u64()
}
fn usage(text string) !u64 {
 mut total := u64(0)
 for line in text.split_into_lines() {
  if line.trim_space() == '' { continue }
  fields := line.fields()
  require(fields.len >= 2, 'invalid du row')!
  amount := decimal(fields[0])!
  require(total <= ~u64(0) - amount, 'du sum overflow')!
  total += amount
 }
 return total
}
fn endpoint(plan Plan, name string, admission bool) ! {
 mut roots := []string{}
 for root in plan.bounds.charged_roots { if os.exists(root) { roots << root } }
 if plan.prior_state != '' { roots << plan.prior_state }
 allocated := small(['/usr/bin/du', '-skl', ...roots])!
 apparent := small(['/usr/bin/du', '-skAl', ...roots])!
 df := small(['/bin/df', '-k', plan.worktree])!
 rows := df.trim_space().split_into_lines()
 fields := rows.last().fields()
 require(fields.len >= 4, 'invalid df row')!
 values := Endpoint{decimal(fields[3])!, usage(allocated)!, usage(apparent)!}
 os.write_file(plan.state + '/' + name + '.df.txt', df)!
 os.write_file(plan.state + '/' + name + '.du-allocated.txt', allocated)!
 os.write_file(plan.state + '/' + name + '.du-apparent.txt', apparent)!
 os.write_file(plan.state + '/' + name + '.endpoint.json', json2.encode(values) + '\n')!
 floor := if admission { plan.bounds.new_phase_free_floor_kib } else { plan.bounds.action_endpoint_free_floor_kib }
 require(values.free_kib >= floor, 'free-space endpoint floor refused')!
 ceiling := plan.bounds.allocated_and_apparent_ceiling_kib - plan.bounds.reserve_inside_ceiling_kib
 require(values.allocated_kib <= ceiling && values.apparent_kib <= ceiling, 'charged roots consume reserved ceiling')!
 mut logs := u64(0)
 for log_name in os.ls(plan.state)! {
  if log_name.ends_with('.log') { logs += os.file_size(plan.state + '/' + log_name) }
 }
 require(logs <= u64(plan.bounds.aggregate_log_limit_bytes), 'aggregate log cap refused')!
}
fn sources(plan Plan) ! {
 for path, pin in plan.source_pins {
  require(hash(plan.worktree + '/' + path)! == pin, 'reviewed source pin differs: ' + path)!
 }
 require(hash(plan.worktree + '/tests/desktop-perf/measure.c')! ==
  '2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771', 'legacy source differs')!
 require(hash(plan.parent.root + '/v')! == plan.parent.executable_sha256
  && hash(plan.parent.complete_literal_manifest)! == plan.parent.manifest_sha256
  && hash(plan.original_sealer.path)! == plan.original_sealer.sha256, 'parent/sealer pin differs')!
 if plan.derived_root != '' {
  require(hash(plan.derived_root + '/v-next')! == plan.derived_sha256
   && hash(plan.derived_manifest)! == plan.derived_manifest_sha256, 'qualified derived compiler pin differs')!
 }
}
fn derived_root(plan Plan) string { return if plan.derived_root != '' { plan.derived_root } else { plan.state + '/toolchain' } }
fn derived_manifest(plan Plan) string { return if plan.derived_manifest != '' { plan.derived_manifest } else { plan.state + '/derived-before/inventory.json' } }
fn original_check(plan Plan, name string, root string, manifest string) ! {
 run(plan, name, ['/opt/homebrew/bin/gtimeout', '--signal=TERM', '--kill-after=5s', '300s',
  plan.original_sealer.path, 'check', root, manifest], plan.environments.preparer, plan.worktree,
  0, plan.original_sealer.require_marker)!
}
fn original_seal(plan Plan, name string, root string, output string) ! {
 run(plan, name, ['/opt/homebrew/bin/gtimeout', '--signal=TERM', '--kill-after=5s', '300s',
  plan.original_sealer.path, 'seal', root, output], plan.environments.preparer, plan.worktree,
  0, 'FRAME-PAGE COMPLETE STATE PASS ')!
}
fn pins(plan Plan, name string, manifest string) ! {
 text := os.read_file(manifest)!
 for line in text.split_into_lines() {
  if line == '' { continue }
  require(line.len > 66 && line[64..66] in ['  ', ' *'], 'unsupported retained pin row')!
  if !os.is_abs_path(line[66..]) { continue } // Current source pins are explicit in the new plan.
  require(hash(line[66..])! == line[..64], 'retained input pin differs: ' + line[66..])!
 }
 os.write_file(plan.state + '/' + name + '.sha256', text)!
}
fn execute(plan_path string, phase_id string) ! {
 text := os.read_file(plan_path)!
 plan := json2.decode[Plan](text)!
 require(os.real_path(plan.worktree) == plan.worktree && plan.state.starts_with('/Users/alex/Library/Caches/vinix-codex/section14/'), 'unsupported plan roots')!
 require(plan.bounds.allocated_and_apparent_ceiling_kib == 786432
  && plan.bounds.reserve_inside_ceiling_kib == 131072, 'reviewed cap differs')!
 sources(plan)!
 if phase_id == 'init' {
  require(!os.exists(plan.state) && !os.is_link(plan.state), 'state must be fresh')!
  available := small(['/bin/df', '-k', plan.worktree])!.trim_space().split_into_lines().last().fields()[3]
  require(decimal(available)! >= plan.bounds.new_phase_free_floor_kib, 'admission free space refused')!
  os.mkdir(plan.state, mode: 0o700)!
  os.write_file(plan.state + '/plan.json', text)!
  for kind in ['preparer', 'bootstrap', 'qualification'] {
   for directory in ['modules', 'cache', 'tmp'] {
    os.mkdir_all(plan.state + '/' + kind + '-private/' + directory)!
   }
  }
  for directory in ['qualification/host', 'targets', 'source-capture', 'bootstrap-output'] { os.mkdir_all(plan.state + '/' + directory)! }
  endpoint(plan, 'admission', true)!
  for path, _ in plan.source_pins {
   output := plan.state + '/source-capture/' + path
   os.mkdir_all(os.dir(output))!
   os.cp(plan.worktree + '/' + path, output)!
  }
  os.cp(plan.worktree + '/tests/desktop-perf/measure.c', plan.state + '/source-capture/measure.c')!
  pins(plan, 'direct-inputs-before', '/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-target-build-20261104-02/pins-before.sha256')!
  pins(plan, 'archives-before', '/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-target-build-20261104-02/archives-before.sha256')!
  original_check(plan, 'parent-before', plan.parent.root, plan.parent.complete_literal_manifest)!
  original_seal(plan, 'source-before', plan.worktree, plan.state + '/source-before')!
  endpoint(plan, 'init-after', false)!
  return
 }
 require(os.read_file(plan.state + '/plan.json')! == text, 'retained plan changed')!
 mut selected := Phase{}
 for phase in plan.phases { if phase.id == phase_id { selected = phase } }
 require(selected.id != '', 'unknown phase')!
 endpoint(plan, phase_id + '-admission', true)!
 original_check(plan, phase_id + '-parent-before', plan.parent.root, plan.parent.complete_literal_manifest)!
 original_check(plan, phase_id + '-source-before', plan.worktree, plan.state + '/source-before/inventory.json')!
 if phase_id != 'D' {
  original_check(plan, phase_id + '-derived-before', derived_root(plan), derived_manifest(plan))!
 }
 mut failed := ''
 for index, action in selected.actions {
  name := if action.id != '' { action.id } else { phase_id + '-' + (index + 1).str() }
  environment := if action.environment.len > 0 { action.environment } else { selected.environment }
  cwd := if action.cwd != '' { action.cwd } else { plan.worktree }
  mut argv := action.argv.clone()
  if name == 'D-09' {
   // The compiler writes <output>.c. Keep that evidence outside the exact derived tree.
   old := plan.state + '/toolchain/v-next'
   mut replacements := 0
   for at, argument in argv {
    if argument == old { argv[at] = plan.state + '/bootstrap-output/v-next'; replacements++ }
   }
   require(replacements == 1, 'bootstrap output amendment differs')!
   os.write_file(plan.state + '/bootstrap-output-amendment.json', json2.encode({
    'reason': 'Explicit C backend retains output.c; only the new binary enters the derived tree.'
    'original_argv': json2.encode(action.argv)
    'amended_argv': json2.encode(argv)
   }) + '\n')!
  }
  run(plan, name, argv, environment, cwd, action.exit, action.marker) or { failed = err.msg(); break }
  if name == 'D-09' {
   output := plan.state + '/bootstrap-output/v-next'
   require(os.is_file(output + '.c') && !os.is_link(output) && os.lstat(output)!.nlink == 1,
    'bootstrap must retain independent binary and generated C')!
   os.cp(output, plan.state + '/toolchain/v-next')!
   os.chmod(plan.state + '/toolchain/v-next', 0o755)!
   os.write_file(plan.state + '/bootstrap-output/artifacts.sha256', hash(output)! + '  ' + output + '\n'
    + hash(output + '.c')! + '  ' + output + '.c\n')!
  }
  endpoint(plan, name + '-after', false) or { failed = err.msg(); break }
  if name == 'D-07' { original_seal(plan, 'derived-source-before', plan.state + '/toolchain', plan.state + '/derived-source-before')! }
  if name == 'D-08' { original_check(plan, 'derived-refusal-after', plan.state + '/toolchain', plan.state + '/derived-source-before/inventory.json')! }
 }
 sources(plan)!
 original_check(plan, phase_id + '-source-after', plan.worktree, plan.state + '/source-before/inventory.json')!
 original_check(plan, phase_id + '-parent-after', plan.parent.root, plan.parent.complete_literal_manifest)!
 pins(plan, phase_id + '-direct-inputs-after', plan.state + '/direct-inputs-before.sha256')!
 pins(plan, phase_id + '-archives-after', plan.state + '/archives-before.sha256')!
 endpoint(plan, phase_id + '-final', false)!
 require(failed == '', failed)!
 if phase_id == 'D' {
  pin := hash(plan.state + '/toolchain/v-next')!
  os.write_file(plan.state + '/derived-compiler.sha256', pin + '\n')!
  run(plan, 'derived-verify', ['/opt/homebrew/bin/gtimeout', '--signal=TERM', '--kill-after=5s', '300s',
   plan.state + '/preparer-production', 'verify', plan.state, pin], plan.environments.preparer, plan.worktree,
   0, 'HEAP COMPILER exact derived sources, pinned new compiler and unchanged parent PASS')!
  original_seal(plan, 'derived-before', plan.state + '/toolchain', plan.state + '/derived-before')!
  original_check(plan, 'derived-independent', plan.state + '/toolchain', plan.state + '/derived-before/inventory.json')!
 } else {
  original_check(plan, phase_id + '-derived-after', derived_root(plan), derived_manifest(plan))!
 }
 println('HEAP PLAN ' + phase_id + ' PASS')
}
fn replace_argv(text string, old []string, next []string) !string {
 anchor := '"' + old[4] + '"'
 require(text.count(anchor) == 1, 'exact compiler action must occur once')!
 at := text.index(anchor) or { return error('compiler anchor absent') }
 start := text[..at].last_index('[') or { return error('action array absent') }
 closing := text[at..].index(']') or { return error('action array is incomplete') }
 end := at + closing + 1
 require(json2.decode[[]string](text[start..end])! == old, 'exact action argv differs')!
 return text[..start] + json2.encode(next, prettify: true).replace('\n', '\n          ') + text[end..]
}
fn retry_plan(input string, output string, next_state string) ! {
 original := os.read_file(input)!
 plan := json2.decode[Plan](original)!
 require(!os.exists(output) && !os.exists(next_state), 'retry plan and state must be fresh')!
 mut amended := original.replace(plan.state, next_state)
 root := plan.state + '/toolchain'
 manifest := plan.state + '/derived-before/inventory.json'
 amended = amended.replace(next_state + '/toolchain', root)
 for path, pin in plan.source_pins {
  amended = amended.replace(pin, hash(plan.worktree + '/' + path)!)
 }
 runner := 'tests/desktop-perf/heap-plan-run.v'
 amended = amended.replace_once('"source_pins": {\n', '"source_pins": {\n    "' + runner + '": "' + hash(plan.worktree + '/' + runner)! + '",\n')
 amended = amended.replace_once('{\n', '{\n  "derived_root": "' + root + '",\n  "derived_manifest": "' + manifest
  + '",\n  "derived_sha256": "' + hash(root + '/v-next')! + '",\n  "derived_manifest_sha256": "' + hash(manifest)! + '",\n')
 amended = amended.replace_once('"charged_roots": [\n', '"charged_roots": [\n      "' + plan.state + '",\n      "/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-value-cursor-scout-20261105-01",\n')
 for phase in plan.phases {
  if phase.id != 'B3' { continue }
  for action in phase.actions {
   if action.argv.len < 5 || !action.argv[4].ends_with('/x86_64-linux-musl-gcc') { continue }
   old := action.argv.map(it.replace(plan.state, next_state))
   gcc := '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/lib/gcc/x86_64-linux-musl/14.2.0'
   musl := '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/x86_64-linux-musl'
   mut next := old[..4].clone()
   next << ['/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23', '--no-default-config', '--target=x86_64-linux-musl',
    '-static', '-nostdinc', '-nostdlib', '-isystem', gcc + '/include', '-isystem', gcc + '/include-fixed',
    '-isystem', musl + '/include', '-fno-stack-protector', musl + '/lib/crt1.o', musl + '/lib/crti.o',
    gcc + '/crtbeginT.o', '-L' + musl + '/lib', '-L' + gcc, '-fuse-ld=/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld']
   next << old[5..]
   next << ['-lc', '-lgcc', '-lgcc_eh', gcc + '/crtend.o', musl + '/lib/crtn.o']
   amended = replace_argv(amended, old, next)!
  }
 }
 os.write_file(output, amended)!
 println('HEAP retry plan pins current sources, unchanged derived compiler and strict x86 Clang closure')
}
fn main() {
 if os.args.len == 5 && os.args[1] == 'retry-plan' {
  retry_plan(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len == 6 && os.args[1] == 'fork-plan' {
  original := os.read_file(os.args[2]) or { panic(err) }
  plan := json2.decode[Plan](original) or { panic(err) }
  if os.exists(os.args[3]) || plan.state != os.args[4] || os.exists(os.args[5]) { panic('fork requires fresh output and state') }
  amended := original.replace(plan.state, os.args[5]).replace_once('{\n', '{\n  "prior_state": "' + plan.state + '",\n')
  os.write_file(os.args[3], amended) or { panic(err) }
  return
 }
 if os.args.len != 3 { eprintln('usage: heap-plan-run PLAN init|D|A2|B3'); exit(2) }
 execute(os.args[1], os.args[2]) or { eprintln('heap-plan-run: ' + err.msg()); exit(1) }
}
