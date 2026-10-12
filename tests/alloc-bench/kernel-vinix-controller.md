# Native kernel allocation controller

`run-kernel-vinix` invokes `allocationhost` directly in V. It admits genuine
GNU GCC, builds an untimed V init, verifies the extracted boot kernel, records
source/header identity and validates all three sampler phases before retiring
its private VM. Kernel build provenance remains the caller's responsibility.

See [native allocation qualification](../native-allocation-tools/README.md)
for both target artifacts and host ownership checks. The original sampler and
independent allocator fixtures are unchanged. This controller port establishes
no new kernel measurement or guest performance result.
