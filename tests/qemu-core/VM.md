The native `run-vm` entry point owns argument parsing, launch arguments and
environments, exact feature and failure markers, PTY reads, shutdown deadlines,
child retirement and the persistence reboot sequence in `corevm` V code. It
executes guest commands directly; its Python frontend and child bridge are
retired. The amd64 command is resolved through the caller's PATH and inherits
its environment. ARM keeps its explicit environment overrides.

All argument and environment strings remain owned through fork and exec. The
leader remains unreaped until its process group is retired, reserving its PID.
The supervising loop stops accessing the master before cleanup; after group
termination it closes the master before reaping, so Darwin slave teardown
cannot wait on an open master. SIGINT and SIGTERM abort the loop; retirement
ignores further interruptions and restores previous handlers afterward. CLI
deadlines must be positive integers before launch. A resistant child escalates
to SIGKILL after the original ARM five-second and two-second grace periods;
amd64 termination is also bounded by a two-second escalation.

Fresh native command qualification is described in
[native-vm-tools.md](native-vm-tools.md). The remaining paragraphs record the
earlier bridge qualification; they are historical evidence, not fresh boots
for this native entry-point migration.

Qualification compares 8,644 frozen-original result policies per ARM, Rosetta
x86 and ARM ASan profile, seventeen actual PTY flows, thirteen CLI/path cases,
and twenty-two environment, stdout, timeout and interruption cases. Native
units exercise one hundred fork/argv/environment/master lifetimes against an
exact descriptor baseline. The original five-second unit deadline remains;
one ASan attempt missed startup under parallel compilation and passed when
rerun unchanged in isolation. Cold installation and missing-compiler failure
retire their private directories on both caller architectures. The shared
controller also passes all 9,105 existing AGX policy comparisons per profile.

Actual ARM QEMU runs with the frozen and native controllers pass all feature
markers and persistence verification across reboot using identical retained
init and initramfs inputs. Both controllers also pass the amd64 guest with the
same ISO, existing kernel and firmware. Two earlier native amd64 attempts hit
the untouched first-touch free-memory assertion; those attempts are retained
in the evidence. These boots use explicitly hashed existing kernels and newly
compiled independent fixtures, and are not fresh kernel-build evidence. No
fixture assertion or production timeout was changed.
