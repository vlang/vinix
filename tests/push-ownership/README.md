# Push ownership check

V treats `arr << s` the way Go treats `append`: the array gets a copy of the
string's header (pointer and length), and the bytes stay shared. Code built
with `-gc none` or `-manualfree` that frees `s` after pushing it leaves the
array holding freed bytes, and frees them a second time if it frees the array's
elements. The V1 compiler cloned a pushed string, so code written against it
can carry this bug without showing it.

`check.v` lists candidates in three forms:

1. `arr << s` where the same function later frees `s`.
2. A bare name or field pushed onto an array whose elements the function
   frees one by one.
3. A struct literal pushed with a bare name as a field value, which is freed
   later.

Names are matched textually. A hit may name something other than a string, or
a free on a path that returns before the push, so each one has to be read.

```sh
v run tests/push-ownership/check.v kernel tools desktop build-support
```

## Reviewed on 2026-11-20

Found and fixed: generation admission (`6efe4d0c8`), dependency diagnostics,
and the installed namespace check. Each made the audio guest or an existing
pkgcore test crash.

The hits that remain are safe:

| Hit | Why |
| --- | --- |
| `pkgcore/deployment_snapshot.v` `pending << id` | `pending` borrows from `roots`, and its cleanup frees only the array buffer |
| `pkgcore/generation_admission.c.v`, `pkgcore/installed_namespace.c.v` | the free is skipped once the name is queued |
| `desktop/backup_app.v` `relative` | the push path returns before the `defer` that frees it |
| `desktop/wm.v` `children << shortcuts` | appends the elements and then frees only the old outer array |
| `desktop/workflowcore/transfer.v` `job.nodes << children` | the same; `transferred` skips the element frees |
| `android/accountclient/abi.v` `feature` | freed only on the refusal path, which returns |
| `android/accountipc/codec.v`, `android/nativeaccountauth/request.c.v` | byte arrays: `<<` copies the bytes |
