module main
import json2
import os

struct Pin { path string sha256 string }
struct Inputs { compiler string sources []Pin }
struct Check { name string seconds f64 argv []string artifacts []Pin }

fn invoke(controller string, arguments []string) (int, string) {
	mut child := os.new_process(controller); child.set_args(arguments); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	return code, output
}

fn main() {
	work := os.real_path(os.dir(@FILE)); controller := work + '/host-controller'
	os.setenv('V', os.real_path('build/package-release-work/v-toolchain/v'), true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	root := work + '/journal-guards'; assert !os.exists(root); os.mkdir(root)!
	raw := os.read_file(work + '/host-1/inputs.json')!
	inputs := json2.decode[Inputs](raw)!
	mut summary := []string{}
	for mode in ['sources', 'artifact', 'existing']! {
		directory := root + '/' + mode; os.mkdir(directory)!
		if mode == 'sources' {
			mut pins := inputs.sources.clone(); pins[0] = Pin{ path: pins[0].path, sha256: 'invalid' }
			os.write_file(directory + '/inputs.json', json2.encode(Inputs{ compiler: inputs.compiler, sources: pins }))!
		} else if mode == 'artifact' {
			os.write_file(directory + '/inputs.json', raw)!
			check := json2.decode[Check](os.read_file(work + '/host-1/cli.json')!)!
			mut pins := check.artifacts.clone(); pins[0] = Pin{ path: pins[0].path, sha256: 'invalid' }
			os.write_file(directory + '/cli.json', json2.encode(Check{ ...check, artifacts: pins }))!
		}
		arguments := if mode == 'existing' { [directory] } else { ['--resume', directory] }
		code, output := invoke(controller, arguments)
		os.write_file(root + '/' + mode + '.txt', output)!
		assert code != 0 && !output.contains(' PASS')
		assert !os.exists(directory + '/cli-compile.txt') && !os.exists(directory + '/vinix-package')
		assert output.contains(match mode { 'sources' { 'qualification sources or compiler changed' } 'artifact' { 'workspace_pin(pin.path)! == pin' } else { 'qualification work directory must be new' } }), output
		summary << 'CATALOG BUILDER journal guard=' + mode + ' refuses before compilation PASS'
	}
	code, output := invoke(controller, ['--resume', work + '/host-1'])
	assert code == 0 && output == 'CATALOG BUILDER twenty-nine host build/test checks PASS\n'
	os.write_file(root + '/resume.txt', output)!
	summary << 'CATALOG BUILDER intact completed journal resumes with all original timings and artifact pins PASS'
	os.write_file(work + '/journal-check.txt', summary.join('\n') + '\n')!; println(summary.join('\n'))
}
