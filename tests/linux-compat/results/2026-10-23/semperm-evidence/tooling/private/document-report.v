import os

fn main() {
 root := '/Users/alex/code/vinix'
 area := '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'
 path := root + '/docs/linux-posix-qualification.md'
 text := os.read_file(path)!
 assert !text.contains('## Native semaphore permissions')
 report := os.read_file(area + '/report.md')!
 start := report.index('\n2026-10-23.') or { panic('Missing report date') }
 mut addition := '\n## Native semaphore permissions\n' + report[start..]
 addition = addition.replace('`reference/linux-v6.12-sem.c`', '`semperm-evidence/reference/linux-v6.12-sem.c`')
 addition = addition.replace('`reference/linux-v6.12-util.c`', '`semperm-evidence/reference/linux-v6.12-util.c`')
 addition = addition.replace('`manifest.json` hashes', 'The [retained evidence](../tests/linux-compat/results/2026-10-23/semperm-evidence)\nmanifest hashes')
 os.write_file(path, text + addition)!
}
