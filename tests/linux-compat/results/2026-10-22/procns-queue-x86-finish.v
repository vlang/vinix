import json2
import os

fn run(command string, args []string, log string, status string) !int {
 mut child := os.new_process(command)
 child.set_args(args)
 child.set_redirect_stdio_merged()
 child.run()
 output := child.stdout_slurp()
 child.wait()
 code := child.code
 child.close()
 os.write_file(log, output)!
 os.write_file(status, '${code}\n')!
 print(output)
 return code
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 assert os.args.len == 2 && os.args[1] in ['archive', 'audit', 'publish']
 if os.args[1] == 'archive' {
  archive := area + '/qf-x86-tooling.tar.gz'
  assert !os.exists(archive)
  code := run('/usr/bin/tar', ['-czf', archive, '-C', area,
   'qf-x86-tools', 'qf-x86-launch', 'qf-x86-tools-wrapper.v', 'qf-x86-prepare.v',
   'qf-x86-iso.v', 'qf-x86-inputs.v', 'qf-x86-producer.v', 'qf-x86-audit-tail.v',
   'qf-x86-prepare-audit.v', 'qf-x86-audit.v', 'qf-x86-finish.v',
   'qf-x86-curl', 'qf-x86-curl-setup.v', 'qf-x86-preserve-initial.v'],
   area + '/qf-x86-archive.log', area + '/qf-x86-archive.status')!
  exit(code)
 }
 if os.args[1] == 'audit' {
  assert !os.exists(area + '/qf-x86-audit.log') && !os.exists(area + '/qf-x86-audit-status.txt')
  code := run(area + '/qf-x86-audit', [], area + '/qf-x86-audit.log', area + '/qf-x86-audit-status.txt')!
  exit(code)
 }
 audit := os.read_file(area + '/qf-x86-audit.log')!
 assert os.read_file(area + '/qf-x86-audit-status.txt')!.trim_space() == '0'
 assert audit.contains('Two strict negative controls rejected; all receipt/input pins and raw/JSON desktop rows verified.')
 assert os.read_file(area + '/qf-x86-inputs-verify.status')!.trim_space() == '0'
 assert os.read_file(area + '/qf-x86-inputs-verify.log')!.contains('PASS')
 map_path := area + '/queue-desktop-publication-inputs.json'
 mut publication := json2.decode[map[string]string](os.read_file(map_path)!)!
 for suffix, source in {
  'queue-x86-audit.log': area + '/qf-x86-audit.log'
  'queue-x86-audit-status.txt': area + '/qf-x86-audit-status.txt'
  'queue-x86-finish.v': area + '/qf-x86-finish.v'
  'queue-x86-archive.log': area + '/qf-x86-archive.log'
  'queue-x86-archive.status': area + '/qf-x86-archive.status'
 } { assert os.is_file(source); publication[suffix] = source }
 for suffix, source in publication { assert os.is_file(source), suffix + ': ' + source }
 os.write_file(map_path, json2.encode(publication, prettify: true) + '\n')!
 println('x86 queue desktop publication: PASS ${publication.len} verified paths')
}
