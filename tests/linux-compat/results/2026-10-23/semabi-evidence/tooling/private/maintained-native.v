import crypto.sha256
import envhelper
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn digest(path string) string {
    return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn main() {
    assert os.args.len == 2 && os.args[1] in ['arm', 'x86']
    suffix := os.args[1]
    arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
    state := if suffix == 'arm' { previous + '/states/semabi-maintained-integration2-arm' } else { area + '/states/maintained-integration2-x86' }
    kernel := area + '/states/kernel-integration4-' + suffix + '-prod/kernel'
    mut inputs := map[string]string{}
    for path in [@FILE, os.executable(), area + '/maintained-run',
        root + '/tests/linux-compat/run.v', root + '/tests/linux-compat/semabifixture/core.v',
        kernel + '/bin/vinix', previous + '/generate-module'] {
        inputs[path] = digest(path)
    }
    for name in ['guesthost', 'hosttest', 'fixturehost', 'policyhost', 'envhelper', 'frozen/serialcore'] {
        for path in os.walk_ext(previous + '/' + name, '') {
            if os.is_file(path) { inputs[path] = digest(path) }
        }
    }
    envhelper.configure()
    for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE',
        'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
    os.setenv('COPYFILE_DISABLE', '1', true)
    os.setenv('VINIX_QEMU_SMP', '4', true)
    args := [area + '/maintained-run', '--arch', arch, '--kernel-dir', kernel,
        '--state-dir', state, '--cases', 'semabi']
    mut p := os.new_process(args[0])
    p.set_args(args[1..])
    p.set_redirect_stdio_merged()
    p.run()
    output := p.stdout_slurp()
    p.wait()
    code := p.code
    p.close()
    print(output)
    for path, pin in inputs { assert digest(path) == pin, 'Changed input: ' + path }
    os.write_file(state + '/controller-inputs.json', json2.encode(inputs, prettify: true) + '\n')!
    os.write_file(state + '/controller-command.json', json2.encode(args, prettify: true) + '\n')!
    exit(code)
}
