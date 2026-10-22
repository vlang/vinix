@[has_globals]
import os
import perfconsole
import perfrunner

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn execute(args []string) ! {
 if os.file_name(args[0]) == 'prune-build-artifacts' {
  println('Retaining shared-checkout build artifacts')
  return
 }
 mut p := os.new_process(args[0])
 p.set_args(args[1..])
 p.run()
 p.wait()
 status := p.code
 p.close()
 if status != 0 { return error('Command failed: ' + args.join(' ')) }
}

fn run(label string) !int {
 assert label in ['ops', 'desktop']
 os.setenv('VINIX_KERNEL_DIR', area + '/arm-track/kernel', true)
 os.setenv('V', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', true)
 os.setenv('VINIX_V_COMPILER', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', true)
 os.setenv('VINIX_AARCH64_SYSROOT', '/Users/alex/.cache/vinix-linux-compat/procns-20261016/sdk', true)
 args := ['new=' + root + '/logs/desktop-ram-fix/vinix-desktop-arm64', '--scenarios=' + if label == 'ops' {'ops,churn,cache'} else {'idle,apps,drag'}, '--rounds=1', '--settle=3', '--seconds=5', '--json=' + area + '/perf-' + label + '.json', '--timeout=2400']
 plan := perfrunner.parse(args, root, area + '/frozen-perf', '')!
 work := area + '/perf-' + label
 assert !os.exists(work)
 os.mkdir_all(work)!
 guard := perfconsole.own_commands()
 defer { guard.close() }
 return perfrunner.run_prepared(plan, work, execute)!
}

fn main() {
 if os.args.len != 2 { eprintln('Expected ops or desktop'); exit(2) }
 label := os.args[1]
 status := run(label) or {
  eprintln(err)
  os.write_file(area + '/perf-' + label + '.error', err.msg() + '\n') or { eprintln(err) }
  os.write_file(area + '/perf-' + label + '.status', '2\n') or { eprintln(err) }
  exit(2)
 }
 os.write_file(area + '/perf-' + label + '.status', status.str() + '\n') or { eprintln(err); exit(2) }
 exit(status)
}
