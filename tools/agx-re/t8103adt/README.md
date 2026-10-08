# Native base-M1 boot-data recovery

`../recover_t8103_adt` is the read-only V CLI for staged base-M1 DeviceTrees or
saved live SGX property lists. It retains schema 2, property-name mapping,
required-input classifications, zero-filled template detection, performance
pairs, driver identity and the independently recovered leakage read. The
staged image unwrap, DeviceTree decoder and Mach-O helpers are native shared
modules; XML syntax uses upstream Expat and compressed DeviceTrees use the
unchanged system compression library.

Public parsed property buffers own their contents. No foreign parser pointer
escapes, and native recovery holds no borrowed bytes after returning. The host
uses V's collector; this tool changes no kernel allocation or lifetime.

The tests retain all 23 independent original fixtures, including their exact
kernel-consumer agreement checks, and add copied-input, scalar plist, staged
finder and argument-parser controls. The XML test capture is the original
independent synthetic SGX fixture, not a machine's private firmware.

```sh
. ../../../build-support/find-v.sh
"$V" -cc cc test .
../recover_t8103_adt --live-sgx sgx.plist
```

Machine-local controls and source-bound receipts are under
`~/.cache/vinix-python-to-v/agx-t8103-20261008/`; the original implementation
and tests remain in Git history. Qualification compares complete JSON, error
categories and diagnostics on ARM64 and actual x86-64, checks sanitizers, and
measures collection after repeated parallel success/error paths. The original
argparse implementation crashes on an empty short-help argument (`-h=`); the
native CLI retains exit 1 and gives a clean explicit-argument diagnostic.
Other explicit help arguments retain their original exit 2.

No physical GPU or firmware execution is claimed by these host checks.
