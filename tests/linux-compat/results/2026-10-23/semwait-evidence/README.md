# Native semaphore wait queue evidence

Qualification: **QUALIFIED**, bounded native ELF64 subset. Baseline `bd9aa1bc1d04eac1ce31e02ce8914969294566ff`; isolated candidate `0e7556c59caac131cdfd2a319673d6e81aa41911`.

The containing repository commit integrates the exact qualified kernel source. Content-addressed objects preserve original bytes; `evidence.json` maps historical paths to local objects. Large boot media and external toolchain inputs remain explicit SHA-256 ledgers. Offline verification checks the copied evidence and ledgers; it does not claim to reconstruct omitted media.

Compile `tests/linux-compat/semwait-evidence.v` with V, without `-prod`, then run `check <this-directory>`. All final gates execute for this QUALIFIED record. The historical `publish-partial` name does not weaken those gates.

## Native and Linux reference runs

- arm-baseline-full-negative: observed FAIL; [receipt](objects/1e728d6662877b831d926c57e38b98f087ad7263b9e9a24a0c2f94613f84bd95), [serial](objects/269ca5692aac718ea1b984ac5d022309fa3a864f9ca93f80443cb4f9bc89f9b2).
- arm-baseline-storage: PASS; [receipt](objects/2478370c460ffb5862c2bc9bdf7a4c69f6d72a48129b8f9f9938cec3224f5686), [serial](objects/774662d5032144c5e55fcf428aad7efa1bd66984381072d187e65ac44eb12036).
- arm-candidate-full: PASS; [receipt](objects/efcbcdecfab1a1e8d7de9f10ce01f7f568d826e44285008d6718a0e88cde9e03), [serial](objects/eed4dbe117509184b90424a7d80ae77ba280f634b84ba194000b2c7d477b6742).
- arm-reference: PASS; [receipt](objects/cf9b4666b55087d68971a934cddd92efabaa49c3630354ab11510e23b5491bfe), [serial](objects/2fe93792550a841a4ee4cd3dcb22880363805235aecb44b0e2139aefe2f594fe).
- x86-baseline-full-negative: observed FAIL; [receipt](objects/d9f9cb74fb2480387672eafdd1d89d366421a59fd997f16286822b8a59acf8bd), [serial](objects/00243e63ba7bdf3f14b4c6710f2879340ab77a832839b44320bd33e5545fc07b).
- x86-baseline-storage: PASS; [receipt](objects/51454bcbb83fa5ee9ac58c0e96164606ca77a4dbfe1fe3a699e70b86dc51d614), [serial](objects/cbf8d29caf8fbc247dc411690abec248f4eae19ba5f108236c5567c750f6c5da).
- x86-candidate-full: PASS; [receipt](objects/e057cd7cfb48b4dd6822689690b2cb5334ecc79cdf88df2a5af87c388eff2258), [serial](objects/d8cdb0a8037c6c972588895967b63a9859d21683f1028d1499afddd2d28204a9).
- x86-reference: PASS; [receipt](objects/d1f3f5ccd3a71393d349005a15502d2598b3c8a33467a5adc6ce4288964c6679), [serial](objects/6e0f5e182aacf126b8870929b6e533e57fcd2a722f6c985d62727900f5076a0e).

## Build, review and performance receipts

- arm-track: [build](objects/518c2a903522a3a96570a5d54762621f81cce18c40aa0e040ae1bdd35e30dff5), [independent generated-C review](objects/ff80c52746faf1078911d66138166cdeb7e3f7f7cbf0bb8e02923de4c986593d).
- arm-prod: [build](objects/ee99b6f4e6753e1ea0ac09d77f7f69d1e2bf21ad307301553c4b63ad0447ef75), [independent generated-C review](objects/7f8c32ad12da132a21ec520c3007f9d794778cf38dfbb5998ea9824f34c05e19).
- arm: [operation/churn/cache/desktop audit](objects/20e4f1c7951e0fc3faac302eedfc039ea73e05cdf5b3463a703f023ffc45d5f0).
- x86-track: [build](objects/b9314ace4f1c31725056370226924acac18529b871d9e7d54560dbfb6050e907), [independent generated-C review](objects/d3e79edca83d051818cd3b284a32d9f779e2bc1a32d2d7881689a88949ca8e95).
- x86-prod: [build](objects/a90b7561740757e90bdaa6fc969dbc953a2ac03fc6e6a8c332c34e21c9ff7a3b), [independent generated-C review](objects/4068921f84aab6988359e7df15f6214cb1f110298759c7e1ecaa397f08ed1a2c).
- x86: [operation/churn/cache/desktop audit](objects/5c7da3d75b62efd0236b3113ce346fa605d1c345f17077962683cb619c2ed499).
- [Allocation inventory comparison](objects/1bb5ff1109e403347638924fb1c28f10ca3d4a8e2dbf0514e72eff83c76f4c53).
- [Actual drag visual review](objects/59487cb8ff39cd3d57ad5c186deddd01af9ed9733ae72104c2e76b7f8251384a).
- [Checker compile](objects/6d6f7d9134799add9d3d911f0fc450f56570d99510d8314f4c8e21fb8fc3e0cf).
- [Checker positive and corruption controls](objects/29ea0dc22b3f919e3f8af40086fd94f1c0821f3bd215e9085a074b8f7a14d6e6).
- [Reference parser controls](objects/66f17f0bac2a7cd125b1ce89ffd1ee8045d29a699fc996b91d693b35e5a3e29b).

The unchanged baseline storage cohorts also pass. This corrects waiter semantics and lifetime handling; it is not evidence of a baseline semaphore storage leak. Static allocation comparison adds no warning groups, while the inherited allowance check still exits 1 on both revisions (178 groups, 401 excess sites). Historical setup failures, rejected checker attempts and the original native semantic failures remain preserved.

SEM_UNDO, permissions, namespace isolation, per-index GETPID, arbitrary fairness, GNU libc and translated/32-bit semaphore paths remain unqualified. See the repository qualification report for the full limits.

Final maintained-source compile, enabled-assertion control, offline evidence audit and exact source integration check all pass; see the [validation manifest](validation/manifest.json) and [offline audit output](validation/integrated-evidence-check.log).

The temporary publication-helper failure and exact-binary recovery are retained in the [publication recovery manifest](validation/publication-recovery.json).
