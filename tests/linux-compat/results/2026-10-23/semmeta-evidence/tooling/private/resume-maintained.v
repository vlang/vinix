import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
const root = '/Users/alex/code/vinix'

fn replace_file(path string, old string, new string) ! {
 text := os.read_file(path)!
 assert text.contains(old), path
 os.write_file(path, text.replace(old, new))!
}

fn main() {
 for suffix in ['arm', 'x86'] {
  stem := area + '/states/maintained-second-' + suffix
  assert !os.exists(stem + '.status') && !os.exists(stem + '.log')
  os.write_file(stem + '.recovery.json', json2.encode({
   'outcome': 'interrupted; no controller exit status or output was recorded',
   'partial_state': '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/sm2-' + suffix,
   'retry': 'maintained-third-' + suffix,
  }, prettify: true) + '\n')!
 }
 replace_file(area + '/maintained-native.v', "'/states/sm2-'", "'/states/sm3-'")!
 replace_file(area + '/publish.v', "'/states/sm2-'", "'/states/sm3-'")!
 replace_file(area + '/publish.v', "  directory(previous + '/states/sm1-' + suffix, 'attempts/maintained-first-' + suffix, mut manifest)!", "  directory(previous + '/states/sm1-' + suffix, 'attempts/maintained-first-' + suffix, mut manifest)!\n  directory(previous + '/states/sm2-' + suffix, 'attempts/maintained-second-' + suffix, mut manifest)!")!
 replace_file(root + '/tests/linux-compat/semmeta-evidence.v', "'maintained-second-'", "'maintained-third-'")!
 for path in [area + '/report.md', area + '/document-report.v', root + '/docs/linux-posix-qualification.md'] {
  replace_file(path, '| Maintained runner on candidate, four vCPUs | 28713/256552/4200/457/261/276/175 checks, all pass | 28713/256552/4200/457/261/276/175 checks, all pass |', '| Maintained runner on candidate | 28713/256552/4200/457/261/276/175 checks, all pass; four vCPUs | 28713/256552/4200/457/261/276/175 checks, all pass; two vCPUs |')!
 }
 for path in [area + '/report.md', root + '/docs/linux-posix-qualification.md'] {
  replace_file(path, 'replacement. The final controllers use stable executables, the guard uses', 'replacement. A later maintained run was interrupted without controller status;\nits partial results are retained and a fresh full run supplies final results.\nThe final controllers use stable executables, the guard uses')!
 }
 replace_file(area + '/publish.v', "'publish.v', 'setup.v', 'document-report.v'", "'publish.v', 'setup.v', 'document-report.v', 'resume-maintained.v'")!
 println('Preserved interrupted attempts and prepared fresh maintained runs')
}
