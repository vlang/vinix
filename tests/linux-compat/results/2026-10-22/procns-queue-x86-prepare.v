import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
 target := area + '/qf-x86-tools'
 assert !os.exists(target)
 os.cp_all(area + '/ds/sources', target, false)!
 os.cp(area + '/qf-frozen-perf-drag/perfrunner/drive.v', target + '/perfrunner/drive.v')!
 os.cp(area + '/qf-frozen-perf-compat/perf-init.sh', target + '/perf-init.sh')!
 builder := area + '/qf-x86-launch'
 os.mkdir_all(builder + '/build-support')!
 config := os.read_file(area + '/desktop-x86-launch/build-support/limine.conf')!
 os.write_file(builder + '/build-support/limine.conf', config + '    cmdline: vinix.disk=auto\n')!
 source := os.read_file(area + '/desktop-iso.v')!.replace('/desktop-x86-launch/', '/qf-x86-launch/')
 os.write_file(area + '/qf-x86-iso.v', source)!
 println('Prepared frozen private x86 Q tools and raw-tar ISO config')
}
