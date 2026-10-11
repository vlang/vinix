# Apple provider and test orchestration

`applehost.copy_provider` is the native V API used directly by ANS, SPI and
speaker runners. Whole-definition omission, original ranges, reference checks,
retained-chunk hashes and source bytes retain their existing policy. The three
Python provider APIs and their import adapter have been retired.

`applehost/orchestration.v` owns command parsing, fresh retained state, private
`/tmp` work, interrupt handling, subprocess capture, native module and serial
generation, and the native guest API. Binary fixture output stays byte-exact.
Symbol/source text uses strict UTF-8 with universal-newline conversion; host
environment and literal Unix path bytes are passed directly.

See [runner qualification](runners.md) for checks and current consumer limits.
Provider tests cover omission ranges, malformed definitions, Unicode boundaries,
raw ext2 bytes, read failures and repeated descriptor retirement. They also
check fresh ownership, literal paths, empty path options and signal restoration.
