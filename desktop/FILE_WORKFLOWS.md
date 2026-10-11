# Files, search and document workflows

Roadmap section 10 is implemented by Files, the desktop launcher, Preview,
Text Editor, Notes, Grapher and the shared V module `desktop.workflowcore`.

| Workflow | Implementation |
| --- | --- |
| Tabs, selection, batch actions and drag into folders | `files_tabs.v`, `files_operations.v` |
| Undo, conflict choices, retry and interrupted-copy recovery | `files_operations.v`, `workflowcore/transfer.v` |
| Per-volume Trash, restore and cancellable recursive emptying | `files_trash*.v`, `files_volumes.v` |
| Permissions and mounted-volume navigation | `files_info.c.v`, `files_volumes.v` |
| Name, content, folder and metadata search | `files_index.v`, `quick_launch.v`, `workflowcore/search.v` |
| Document previews and thumbnails | `files_quicklook.c.v`, `files_preview_services.v`, `workflowcore/previews.v` |
| Default applications and recent documents | `document_open.v`, the shared session MIME service, `recent_items.v`, `jump_list.v` |
| Atomic saving, recovery and saved versions | `workflowcore/fs.c.v`, `workflowcore/documents.v`, `*_documents.v` |

## Everyday use

Files' toolbar provides tabs, selection mode, Select All, Copy, Cut, Paste,
Trash, Undo, Search, Open and Open With. Selections apply to list, column,
commander and tag views. Drag selected items onto a folder to copy them.
Get Info exposes owner/group/other permission bits and an explicit Apply
action. Volumes lists mounted local, removable and network filesystems;
navigation checks that the selected mount still identifies the same device.

Copy and move run in separate workers. The operation bar shows completed
items and bytes, cancellation, retry, Skip, Keep Both and Replace. A copy is
published only after its private staging tree is complete. Replace retains
the original inode for undo. Undo applies to a whole batch and refuses to
overwrite later edits. Moving back across devices uses another background
transfer.

Checkpoints live in the user's private `.vinix-file-jobs` directory. Opening
Files offers the newest unfinished, unlocked operation for Retry / Resume.
The checkpoint requires the original destination device and unchanged source
identities; it never resumes into a replacement mount. A lease prevents two
windows from resuming the same partial copy. Interrupted partial trees and
replacement backups remain referenced by their checkpoints.

Trash belongs to the source volume. Home uses `.vinix-trash`; other mount
roots use `.vinix-trash-<uid>`. Moving and restoring rename the original inode,
preserving its metadata and symbolic links. Restore refuses occupied names,
missing parents, symlink parents and replaced devices. Emptying is permanent,
requires confirmation of the displayed catalog, and runs in the background.
Cancellation retains the remaining contents. Retry opens Trash for a fresh
review and confirmation. Recursive removal follows anchored descriptors,
rejects nested mounts and never follows symbolic links. The catalog is capped
at 256 items and each removal at 100,000 nodes and 64 directory levels.

## Search

Files' Search panel controls indexing separately for each discovered volume.
Home is enabled initially. Removable and network roots require opt-in, with
an independent Content toggle. Rebuild runs in a cancellable worker. Policy
changes are saved immediately and a finishing worker honors the latest
policy. The open system launcher reloads changed policy/results while it is
visible. Cmd-Space searches applications and documents, including before a
Files window has been opened.

Search terms are combined with AND and are case insensitive. Supported
filters include `type:txt`, `type:folder`, `tag:Work`, `size:1024` (minimum bytes),
and `after:` / `before:` followed by Unix seconds. Tag edits update existing
search results without rebuilding document contents. Every result rechecks
file permissions, identity and the live volume. Cached content from a revoked
permission or disconnected/replaced mount cannot produce a result.

The bounded index holds up to 100,000 files/folders and 64 MiB of extracted
content. Content inputs are capped at 256 KiB per file; large files still have
name and metadata results. Text, common source formats, OOXML, OpenDocument,
EPUB and PDF text are supported. Hidden files, symbolic links and implicit
cross-mount traversal are excluded. Explicitly enabled roots cover mounts.

## Previews and providers

Space opens Quick Look in Files. Preview shares the document provider while
retaining its existing image tools. Office previews display extracted text;
archives display a listing; media displays metadata and an optional video
still. PDF text covers the first eight pages and an optional first-page image.

| Formats | Provider |
| --- | --- |
| PNG, JPEG, GIF, BMP and bounded text | Built in |
| DOCX, XLSX, PPTX, ODT, ODS, ODP, EPUB and ZIP listings | Built-in ZIP/DEFLATE and markup readers |
| PDF text and first-page image | `pdftotext`, optional `pdftoppm` |
| Video and audio metadata; video stills | `ffprobe`, optional `ffmpeg` |
| DOC / RTF, XLS, PPT | `catdoc`, `xls2csv`, `catppt` |
| TAR and compressed TAR | `tar` |
| 7z and RAR listings | `bsdtar` |

External providers must be installed in the guest's executable search path.
Missing providers and malformed files produce visible failure results. A
provider has a 15-second deadline and bounded output. Preview workers also
limit CPU time, output-file size and, on Linux, address space. Closing a
preview terminates its worker/process group. The original document is never
modified or extracted into its source folder.

Private thumbnail entries include path, device, inode, size, timestamps and
permissions in their cache key. Cached surfaces contain both VSF1 buffers,
are scaled to at most 192 pixels per side and are capped at 200 entries.
Visible image thumbnails are generated in a worker; PDF/video thumbnails are
cached after preview. Open With can retain a default choice and opened/saved
documents are recorded in recent items.

## Shared document services

Text Editor, Notes and Grapher use the same private `.vinix-documents` store
for autosave drafts, crash recovery and saved versions. Recovery restores
into the application's document model. Saving checks the opening identity
and refuses an external edit; Save As uses an unused name. Up to 32 saved
versions are retained per canonical document path. Recovery and prior-version
inputs are bounded at 16 MiB; individual applications retain their smaller
document limits.

`Document.save` serializes cooperating saves, retains the previous contents,
and uses `atomic_save` to sync a staged inode before publishing it. Existing
owner and permission bits are preserved. `AtomicWriter` exposes the same
publication boundary for streamed outputs; Preview uses it for PNG exports
and original-image copies. Callers close a writer on every exit path. A failed
write leaves the destination untouched, and a late arrival at a new name is
preserved. Document and file services report device changes and sync failures
instead of silently treating them as success.

## Verification

All implementation, staging, publication and test tooling is V. Tests freeze
committed desktop sources by default, keeping other sessions' unfinished
edits out of the build. Run from the repository root with `V` set to the
production compiler and a working bootstrap V compiler:

```sh
V=/path/to/production/v /path/to/bootstrap/v run desktop/tools/workflow_driver.v check \
  workflow_services workflow_services_memory files_trash files_trash_worker \
  files_trash_memory files_workflows files_index files_tags_search \
  launcher_documents quick_launch files_quicklook files_preview_services \
  preview_app editor_documents document_apps workflow_frames_memory
```

For a real second filesystem, set `VINIX_WORKFLOW_SECOND_VOLUME` to a writable
mount and add `files_cross_volume`. The test creates its own temporary tree,
checks complete moves and background undo across devices, and verifies bytes,
links and permissions. It refuses to qualify two directories on one device.
`VINIX_WORKFLOW_KEEP=1` retains generated C and test artifacts for diagnosis.
`VINIX_WORKFLOW_OVERLAY=1` is an explicit opt-in for uncommitted workflow work;
`VINIX_WORKFLOW_PATCH` can provide an isolated reviewed patch.

Measured tests require zero retained bytes over repeated shared saves, Trash
workflows and workflow-panel frames. Files commits cross-build AArch64 and
publish through the existing running-guest application store.

Automated host tests cover cancellation/resume, conflict choices, original
preservation, replaced-device guards, metadata restoration, permission-aware
search, tag updates, bounded office/ZIP decoding, valid thumbnail surfaces and
document recovery/version conflicts. Physical removable-media removal,
network-server disconnects and external PDF/media/legacy-office providers
still require guest qualification with those devices and providers installed.
