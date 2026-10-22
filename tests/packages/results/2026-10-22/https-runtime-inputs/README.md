# Historical HTTPS tool source inputs

The original HTTPS receipts and ledger keep their exact input paths and SHA-256
digests. Fifteen account and package source files later changed independently
of that run.
The adjacent files preserve their original bytes, recovered with literal
`git show 30e7b5661:PATH` arguments and checked against the recorded SHA-256
before writing. Each filename is its content digest.

| Original repository path | SHA-256 |
| --- | --- |
| tools/accounts/accountcore/model.v | 75f35be0164c9ba3092e7f6ffa318df3fe729ff713d74f26c8451012f1fe4d4e |
| tools/accounts/accountcore/parse.v | 0557c9e749c0df427839007665bdc691e5ee3c1b7147d895ba66c25b15ec9a8f |
| tools/accounts/accountcore/store.v | c0e88c92f6a08603077f404a99a25623a9d74b86a73d1d31585b567b6a428b25 |
| tools/accounts/authclient/client.v | 38a02294576d690811ad4761a4301bacdafd870b226a402ed304beeac4b18808 |
| tools/accounts/session.v | 041dc865bfda6744498b36e5d7dc80b7a1ff89cad7c69fa9f273a318647bc8a8 |
| tools/accounts/sessioncore/become.v | 025c67c4332d8f2c093d3daee9eddedf0262c0ed8de71de26b3ba4c0f05e1205 |
| tools/accounts/sessioncore/launch.v | 134fdfa2c4a09e44b3e862ad0aef808cc2153b121921fb846428f67cebc01e40 |
| tools/accounts/sessioncore/manager.v | 1e38c8408432d52e45318a70d69f69b3730be60a5a268ea6c2bd4310309077f5 |
| tools/packages/pkgcore/ffmpeg_profile.v | fbfea09ae469a48545bf1d5fc722236c7c49c6804039830548159a35aaa03978 |
| tools/packages/pkgcore/launch.v | a792edbe3ab4c10c2d89a042094f40b024d3d99bec28fca9212b95050bf0b279 |
| tools/packages/pkgcore/sqlite_profile.v | 2c537a826f7a8dddd68d35b582658c4d838575ffd5a4e9c6855fa8d898a5e68e |
| tools/packages/pkglaunch/client.v | 882c88ee38072a8d883f112ef31e8372c3354286ad1a647fcaf0a06e5501f4e5 |
| tools/packages/pkglaunch/protocol.v | ab9d72cbcd5219c6a5c021ce8e84c58c8518f1976d7a54430c2d06f0cd91ea54 |
| tools/packages/pkglaunch/request_reader.v | 573fc14e35f0bde671bd0254fbcf3d0457067b99af8eed5d18e217fd1f766330 |
| tools/packages/stage.v | 9ff0d406f3ee3306d6c240f66b1347f72d2d245b85681efa5cb34b65e422414f |

The retainer accepts an archived copy only for an original path beneath `tools/`,
with an exact lowercase 64-character digest match. Other inputs and all evidence
must still match their original locations. This preserves historical proof; it
does not qualify the newer tool implementation or make removed build artifacts
available. The separate historical-input controls check exact copies, corruption,
missing files, source scope and invalid digest refusal.
