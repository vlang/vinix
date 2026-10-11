# Host policy fixture generator

Native `host` retains the disposable directory, metadata-preserving copies
of the production policy sources, independent C atomic header, real compiler
launch and original 30-second fixture deadline. `host_generator.v` writes the
independent V modules and assertions in two phases around those copies.

The files in `hosttemplates` preserve the original V literals byte for byte.
Their movement is recorded separately from translated generator logic.
The production policy and fixture assertions remain independent of the generator.

The normal entry point builds a generator with `build-support/run-v-tool.sh`,
installs it with mode `0700` in the original disposable owner, and reuses it for
both phases. The temporary owner removes it on success, failure or interrupt.
`VINIX_BLOCK_POLICY_GENERATOR` can select an already built generator. `V` keeps
its existing meaning for the production fixture compiler and also selects the
generator compiler through `build-support/find-v.sh`.

This host port adds no kernel-build, QEMU or physical-device validation.

`--state-dir /new/directory` retains the actual source copies, hashes, commands,
generator, sanitized executable and logs. Existing directories are refused.
The independent C header now lives in `hosttemplates/host.h`; its original bytes
are checked against the frozen Git source by the native host qualification tool.
