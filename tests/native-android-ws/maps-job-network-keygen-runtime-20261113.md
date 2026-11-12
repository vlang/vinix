# Job network query and key authentication request metadata

Based on 02e3dd2da. Two retained runtime failures identified missing APIs:

- r72's GMS broker logs an uncaught missing
  KeyGenParameterSpec.Builder.setUserAuthenticationValidityDurationSeconds
  from TapAndPayInitIntentOperation before its System.exit(10). Maps also
  records an account-query timeout. The missing setter is a concrete GMS
  failure; the logs do not establish that it caused every account timeout.
- r74's Maps main looper exits on missing JobParameters.getNetwork from
  WorkManager's SystemJobService.onStartJob. Its log records repeated genuine
  HTTPS validation successes before that exit. Explore rendered, with a blank
  map. A Louvre query was typed after confirming search focus, but no result
  appeared before exit. Search, tiles and routes are not qualified by r74.

The key-generation request builder now retains the duration, defaults to -1,
accepts -1 through Integer.MAX_VALUE, rejects smaller values before mutation,
and copies the value into each built specification. The fluent setter returns
the same builder. This adds request metadata, not key generation or successful
authentication. The contract follows
[AOSP KeyGenParameterSpec](https://android.googlesource.com/platform/frameworks/base/+/cb3bb3f/keystore/java/android/security/keystore/KeyGenParameterSpec.java).

JobParameters now exposes getNetwork. The current latency-only dispatcher has
no job-specific network assignment, so this returns null. It does not substitute
the device's default route or claim network constraints were satisfied. Network
constraint dispatch/binding remains unimplemented. Android documents the
[nullable job network query](https://developer.android.com/reference/android/app/job/JobParameters).
The regression checks it inside an actual scheduled, unconstrained callback,
alongside the existing ID, extras and deadline checks.

Evidence remains under `/Users/alex/.local/state/vinix/android/`. Available
V 0.5.2 6f888d6 built the SDK producer in separate C-emission/compilation steps.
maps-api-retry-inputs-20261113-r1 retains copied source, the selected Unix
signal-handler header and C dependency list; generated C and command receipts are
external. The final runs explicitly retain RSS 629145600, wall 300000 ms,
reserve 1073741824, growth 536870912 and output 4194304. All exit 0/0 with cleanup:

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| maps-api-retry-builder-emit-20261113-r1 | 2665 | 430505984 | 131072 |
| maps-api-retry-builder-cc-20261113-r1 | 473 | 137101312 | 3653632 |
| maps-api-retry-fixture-tool-20261113-r1 | 1884 | 374898688 | 12214272 |
| framework-job-network-keygen-20261113-r1 | 2619 | 483639296 | 40587264 |
| current-api-job-network-keygen-20261113-r1 | 919 | 168148992 | 868352 |
| maps-current-20261113-r75 staging | 8264 | 37453824 | 151748608 |

SDK jar SHA256 ea2c13481b0e611d41004796d91f5cf3a18234e3879e1aad29379dd1568e9aea;
signed APK 129beab25077f1eac4ab6b1833462143d77c854863ced9d72c05050467d7bba4.
Fresh r75 retains the non-JIT native r4, expiry-fixed protocol/launcher,
memory controller r4, core/TLS jars, 12 GiB/4 CPUs and 8 GiB app disk.
Volume identity 2318452ef6b5410bbbf402b12368abcc, inspection, read-only e2fsck
and initial hash passed before launch.

The signed ARM regression passed as UID/GID 10160, ready/pass once, drained EOF,
exit 0. Its reconstructed child log includes KEYGEN-AUTH-VALIDITY-PASS,
JOB-NETWORK-PASS, NETWORK-VALIDATION-PASS and the existing GL/API markers.
The key tests check default -1, -1/0/60/maximum, fluent identity, immutable built
snapshots, rejection of -2/minimum without mutation, and preservation of the
separate authentication-required flag. No key-generation success is asserted.

Snapshot job-network-keygen-api-uart-20261113-r1 full SHA256:
4c47903a6a5d9daef02194b987422a34fdfa93d4362c37e03c6db67c45687151;
receipt 03df6e68a9d40b803f5c914d769a71cca4651aa928ef2dd97880414d0b398024.
Readback reconstructs the unchanged two-entry export with zero removals:
archive 191db2bebc089c462dc9b57647fb6663366b95e29439a4c9e42d8a532e4befb2;
child 4ee73ffbc7ba0053e8222c69c123d90ba310df59c0ce1a32923f017afe9e7d24.
r75's actual Maps run reached Explore, real Louvre results (4.7 stars,
382551 reviews), details and photos, then an Eiffel Tower-to-Louvre route with
a 9-minute driving estimate. The route preview displayed a turn instruction
(Head toward Pont d'Iéna). Tiles and route geometry remained blank. The retained
Maps and GMS logs contain no main-looper/uncaught failure, NoSuchMethodError,
auth-pump failure or service-exit marker. Google sign-in was not attempted.
These observations establish progress past r74's job API failure, not full Maps.

The complete 600134 ms watch retained at least 4753648 KiB free memory and
7240785920 bytes free app storage. After sync returned a guest prompt, owned
QEMU PID 82022 was stopped and verified absent before read-only extraction.
The broker receipt was still ready, awaiting account interaction; no clean
application exit or authentication is claimed. maps-current-20261113-r75 retains
screenshots, logs, receipt, complete UART, raw image and retained.sha256.
Final image SHA256 c42cbfb94467c2c7ddde289eed861a2c40a3814c83e6c3e04f407b93774fd0a5;
Maps log 582027ce3ca800000be09081c5765d2205c0840c606849dc6e69f4441896e4d6;
broker log 53d82179404583d2c78498b4b38c325ae4430ff199c7fcc7276d3aa30f1a3173;
receipt 82b453bc1d1f0dfd4decb5ccbb7436df067712d4abc45543e7a9a17cb49a2667;
UART 8fb8b8955df57b579879c3ab94ea33a31e20c5ff2b5adeb793d3eff1b3a66730.
