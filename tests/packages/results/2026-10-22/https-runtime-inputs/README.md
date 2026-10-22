# Historical HTTPS account source inputs

The original HTTPS receipts and ledger keep their exact input paths and SHA-256
digests. Seven account source files later changed independently of that run.
The adjacent files preserve their original bytes, recovered with literal
`git show 30e7b5661:PATH` arguments and checked against the recorded SHA-256
before writing. Each filename is its content digest.

| Original repository path | SHA-256 |
| --- | --- |
| tools/accounts/accountcore/model.v | 75f35be0164c9ba3092e7f6ffa318df3fe729ff713d74f26c8451012f1fe4d4e |
| tools/accounts/accountcore/parse.v | 0557c9e749c0df427839007665bdc691e5ee3c1b7147d895ba66c25b15ec9a8f |
| tools/accounts/accountcore/store.v | c0e88c92f6a08603077f404a99a25623a9d74b86a73d1d31585b567b6a428b25 |
| tools/accounts/session.v | 041dc865bfda6744498b36e5d7dc80b7a1ff89cad7c69fa9f273a318647bc8a8 |
| tools/accounts/sessioncore/become.v | 025c67c4332d8f2c093d3daee9eddedf0262c0ed8de71de26b3ba4c0f05e1205 |
| tools/accounts/sessioncore/launch.v | 134fdfa2c4a09e44b3e862ad0aef808cc2153b121921fb846428f67cebc01e40 |
| tools/accounts/sessioncore/manager.v | 1e38c8408432d52e45318a70d69f69b3730be60a5a268ea6c2bd4310309077f5 |

The retainer accepts an archived copy only for an original account-source path,
with an exact lowercase 64-character digest match. Other inputs and all evidence
must still match their original locations. This preserves historical proof; it
does not qualify the newer account implementation or make removed build artifacts
available. The separate historical-input controls check exact copies, corruption,
missing files, source scope and invalid digest refusal.
