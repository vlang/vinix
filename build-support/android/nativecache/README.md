# ART cache preparation

The native launcher prepares the standalone ART cache before executing ART,
after any explicit Unix credential change. ART selects `$XDG_CACHE_HOME/art`
when `XDG_CACHE_HOME` is present, otherwise `$HOME/.cache/art`. The launcher
creates the complete ARM64 hierarchy, including missing parents, under the
application's actual credentials and checks read, write and traversal access.
Empty or relative selected homes fail with a launcher error. A present but
empty `XDG_CACHE_HOME` does not fall back to `HOME`.

New directories use mode `0700` subject to the process umask. Existing
directories, including directory symlinks, keep their ownership and modes;
the launcher does not change permissions to make an inaccessible cache work.

This prevents the pinned ART's oat-file assistant from dereferencing a missing
cache filename when a fresh application home lacks its cache parents. Run
`v test build-support/android/nativecache` for fresh and existing cache,
environment selection, malformed paths and permission checks.
