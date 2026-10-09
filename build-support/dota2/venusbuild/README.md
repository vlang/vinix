# Native Venus builder

`venus_query.v` owns the translated Dota Venus build sequence, source
archive checks, patch preparation, Meson cross-file output and cached
artifact publication. `venus-build.py` retains constants, the original
parser and public signatures. Its generic bridge borrows actual Python
paths, import specifications, modules and subprocess objects.

The native policy calls the original Lavapipe API on the same retained
module. Source and sysroot managers stay owned by that API; Venus adds no
new context-manager or worker ownership. Preserve import publication
before executing module code, command ordering and the library/ICD tuple.

The generation keeps the original fields and adds a separate native source
closure, including the maintained Mesa/Venus implementations and binding
symlinks. Upstream Mesa sources, pins, patches and build options stay intact.
