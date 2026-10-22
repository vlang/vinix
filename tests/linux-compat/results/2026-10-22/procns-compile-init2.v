import os
import envhelper
import guesthost
import crypto.sha256

fn main() {
	assert os.args.len == 2 && os.args[1] in ['arm', 'x86']
	suffix := os.args[1]
	envhelper.configure()
	state := envhelper.area + '/states/build-init2-' + suffix
	assert !os.exists(state), 'Refusing to reuse ' + state
	os.mkdir_all(state)!
	init := guesthost.compile_init(envhelper.area + '/frozen2/procnsfixture/core.v', state, if suffix == 'arm' { 'aarch64' } else { 'x86_64' }, false)!
	println(init + ' SHA256 ' + sha256.sum(os.read_bytes(init)!).hex())
}
