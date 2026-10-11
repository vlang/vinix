# Mapping metadata storage admission

Run the production V storage and resource-budget helpers against real V arrays:

```sh
TMPDIR=/path/to/scratch VTMP=/path/to/scratch build-support/run-v-tool.sh tests/mmap-budget/run.v
```

The controller stages production `vmstorage`, `kbudget` and `cgcontrol` code
with host lock, page-size and process-admission bindings. It uses V throughout
and removes its temporary state. `V` can select the compiler.

The storage helper adds a 128-byte envelope for headers and alignment. Up to
the general heap's 2048-byte slab limit, it rounds to a covering power of two.
Larger requests reserve rounded native data pages plus the heap's metadata
page. Both 4 KiB and 16 KiB boundaries and overflow refusals are tested.

Array growth reserves the new buffer while the old buffer remains charged.
Only after V's existing `.noslices` growth frees the previous buffer does its
reservation retire. Tests exhaust a real owner allowance, verify a refused
growth leaves pointers, capacity, contents and charges intact, then release
pressure and retry. They also check capacity reuse and growth after the
creator's owner handle closes; retained storage keeps that account alive.

The helper applies to owned, unsliced metadata arrays whose callers serialize
mutation and already charge their current capacity. It follows the pinned V
runtime's doubling rule. Native integration and repeated split/fork/unmap
checks live in the Linux compatibility `mapstorage` case. These checks do not
certify every heap allocation or replace physical heap leak measurements.
