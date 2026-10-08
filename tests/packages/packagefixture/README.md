# Native independent package-store fixture

The existing entrypoint keeps all six unittest IDs and 13 public helper and
lifecycle signatures. V owns fixture setup, archive construction, every test
body and the original assertions. It calls actual unittest assertions and
replaceable `archive`, `upload`, `fetch` and snapshot helpers. Paths, bytes,
HTTP responses, tar readers, subprocesses, exceptions and context managers are
borrowed from the same Python libraries used by the frozen original fixture.

The fixture shares the production borrowed-object ABI and host controller. Each
call retains its objects until callbacks complete and the native process has
been reaped. Context entry registers only after success; explicit exit becomes
inactive before user cleanup and preserves exception identity, suppression and
the passed traceback's identity. A server or temporary directory assigned to
the testcase remains owned by that testcase across native calls. Teardown keeps
the original terminate, five-second wait, stdout close and directory cleanup
order. The original 100 x 10 ms readiness loop and 1.1-second snapshot stability
interval remain intact. Legacy setup-failure cleanup behavior is unchanged.

`VINIX_PACKAGE_FIXTURE_QUERY` selects a prepared matching-ABI fixture query;
`VINIX_PACKAGE_STORE_QUERY` selects the production query. Qualification compares
all six complete frozen fixture bodies with the V bodies using the same server,
staging implementation and immutable fixture inputs. It also checks caller
helper overrides, archive bytes, assertion/effect plans, returned object
identity, context retirement and real loopback HTTP operation. Cold compilation
ownership is qualified separately from the original server readiness deadline.
These are host fixture changes; no kernel, QEMU guest or C migration is claimed.
