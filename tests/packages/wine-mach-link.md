# Experimental Mach-O captured links

`wine-mach-link.v` qualifies a narrow local link profile independently of the
mandatory Wine host receipts. Build it with the repository's selected V,
`-prod -gc none -manualfree -cflags -fno-lto`, and the repository module path.

```
wine-mach-link build RETAINED_HOST_C_DIRECTORY FRESH_CAPTURE
wine-mach-link check CAPTURE
wine-mach-link-check WINE_MACH_LINK CAPTURE FRESH_CONTROLS
```

The input directory must contain `program.c` and `runtime.c`. These are copied
into the capture before compiling. The current profile selects arm64 macOS,
Clang 23.1.5_1, LLD 23.1.5 and the macOS 27.2 command-line SDK explicitly.
It uses `-fno-lto` and `ld64.lld --reproduce`, validates the bounded ordinary
USTAR format with the existing ELF archive parser, and extracts members without
invoking tar. It admits exactly two thin arm64 object operands, the compiler
runtime archive, SDK text stubs and fixed linker options. The runtime universal
container must have bounded, nonoverlapping ordinary archive slices and exactly
one ordinary arm64 slice. Unknown options,
absolute replay object paths, bitcode objects and other archive input types
are refused. The original response retains the driver's absolute
`-lto_library` option; this LLD documents that option as obsolete and ignored.
The referenced libLTO is **not** represented as a captured input.

Format 2 invokes the selected linker directly with `-t @response.txt`, in the
extracted namespace. Its retained load trace must name captured files only;
absolute paths, path traversal, unparsed output and missing required object or
direct-library observations refuse admission. A `link-loads.json` map binds
each observed path to its archived member hash. Multiple loaded archive members
or TBD documents can refer to the same captured file. Unused archive operands
need not appear in the load trace. Both compilation and replay use closed child
environments and record observed host images. Ordinary non-system tool images are checked
against before-command probes and current bytes. OS shared-cache images remain
UUID metadata only. The check requires byte-identical original/replayed
executables and validates retained evidence hashes, extracted member hashes,
command profiles, environment records and image observations. A copied capture
retains its original recorded command namespace and can be checked there.
Historical format-1 captures require their retained original checker; the new
checker refuses them because they do not contain file-load evidence.

This is a retained local reproduction check. It does not establish complete
SDK reexport/search closure, independence from the installed SDK, a sandboxed
linker, C header closure, or hermetic toolchain admission. The proof file is
an audit receipt, not a signature or a trust anchor. Preserve the complete
external audit bundle and its independent inventory. The existing host
builder continues to use its existing receipt profile; integrating captured
Mach-O links into all mandatory roles and rerunning signed guest acceptance
remains future work.

The production control runner checks real and copied baselines, twenty-one exact
receipt refusals (including resealed output, extraction, argv, environment,
version, image, trace and load-map mutations), five response-profile refusals
and five input header refusals. A resealed archive omission removes an SDK
reexport stub from both the archive and extracted inventory and must fail
because the recorded replay loaded that file. These are file-load observations;
they do not prove absence of unreported reads, search attempts or loader inputs.
All checks remain active under `-prod`.
