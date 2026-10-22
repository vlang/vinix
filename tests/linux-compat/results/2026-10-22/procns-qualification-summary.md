# Proc namespace qualification

Final fixture accepts EACCES only during concurrent task-exit lookups; stable namespace identity checks remain strict.

arm-before: exit=1, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/final2-before-arm
- kind=0 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=0 cycles=200 big_pages=57/57 written_after_free=0/0 errors=0 PASS
- kind=1 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=1 cycles=200 big_pages=63/63 written_after_free=0/0 errors=0 PASS
- kind=2 classes=18 changed=8 retained_bytes=3401600 bytes_per_operation=17008
  LINUX PROCNS STORAGE: kind=2 cycles=200 big_pages=63/63 written_after_free=0/0 errors=0 FAIL
- kind=3 classes=18 changed=8 retained_bytes=3401600 bytes_per_operation=17008
  LINUX PROCNS STORAGE: kind=3 cycles=200 big_pages=71/71 written_after_free=0/0 errors=0 FAIL

arm-after: exit=0, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/queue-after-arm
- kind=0 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=0 cycles=200 big_pages=57/57 written_after_free=0/0 errors=0 PASS
- kind=1 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=1 cycles=200 big_pages=63/63 written_after_free=0/0 errors=0 PASS
- kind=2 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=2 cycles=200 big_pages=63/63 written_after_free=0/0 errors=0 PASS
- kind=3 classes=18 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=3 cycles=200 big_pages=71/71 written_after_free=0/0 errors=0 PASS

arm-reference: exit=0, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/final2-reference-arm

x86-before: exit=1, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/final3-before-x86
- kind=0 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=0 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 PASS
- kind=1 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=1 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 PASS
- kind=2 classes=14 changed=8 retained_bytes=3401600 bytes_per_operation=17008
  LINUX PROCNS STORAGE: kind=2 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 FAIL
- kind=3 classes=14 changed=8 retained_bytes=3401600 bytes_per_operation=17008
  LINUX PROCNS STORAGE: kind=3 cycles=200 big_pages=165/165 written_after_free=0/0 errors=0 FAIL

x86-after: exit=0, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/queue-after-x86
- kind=0 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=0 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 PASS
- kind=1 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=1 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 PASS
- kind=2 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=2 cycles=200 big_pages=149/149 written_after_free=0/0 errors=0 PASS
- kind=3 classes=14 changed=0 retained_bytes=0 bytes_per_operation=0
  LINUX PROCNS STORAGE: kind=3 cycles=200 big_pages=165/165 written_after_free=0/0 errors=0 PASS

x86-reference: exit=0, state=/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/final2-reference-x86

Source SHA256: edb580692f3fe42e0f690a71b1078df9ffd96e98e40a94c3ef4be6f4646ef921
Manifest SHA256: 577eb2d88250a5ef73e3aed2e4d3bfc9227be611d1ad85406e3a1fe0fa9347db
Candidate manifest SHA256: 37cb67b3f4641c23e49355304942a189fa8cd78e51dd0ff661b8c684b2e29475
Candidate commit: bd9aa1bc1d04eac1ce31e02ce8914969294566ff
Integration commit: d0e230dd7b56bf68ea55d418c142ed45aca08fd6
Baseline provenance: /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/baseline-inputs.json
Original cf642 x86 final3 failed strict big-heap flatness (kind2 201→251 pages); it is preserved and never promoted. Queue attribution measured the retained queue capacity1024→2048 with200-byte elements, exactly50 extra pages; four extended idle snapshots stayed251.
Initial six attempts, second six attempts, third x86 attempts, diagnostic EACCES experiment, and allocation attribution are preserved in qualification-summary.json. complete records receipt availability; the independent strict evidence checker determines qualification.
