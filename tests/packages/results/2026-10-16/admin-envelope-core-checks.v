module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn run(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { return error(name + ': status ' + code.str()) }
	println('PASS ' + name)
	return Result{ name: name, code: code, seconds: f64(time.since(start).milliseconds()) / 1000.0 }
}
fn pair(name string, source string, v string, flags []string, work string) ![]Result {
	return [run(name + '-compile', v, [...flags, '-o', work + '/' + name, source], work)!, run(name + '-run', work + '/' + name, [], work)!]
}
fn check() ! {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	phase := os.args[1]; mut results := []Result{}
	if phase == 'core' {
		for name, source in {'protocol': 'tools/accounts/authproto/proto_test.v', 'authcore': 'tools/accounts/authcore/authcore_test.v',
			'shipped-actions': 'tools/accounts/authcore/shipped_actions_test.v', 'root-peer': 'tools/accounts/authclient/root_peer_test.v',
			'launch-protocol': 'tools/packages/pkglaunch/protocol_test.v', 'launch-streams': 'tools/packages/pkglaunch/streams_test.v',
			'admin-protocol': 'tools/packages/pkgadmin/protocol_test.v', 'admin-socket': 'tools/packages/pkgadmin/socket_test.v'} {
			results << pair(name, source, v, flags, work)!
		}
	} else if phase in ['memory', 'asan'] {
		extra := if phase == 'memory' { ['-d', 'track_heap'] } else { ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		results << pair(phase, 'tools/accounts/authproto/ownership_test.v', v, [...flags, ...extra], work)!
	} else if phase == 'compat' {
		for kind in ['baseline', 'final'] {
			os.cp(work + '/compatibility.v', work + '/' + kind + '/authproto/frame_compatibility_test.v')!
			results << pair('compat-' + kind, work + '/' + kind + '/authproto/frame_compatibility_test.v', v, flags, work)!
		}
		assert os.read_file(work + '/compat-baseline-run.txt')! == os.read_file(work + '/compat-final-run.txt')!
	} else if phase == 'cli' {
		results << run('package-cli-compile', v, [...flags, '-o', work + '/vinix-package', 'tools/packages/main.v'], work)!
		results << run('distribution-cli-compile', v, [...flags, '-o', work + '/distribution-cli', 'tests/packages/distribution-cli.v'], work)!
		results << run('distribution-cli-run', work + '/distribution-cli', [work + '/vinix-package'], work)!
		results << run('distribution-driver-compile', v, [...flags, '-o', work + '/distribution-check', 'tests/packages/distribution-check.v'], work)!
	} else { return error('unknown phase') }
	os.write_file(work + '/results-' + phase + '.json', json2.encode(results) + '\n')!
}
fn main() { check() or { eprintln(err); exit(1) } }
