import os
import time

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 assert os.args.len == 2 && os.args[1] in ['ops', 'drag']
 name := if os.args[1] == 'ops' { 'qxo' } else { 'qxd' }
 path := area + '/qf-x86-' + name
 assert !os.exists(path + '.log') && !os.exists(path + '.status')
 mut process := os.new_process(area + '/qf-x86-run')
 process.set_args([os.args[1]])
 process.set_redirect_stdio_merged()
 mut log := os.create(path + '.log')!
 process.run()
 for process.is_alive() {
  chunk := process.stdout_read()
  if chunk != '' { log.write_string(chunk)!; log.flush() } else { time.sleep(50 * time.millisecond) }
 }
 remainder := process.stdout_slurp()
 log.write_string(remainder)!
 log.close()
 process.wait()
 status := process.code
 process.close()
 os.write_file(path + '.status', '${status}\n')!
 println(name + ' host producer exit ' + status.str())
 exit(status)
}
