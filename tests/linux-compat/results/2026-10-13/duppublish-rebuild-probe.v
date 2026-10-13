import crypto.sha256
import guesthost
import json2
import os
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn capture(executable string, args []string) string {
	mut p := os.new_process(executable); p.set_args(args); p.set_redirect_stdio_merged(); p.run(); output := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 0, output; return output.trim_space()
}
fn main() {
	root := '/Users/alex/code/vinix'; area := '/Users/alex/.cache/vinix-linux-compat/duppublish-20261013'
	selected := capture('sh', ['-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root])
	before := digest(selected); version := capture(selected, ['version']); os.setenv('V', selected, true)
	mut artifacts := {'compiler_path': selected, 'compiler': before, 'version': version, 'generator': digest(root + '/tests/linuxkpi/generate_module.v'), 'generator_core': digest(root + '/tests/native-generators/generators/core.v'), 'build': digest(root + '/tests/native-guest-tools/guesthost/build.v')}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		state := area + '/qualified-probe-rebuild-' + suffix; assert !os.exists(state); os.mkdir_all(state)!
		init := guesthost.compile_init(root + '/tests/linux-compat/duppublishfixture/core.v', state, arch, false)!
		c_matches := digest(state + '/fixture.c') == digest(area + '/qualified-after-' + suffix + '/duppublish/fixture.c'); assert c_matches, 'probe C reconstruction mismatch'
		elf_matches := digest(init) == digest(area + '/qualified-after-' + suffix + '/duppublish/init'); assert elf_matches, 'probe ELF reconstruction mismatch'
		os.cp(state + '/fixture.c', area + '/pinned-preview-' + suffix + '.c')!
		artifacts[arch + '_c'] = digest(state + '/fixture.c'); artifacts[arch + '_elf'] = digest(init)
		println(arch + ': selected probe compiler reconstructs exact tested C and ELF: PASS')
	}
	assert digest(selected) == before
	os.write_file(area + '/probe-compiler.json', json2.encode(artifacts, prettify: true) + '\n')!
}
