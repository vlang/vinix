# Public trust-chain regression certificates

These RSA-2048 test certificates are valid from October 22, 2026 to October 17,
2046. They are not production trust anchors. No private keys are retained here.

`root.der` trusts `intermediate.der`, which signs `leaf.der`. `cross.der` has
the root's subject and public key, but is signed by a separate, untrusted CA.
The input chain is leaf, intermediate, cross-signed root. Its valid path ends
at the locally trusted root. `wrong.der` has the root's subject with a different
public key. `corrupt.der` has a modified leaf signature.

The signed network TLS fixture requires validation of that path, reproduces
the unadapted wolfJSSE failure, and checks rejection of negative cases. It also
requires real Internet TLS and certificate/hostname verification separately.

Regenerate public certificates with the V tool (OpenSSL is required):

```
v run tests/native-android-ws/trust-chain-certificates.v \
  build/trust-chain-private tests/native-android-ws/trust-certificates
```

Private keys are generated only under the specified build directory. Review
and update the validity dates here when regenerating.
