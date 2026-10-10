# Emulator desktop QMP policy

`desktopprep/qmp.v` owns the socket setup, JSON command/reply loop, input-event
construction, coordinate arithmetic, pointer sequencing and close policy used by
the N64, PlayStation and PlayStation 2 desktop runners. The Python `QMP` classes
keep their public methods and pass actual objects through the borrowed Package
Session ABI. JSON codecs, socket calls and supplied arithmetic/callback objects
execute in the caller; inputs are not converted to native approximations.

The native expression stack captures callable targets before operands and drops
consumed handles when the original expression retires. The ordered method state
owns the original parameters and assigned reply through normal returns and saved
errors. Finite literals have implementation-lifetime roots; dynamic inputs are
never memoized. Attribute stores, dictionary displays, truth and raising retain
small Python syntax bindings with zero algorithm credit. Private helper frames
do not promise the original traceback layout or arbitrary recursion budgets.

All code outside the QMP classes keeps its original AST, including guest input
files, screenshots, pixel checks, startup deadlines and process/finally owners.
Event declarations receive zero credit. Conservative algorithm credit is 2,250
bytes across 58 original lines. The previous four Python files total 30,882 bytes;
the replacements total 29,705 bytes, removing 1,177 net Python bytes.

Qualification compares the original/native callbacks, faults, incoming exception
contexts, named and temporary retirement, and actual Unix-socket transcripts.
Actual JSON exchanges cover asynchronous events, errors, malformed input, EOF,
large integers and pointer commands. ARM, Rosetta x86 and ASan/UBSan artifacts
are built separately; repeated calls, saved errors, descriptors, interrupts and
cold private owners are checked. This policy port establishes no new emulator
boot, game, rendering, GPU, kernel or physical-device result.

The committed shared transport reserves closed standard slots only while its
private child pipes are created. Its module-instance reentrant lock protects
spawn windows; callbacks are not serialized. Global POSIX descriptors can still
change inside or overlapping another allocation window, including a nested
constructor proxy. Private artifact owners retire at interpreter exit.
