# Application sandbox launcher

`vinix-sandbox` applies a process policy before executing an application. It
sets and verifies `no_new_privs`, removes effective, permitted, inheritable and
ambient capabilities, clears supplementary groups, closes descriptors above
stderr, locks an `unveil` filesystem view, and installs explicit pledge
execpromises. A privileged caller also empties the capability bounding set.
Any failed setup operation stops the launch with exit status 125.

Build it with the target Linux ABI compiler; it has no library dependencies
other than libc:

```sh
x86_64-linux-musl-gcc -static -O2 -Wall -Wextra -Werror \
  tools/sandbox/vinix-sandbox.c -o vinix-sandbox
```

For example, a static file reader can be launched with:

```sh
vinix-sandbox --uid 1000 --gid 1000 --promises 'stdio rpath' \
  --unveil /home/user/input r -- /usr/bin/reader /home/user/input
```

The command must be an absolute path. The executable is automatically unveiled
for reading and execution. Each further `--unveil /absolute/path rwxc` grants
only the named permissions; an empty permission string hides a subtree.
Dynamic applications need their loader and shared-library paths explicitly
unveiled, and ordinarily need `rpath prot_exec` while their loader starts.
There is no automatic directory-wide grant for `/usr`, `/etc`, or home.

The environment is empty by default. Each `--env NAME=VALUE` adds an explicitly
chosen variable, such as `HOME`, `DISPLAY`, or `LANG`. Arguments and values are
passed directly to `execve`, with no shell evaluation or PATH search.

Root credentials require a paired, nonzero `--uid` and `--gid`. Unprivileged
callers default to their effective identity and also discard saved IDs. They
must already have no supplementary groups or have authority to clear them.
An unprivileged caller cannot change its bounding set, but empty permitted and
inheritable sets plus `no_new_privs` prevent gaining capabilities on exec.
This tool cannot grant capabilities, retain inherited descriptors, or recover
from unavailable pledge/unveil by running the program unrestricted.

The native Calculator applies its own narrower policy after initializing its
model and translations: `stdio` only, a locked empty filesystem view, no
capabilities or new privileges, and anonymous UID/GID 65534 when started as
root. Its compositor protocol channels remain open. That profile is active
when the running kernel identifies itself as Vinix, including its kernel-owned
`-vinix` release suffix in a private UTS namespace. Host UI tests do not invoke
Vinix syscall numbers.

The launcher protects an application process after it starts. It does not
authenticate boot artifacts or supply system-wide MAC, verified block devices,
or Linux security-tooling compatibility. An application-specific promise set
and filesystem grants still require review, including existing standard streams.
