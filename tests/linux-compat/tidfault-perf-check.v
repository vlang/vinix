// Compile without -prod and add tests/desktop-perf to the module path.
import crypto.sha256
import json2
import os
import perfreport
#include <stdlib.h>
$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr,voidptr,u32) i32
fn C.CC_SHA256_Final(&u8,voidptr) i32
fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}
		state.checksum_into(mut result)
		return result.hex()
	}
}

struct PerformanceEvidence {context string kernel_sha256 string general_retention_flat bool unresolved_growth []string artifacts map[string]string}
fn main() {
 if '--negative-control' in os.args {assert false,'tidfault performance assertions must execute'; return}
 assert os.args.len == 2,'Usage: tidfault-perf-check.v EVIDENCE-AREA (compile without -prod; add tests/desktop-perf to the V module path)'
 area := os.args[1].trim_right('/')+'/'
 root := '/Users/alex/code/vinix/'
 out := root+'tests/linux-compat/results/2026-10-15/'
 mut pins := map[string]string{}
 mut growth := []string{}
 for label,scenarios in {'ops':['ops','churn','cache'],'desktop':['idle','apps','drag']} {
  assert os.read_file(area+'perf-'+label+'.status')!.trim_space() == '0'
  log := os.read_file(area+'perf-'+label+'/serial.log')!
  verdict := perfreport.inspect(log.bytes(),['new'],scenarios,1,false,perfreport.Value(perfreport.Number{'0'}))
  assert verdict.errors.len == 0,verdict.errors.join('\n')
  assert perfreport.encode(perfreport.Value(verdict.rows.map(perfreport.Value(it))),true)+'\n' == os.read_file(area+'perf-'+label+'.json')!
  if label == 'ops' {
   mut operations := 0; mut programs := 0; mut caches := 0
   for row in verdict.rows {
    kind := perfreport.string_value(perfreport.value(row,'report'))
    if kind == 'PERF-OPS' {assert perfreport.string_value(perfreport.value(row,'count')) == '200'; operations++}
    else if kind == 'PERF-CHURN' {assert perfreport.string_value(perfreport.value(row,'runs')) == '300'; programs++}
    else if kind == 'PERF-CACHE' {caches++}
   }
   assert operations == 36 && programs == 4 && caches == 1
   for line in log.split_into_lines() {
    mut positive := false
    if line.starts_with('PERF-OPS ') {for field in line.fields() {if field.starts_with('size-') || field.starts_with('large_pages:') {positive = positive || field.all_after(':').i64() > 0}; if field.starts_with('bytes_per_op=') {positive = positive || field.all_after('=').i64() > 0}}}
    if line.starts_with('PERF-CHURN ') {for field in line.fields() {if field.starts_with('retained_kb=') || field.starts_with('per_run_bytes=') {positive = positive || field.all_after('=').i64() > 0}}}
    if line.starts_with('PERF-SLAB ') {for field in line.fields() {if field.starts_with('objects=') || field.starts_with('pages=') {positive = positive || field.all_after('=').i64() > 0}}}
    if positive {growth << line.trim_space()}
   }
  } else {assert verdict.rows.len == 3}
  for path in [area+'perf-'+label+'/serial.log',area+'perf-'+label+'.json',area+'perf-'+label+'.status'] {pins[path] = digest(path); publish(path,out+'tidfault-perf-'+label+'-'+os.file_name(path))!}
 }
 // Preserve the exact observed finding. Additional positive rows must be
 // investigated and explicitly reported rather than accepted implicitly.
 assert growth == ['PERF-OPS variant=new scenario=ops round=1 op=rename dir=/root count=200 bytes_per_op=1 size-256:+1']
 native := json2.decode[json2.Any](os.read_file(area+'states/p2-after-arm/receipt.json')!)!.as_map()
 kernel := area+'kernel-arm/kernel/bin/vinix'; assert digest(kernel) == native['kernel_sha256']!.str()
 pins[kernel] = digest(kernel); pins[area+'states/p2-after-arm/receipt.json'] = digest(area+'states/p2-after-arm/receipt.json')
 helper := area+'desktop-retention'; helper_time := os.file_last_mod_unix(helper)
 for directory in ['tests/desktop-perf/perfrunner','tests/desktop-perf/perfconsole','tests/desktop-perf/perfreport','tools/sourcecommand','tests/linuxkpi/hosttest'] {
  for path in os.walk_ext(root+directory,'.v') {assert os.file_last_mod_unix(path) <= helper_time,'harness changed after the executable was compiled: '+path; pins[path] = digest(path)}
 }
 for path in [root+'tests/desktop-perf/measure.c',root+'tests/desktop-perf/perf-init.sh',root+'scripts/run-aarch64.sh',root+'build-support/init-aarch64/initramfs-desktop.tar',root+'logs/desktop-ram-fix/vinix-desktop-arm64',root+'build/qemu-horizontal/bin/qemu-system-aarch64',root+'boot-image/edk2-aarch64-code-2048x1536.fd'] {assert os.file_last_mod_unix(path) <= helper_time; pins[path] = digest(path)}
 assert os.read_file(area+'perf-ops-producer.log')! == ''
 assert os.read_file(area+'performance-audit-refused-compile.log')!.contains('strtod') && os.read_file(area+'performance-audit-refused-compile.log')!.contains('stdlib.h')
 assert os.read_file(area+'performance-strict-refusal.log.status')!.trim_space() == '1' && os.read_file(area+'performance-strict-refusal.log')!.contains('bytes_per_op')
 for name in ['prepare-perf-finding.v','performance-audit-strict.v','performance-audit-strict','perf-contracts-strict.txt','performance-strict-refusal.log','performance-strict-refusal.log.status','run-performance-evidence.v','run-performance-evidence','performance-evidence-compile.log'] {pins[area+name] = digest(area+name)}
 for name in ['desktop-setup.v','desktop-retention.v','desktop-retention','perf-ops-producer.log','perf-ops-started-producer.log','perf-desktop-producer.log','perf-contracts.txt','create-perf-audit.v','compile-perf-audit.v','compile-perf-audit','compile-perf-audit-producer.log','performance-audit-refused.v','performance-audit-refused-compile.log','performance-audit-corrected-compile.log','create-performance-audit.log'] {pins[area+name] = digest(area+name)}
 mut p := os.new_process(os.executable()); p.set_args(['--negative-control']); p.set_redirect_stdio_merged(); p.run(); control := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 1 && control.contains('tidfault performance assertions must execute')
 os.write_file(area+'perf-assertion-control.log',control)!; pins[area+'perf-assertion-control.log'] = digest(area+'perf-assertion-control.log'); pins[@FILE] = digest(@FILE)
 publication := json2.encode(PerformanceEvidence{
  context:'Native AArch64 supplementary regression evidence:36 warmed 200-operation tmpfs/EXT2 cohorts, four warmed 300-execution program cohorts, separate cache costs, and passing idle/apps/drag desktop smoke. The general retention gate remains OPEN: the EXT2 rename cohort retains one size256 object; its cause/reproducibility are unresolved. The strict flat-retention auditor actually refuses this run; its original source/binary and refusal remain pinned. All positive growth rows are preserved explicitly, with no further positive row accepted. The targeted tidfault cohorts remain separately flat on both architectures. Same final native tidfault kernel, existing cached desktop/initramfs and 12GiB QEMU guest. V orchestration retains shared-checkout artifacts and reuses the locked module-ISO cache. The first early detacher attempt starts no guest. Temporary VM runtime disks are cleaned by the maintained harness. This evidence does not establish arbitrary application installation, persistent workflows, general physical/page-cache retention, x86 desktop coverage, GNU libc, sandbox/portal or translated/32-bit qualification.'
  kernel_sha256:digest(kernel)
  general_retention_flat:false
  unresolved_growth:growth
  artifacts:pins
 },prettify:true)+'\n'
 if os.exists(out+'tidfault-performance-evidence.json') {assert os.read_file(out+'tidfault-performance-evidence.json')! == publication} else {os.write_file(out+'tidfault-performance-evidence.json',publication)!}
 os.write_file(area+'performance-audit.log','Native tidfault supplementary evidence audit: PASS; general retention: OPEN\n')!; publish(area+'performance-audit.log',out+'tidfault-performance-audit.log')!
 publish(area+'performance-strict-refusal.log',out+'tidfault-performance-retention-refusal.log')!
 println('Native tidfault supplementary evidence audit: PASS; general retention: OPEN')
}
fn publish(input string,output string) ! {bytes := os.read_bytes(input)!; if os.exists(output) {assert os.read_bytes(output)! == bytes} else {os.write_file_array(output,bytes)!}}
