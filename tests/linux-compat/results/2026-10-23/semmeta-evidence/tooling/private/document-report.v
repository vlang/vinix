import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'

fn main() {
 report := '# Native semaphore metadata\n\n' +
 '2026-10-23. Bounded native ELF64 musl qualification on AArch64 and x86-64.\n\n' +
 'IPC_STAT now exports the native semid_ds layout, including creator/owner IDs,\n' +
 'key, mode, semaphore count and operation/change timestamps. IPC_SET imports\n' +
 'the complete native structure before lookup and authorization, preserves\n' +
 'immutable fields, masks modes to 0777 and rejects invalid UID/GID mappings.\n' +
 'Creators and current owners retain independent ownership rights. SETVAL,\n' +
 'SETALL and IPC_SET update change time; successful operation vectors update\n' +
 'operation time. Read permission and ownership failures follow Linux ordering.\n\n' +
 '| Execution | AArch64 | x86-64 |\n| --- | --- | --- |\n' +
 '| Original Vinix kernel, unchanged probe ELF | 28,713 checks, 19,480 failures | 28,713 checks, 19,480 failures |\n' +
 '| Candidate Vinix kernel, unchanged probe ELF | 28,713 checks, 0 failures | 28,713 checks, 0 failures |\n' +
 '| Linux 6.12.51, identical probe ELF | 28,713 checks, 0 failures | 28,713 checks, 0 failures |\n' +
 '| Maintained runner on candidate | 28713/256552/4200/457/261/276/175 checks, all pass; four vCPUs | 28713/256552/4200/457/261/276/175 checks, all pass; two vCPUs |\n\n' +
 'The probe validates 104-byte x86-64 and 88-byte AArch64 metadata layouts,\n' +
 'field offsets, copy canaries, reserved fields, timestamp transitions and\n' +
 'ignored input fields. Runtime page sizes select protected buffer boundaries.\n' +
 'Bad pointers, full input import, negative/missing/stale IDs, invalid UID/GID,\n' +
 'unsupported IPC_64 commands and ignored indices check error precedence.\n' +
 'All 512 modes are crossed with seven scenarios: creator, current owner,\n' +
 'creator group, owner group, unrelated user, CAP_IPC_OWNER and CAP_SYS_ADMIN.\n' +
 'Each mode/scenario performs eight checks; 41 additional checks cover metadata.\n' +
 'Both creator and owner can assign arbitrary valid IDs without CAP_CHOWN;\n' +
 'CAP_IPC_OWNER grants read/alter access, while CAP_SYS_ADMIN grants ownership\n' +
 'operations. The permission suite separately covers ordinary vector access.\n\n' +
 'Reference implementations are retained in reference/linux-v6.12-sem.c and\n' +
 'reference/linux-v6.12-util.c, from upstream\n' +
 '[ipc/sem.c](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c) and\n' +
 '[ipc/util.c](https://github.com/torvalds/linux/blob/v6.12/ipc/util.c).\n' +
 'Earlier attempts remain under attempts/: compile/entry-point corrections,\n' +
 'a Linux coarse-clock boundary expectation, an incorrect 4 KiB guard-page\n' +
 'assumption on Vinix AArch64 and concurrent V-run controller executable\n' +
 'replacement. The final controllers use stable executables, the guard uses\n' +
 'getpagesize(), and timestamp checks wait for coarse realtime to advance.\n' +
 'Printed baseline mismatches are capped; the exact failing-check total comes\n' +
 'from the summary, rather than the number of diagnostic lines.\n\n' +
 'The isolated candidate is 09bf0cfff672c584c351642260bfe6a8a9513892, based\n' +
 'directly on d2283facaf4c5db67d48cae8194e3000f2689575. Only the semaphore\n' +
 'source differs; its SHA-256 is\n' +
 '29bed8c38a9de3b927c06b21ef25a956db52c5205b0410c3b5aa012026d2b3c1.\n' +
 'Production build receipts pin sources, dependencies, tools and outputs,\n' +
 'with unchanged before/after input hashes. Generated-C reviews on both\n' +
 'architectures confirm a zeroed stack metadata structure, inline scalar set\n' +
 'fields and no new allocation/free. IPC_SET imports before identity/locking;\n' +
 'IPC_STAT snapshots under lock and copies out after unlock without retaining\n' +
 'a set pointer. Existing destruction, waiter and evaluation helpers match the\n' +
 'baseline. No new object lifetime is introduced.\n\n' +
 'manifest.json hashes artifacts, maps original paths to retained files and\n' +
 'explicitly pins omitted large media/external tools. Duplicate bytes use\n' +
 'relative symlinks. Kernels, generated C, ELFs, serial logs, commands, statuses\n' +
 'and unsuccessful attempts remain inspectable. Audit without -prod:\n\n' +
 '```\nv run tests/linux-compat/semmeta-evidence.v --self-test\n' +
 'v run tests/linux-compat/semmeta-evidence.v check tests/linux-compat/results/2026-10-23/semmeta-evidence\n```\n\n' +
 'The checker validates build/source identity, architecture, exact summaries,\n' +
 'identical probe ELFs on all three kernels and all seven maintained suites.\n' +
 'Its nine negative controls and the reference parser\'s two positive/nine\n' +
 'negative controls pass. completion/receipt.json binds the final audit and\n' +
 'manifest to the current source.\n\n' +
 'IPC namespace isolation, mapped IDs and ancestor capability traversal,\n' +
 'independent filesystem IDs, SEM_UNDO, inventory commands, larger sets/vectors,\n' +
 'GNU libc and foreign/32-bit paths remain unqualified. Section 15\'s broad\n' +
 'libc, installation/sandbox and foreign application gates remain open.\n'
 os.write_file(area + '/report.md', report)!
 qualification := root + '/docs/linux-posix-qualification.md'
 mut text := os.read_file(qualification)!
 assert !text.contains('## Native semaphore metadata')
 text += '\n## Native semaphore metadata\n\n' + report.all_after('\n\n')
  .replace('reference/linux-v6.12-', 'semmeta-evidence/reference/linux-v6.12-')
  .replace('manifest.json hashes artifacts', 'The [retained evidence](../tests/linux-compat/results/2026-10-23/semmeta-evidence)\nmanifest hashes artifacts')
 os.write_file(qualification, text)!
 matrix := root + '/docs/linux-posix-compatibility.md'
 text = os.read_file(matrix)!
 text = text.replace('| Native semaphore permissions |', '| Native semaphore metadata | qualified subset | qualified subset | IPC_STAT/IPC_SET use native layouts, full input import, immutable creator/key/count fields and Linux authorization/error order. Creators and current owners retain independent rights; operations/control writes update timestamps. Identical musl ELFs pass 28,713 checks on both native kernels and Linux 6.12.51; originals fail 19,480 each. Seven maintained semaphore suites pass. [Receipts and limits](linux-posix-qualification.md#native-semaphore-metadata). Namespace/mapping, filesystem IDs, SEM_UNDO, inventory and GNU/foreign/32-bit paths remain unqualified. |\n| Native semaphore permissions |')
  .replace('Independent filesystem IDs, IPC_SET/STAT, namespace isolation/mapping', 'Independent filesystem IDs, namespace isolation/mapping')
 os.write_file(matrix, text)!
 readme := root + '/tests/linux-compat/README.md'
 text = os.read_file(readme)!
 text += '\nThe `semmeta` case adds 28,713 native ELF64 checks for IPC_STAT/IPC_SET,\n' +
 'creator/owner permissions, timestamp transitions and full native structure\n' +
 'copies/error precedence. Both architectures and identical Linux 6.12.51 probe\n' +
 'ELFs pass; originals fail 19,480 checks each. Run\n' +
 '`--cases semmeta,semperm,semrange,semarray,sempid,semword,semabi` with a fresh\n' +
 'state directory. All seven maintained cases pass on both candidate kernels.\n\n' +
 '`semmeta-reference.v` accepts the same arguments as `semabi-reference.v`;\n' +
 '`--self-test` checks two positive and nine negative parser controls. Compile\n' +
 '`semmeta-evidence.v` without `-prod`, run `--self-test`, then `check` on the\n' +
 '[metadata evidence](results/2026-10-23/semmeta-evidence). Generated C confirms\n' +
 'stack snapshots and no new object lifetime. Namespace/mapping, independent\n' +
 'filesystem IDs, SEM_UNDO, inventory and GNU/foreign/32-bit qualifications\n' +
 'remain open; see the retained report for failed attempts and limits.\n'
 os.write_file(readme, text)!
 roadmap := root + '/roadmap.md'
 text = os.read_file(roadmap)!
 anchor := 'Acceptance: published Linux workloads install, run, save, update and integrate'
 assert text.count(anchor) == 1
 text = text.replace(anchor, '- [x] Implement native semaphore IPC_STAT/IPC_SET layouts, creator/owner\n' +
 '  mutation rights and operation/change timestamps with Linux error precedence.\n' +
 '  Qualify 28,713 checks against identical Linux ELFs on both architectures;\n' +
 '  originals fail 19,480 each. Repeat all seven maintained semaphore suites,\n' +
 '  retain unsuccessful attempts and publish explicit remaining IPC/libc limits.\n' +
 '  See [the metadata receipts](docs/linux-posix-qualification.md#native-semaphore-metadata).\n\n' + anchor)
 os.write_file(roadmap, text)!
 publisher := area + '/publish.v'
 text = os.read_file(publisher)!.replace("['semperm-reference.v', 'semmeta-evidence.v'", "['semmeta-reference.v', 'semmeta-evidence.v'")
 os.write_file(publisher, text)!
 println('Metadata documentation and report prepared')
}
