# Authenticator desktop attachment

The root account broker owns this single-use UI controller. An administrator
explicitly selects the desktop UID/GID, helper executable and window socket;
the authenticator cannot select paths or identities. UID 0 is supported for
the root desktop. This channel is separate from both account RPC and the
headless service lifetime channel.

After an authenticated, one-time interaction redemption, the controller
creates a size-sealed VSF1 memfd and an input pipe, then starts the desktop
helper with only its surface, input writer and lifetime endpoint inherited.
The helper must send exactly byte `0x01` after window creation within five
seconds. The broker continues processing other callbacks while waiting.
Only then does it send the service a 64-byte WSUI frame plus exactly two
SCM_RIGHTS descriptors: the writable surface and input reader. The frame binds
the original session, its private response capability and immutable geometry.
The account launch command follows on the separate account stream. A launch
acknowledgment does not complete the original account request.

Completion, cancellation, client loss, timeout or helper failure closes the
helper lifetime endpoint. The helper closes its input writer, allowing the
service to end its UI while its headless service remains alive. Cleanup reaps
only the helper, with a bounded grace period followed by SIGKILL. A controller
supports one attachment per authenticator process; further attempts fail.

`control_test.v` checks frame binding, real descriptor transfer, closed-stdio
normalization and a forked helper's readiness/EOF/reaping sequence. The memfd
size-seal test runs on Linux. The production `begin()` path, real window
creation and same-VM Activity promotion additionally require guest evidence;
host tests and cross-compilation do not establish Google account login.
