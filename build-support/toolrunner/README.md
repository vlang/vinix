The shared `run-v-tool.sh` launcher keeps compiler output on stderr, including
cache-status text a V build may print on stdout. The tool's stdout remains its
own output on first use, so package manifests and binary data remain usable.

Run `v -cc cc test build-support/toolrunner`. The native compiler fixture
deliberately writes to both streams and installs a native tool. Tests verify
stream routing, literal argument forwarding, the caller's working directory,
tool and compiler exit statuses, and temporary-directory cleanup. ARM and
Rosetta x86 checks passed. No Python is involved.
