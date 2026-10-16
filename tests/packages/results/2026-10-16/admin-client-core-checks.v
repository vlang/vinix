module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn task(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { print(output); return error(name + ' failed: ' + code.str()) }
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]; v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Result{}
	if phase == 'core' {
		for name, source in {'protocol': 'tools/accounts/authproto/proto_test.v', 'authcore': 'tools/accounts/authcore/authcore_test.v',
			'shipped-actions': 'tools/accounts/authcore/shipped_actions_test.v', 'root-peer': 'tools/accounts/authclient/root_peer_test.v',
			'launch-protocol': 'tools/packages/pkglaunch/protocol_test.v', 'launch-streams': 'tools/packages/pkglaunch/streams_test.v',
			'admin-protocol': 'tools/packages/pkgadmin/protocol_test.v', 'admin-socket': 'tools/packages/pkgadmin/socket_test.v',
			'admin-envelope': 'tools/packages/pkgadmin/ownership_test.v', 'auth-frame': 'tools/accounts/authproto/ownership_test.v',
			'auth-client': 'tools/accounts/authclient/ownership_test.v', 'launch-client': 'tools/packages/pkglaunch/client_ownership_test.v'} {
			extra := if name in ['admin-envelope', 'auth-frame', 'auth-client', 'launch-client'] { ['-d', 'track_heap'] } else { []string{} }
			results << task(name + '-compile', v, [...flags, ...extra, '-o', work + '/' + name, source], work)!
			results << task(name + '-run', work + '/' + name, [], work)!
		}
	} else if phase == 'cli' {
		results << task('package-cli-compile', v, [...flags, '-o', work + '/vinix-package', 'tools/packages/main.v'], work)!
		results << task('distribution-cli-compile', v, [...flags, '-o', work + '/distribution-cli', 'tests/packages/distribution-cli.v'], work)!
		results << task('distribution-cli-run', work + '/distribution-cli', [work + '/vinix-package'], work)!
		results << task('distribution-driver-compile', v, [...flags, '-o', work + '/distribution-check', 'tests/packages/distribution-check.v'], work)!
	} else { panic('phase') }
	os.write_file(work + '/results-' + phase + '.json', json2.encode(results) + '\n')!
}
