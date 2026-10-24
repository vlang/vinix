import os

fn main() {
 const_root := '/Users/alex/code/vinix'
 text := os.read_file(const_root + '/docs/linux-posix-qualification.md')!
 heading := '## Native zombie priority retention'
 start := text.index(heading) or { panic('Missing qualification section') }
 report := text[start..].replace(heading, '# Native zombie priority retention')
  .replace('[Retained zombie-priority evidence](../tests/linux-compat/results/2026-10-24/priozombie-evidence).', 'This directory contains the retained evidence. Run the audit from the repository root.')
 os.write_file('/Users/alex/.cache/vinix-linux-compat/priozombie-20261024/report.md', report)!
}
