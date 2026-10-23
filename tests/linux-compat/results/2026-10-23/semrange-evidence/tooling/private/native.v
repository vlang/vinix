import crypto.sha256
import envhelper
import guesthost
import json2
import os
import time

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn execute(args []string, log string) ! {
 os.write_file(log + '.command.json', json2.encode(args, prettify: true) + '\n')!
 mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
 output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
 os.write_file(log, output)!; os.write_file(log + '.status', code.str() + '\n')!
 if code != 0 { return error('Command failed: ' + log) }
}
fn main() {
 assert os.args.len == 5, 'native arm|x86 PROBE KERNEL_DIR FRESH_STATE'
 suffix := os.args[1]; assert suffix in ['arm', 'x86']
 arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
 probe := os.real_path(os.args[2]); kernel := os.real_path(os.args[3] + '/bin/vinix')
 state := os.args[4]; assert !os.exists(state), 'Fresh state required'
 for path in [probe, kernel] {
  bytes := os.read_bytes(path)!
  assert bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
  assert int(bytes[18]) + (int(bytes[19]) << 8) == if suffix == 'arm' { 183 } else { 62 }
 }
 os.mkdir_all(state + '/kernel/bin')!
 for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(state + '/rootfs/' + name)! }
 os.cp(probe, state + '/rootfs/sbin/init')!; os.chmod(state + '/rootfs/sbin/init', 0o755)!
 os.cp(kernel, state + '/kernel/bin/vinix')!
 mut inputs := {probe: digest(probe), kernel: digest(kernel), @FILE: digest(@FILE), os.executable(): digest(os.executable())}
 runner := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/launch-root'
 for directory in ['build-support', 'build-aarch64-iso/limine', 'build-amd64-iso/limine'] {
  for path in os.walk_ext(runner + '/' + directory, '') { if os.is_file(path) { inputs[path] = digest(path) } }
 }
 envhelper.configure()
 for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE', 'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
 os.setenv('COPYFILE_DISABLE', '1', true); os.setenv('VINIX_QEMU_SMP', '4', true)
 started := time.utc().str()
 execute(['/usr/bin/tar', '--format=ustar', '-cf', state + '/initramfs.tar', '-C', state + '/rootfs', '.'], state + '/image.log')!
 launch := guesthost.launch_from(state + '/rootfs/sbin/init', state + '/initramfs.tar', state, state + '/kernel', arch, true, runner)!
 inputs[launch.command[0]] = digest(launch.command[0])
 os.write_file(state + '/qemu.command.json', json2.encode(launch.command, prettify: true) + '\n')!
 result := guesthost.boot(launch.command, launch.env, state, ['LINUX SEMRANGE: PASS'], ['LINUX SEMRANGE FAIL:', 'LINUX SEMRANGE: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'], 180, true)!
 serial := os.read_file(state + '/serial.log')!
 mut code := result
 for path, pin in inputs { if digest(path) != pin { code = 2 } }
 if code == 0 && (!serial.contains('LINUX SEMRANGE SUMMARY: checks=4200 failures=0') || serial.contains('LINUX SEMRANGE MISMATCH:')) { code = 2 }
 os.write_file(state + '/receipt.json', json2.encode({
  'architecture': json2.Any(arch), 'started': started, 'finished': time.utc().str(),
  'inputs': json2.decode[json2.Any](json2.encode(inputs))!, 'exit_code': code,
  'serial_sha256': digest(state + '/serial.log'), 'iso_sha256': digest(state + '/test.iso'),
 }, prettify: true) + '\n')!
 os.write_file(state + '/status', code.str() + '\n')!
 println('Native semaphore ABI status=' + code.str() + ' ' + arch)
 exit(code)
}
