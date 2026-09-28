# Repository Rules

## Feature completion

- Always commit when you implement a feature or fix in this repository; do not
  wait to be asked. Commit each finished change before handing it off.
- Other sessions edit this checkout at the same time. Commit only the files you
  changed (`git commit -- <paths>`), and read each file's `git diff` first so
  no one else's uncommitted edits go in with yours.
- Commits that change Files or Activity Monitor run `.githooks/post-commit`,
  which cross-compiles the app and publishes it to the running QEMU guest (see
  `desktop/README.md`). Name the app in the subject (`Files:`,
  `Activity Monitor:`) so the hook picks it up.
