#!/bin/bash
# Build the amd64 and arm64 Vinix ISOs, boot-test them, and publish them as a
# GitHub release.
#
# Usage: ./scripts/deploy-iso.sh [options]
#
#   --tag=TAG          release tag (default: first unused iso-YYYY-MM-DD, then -2, -3, ...)
#   --ref=REF          commit to release (default: HEAD); it must be pushed
#   --arch=LIST        amd64, arm64, or amd64,arm64 (default)
#   --draft            create the release as a draft
#   --prerelease       mark the release as a pre-release
#   --no-test          do not boot-test the images first
#   --no-publish       build (and test) only
#   --prepare-only    build and save a handoff for later publication
#   --verify-prepared=TAG  check a saved handoff and report its asset digests
#   --publish-prepared=TAG  verify and publish a saved handoff
#   --prepared-review=FILE  require the exact reviewed JSON for --publish-prepared
#   --resume-draft=ID  continue an upload or confirm publication by release ID
#   --resume-create=TAG  recover a draft whose creation response was lost
#   --package-review=DIR  require a reviewed package plan (amd64.json or arm64.json) for each target
#   --yes              publish without asking
#   --repo=OWNER/NAME  GitHub.com repository (default: the repository gh discovers)
#
# The images are built from a clean checkout of REF in build-release/work/src,
# so uncommitted changes in this tree never end up in a release. What is not
# source -- the Alpine package layers the arm64 desktop is assembled from,
# ui2, the V compiler -- comes from this checkout and the environment, as for
# the regular build scripts; set V to pick a compiler.
# Only one release may use a checkout's build-release workspace at a time.
# VINIX_IOS_RELEASE_RUNTIME may retain a previously published optional runtime.
# Set VINIX_IOS_RELEASE_RUNTIME_SHA256 and VINIX_IOS_RELEASE_RUNTIME_ORIGIN too;
# its static ARM64 ELF and checksum are verified and its origin is recorded.
#
# Outputs, in build-release/TAG:
#
#   vinix-amd64.iso   boots through BIOS or UEFI, from a CD or a disk
#   vinix-arm64.iso   boots through UEFI
#   SHA256SUMS
#   vinix-packages-ARCH.json  verified package selection (when inputs are selected)
#   vinix-x11-ARCH.tar.gz(.sha256)  the X11 that pkg installs with the first
#                     graphical application; the images leave it out
#   vinix-ios-runtime-arm64(.sha256)  the static iOS runtime the first-run app
#                     page installs on arm64 (desktop/app_selection_runtime.v)
#   RELEASE_NOTES.md  what the release page says
#   test/             serial logs and screenshots from scripts/test-iso.sh
#
# The asset names do not change between releases, so
# https://github.com/OWNER/NAME/releases/latest/download/vinix-arm64.iso always
# names the newest image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG=''
REF=HEAD
ARCHES=amd64,arm64
DRAFT=0
PRERELEASE=0
RUN_TESTS=1
PUBLISH=1
PREPARE_ONLY=0
VERIFY_PREPARED=''
PUBLISH_PREPARED=''
PREPARED_REVIEW=''
ASSUME_YES=0
REPO=''
PACKAGE_REVIEW=''
RESUME_DRAFT=''
RESUME_CREATE=''
BUILD_OPTIONS=0

usage() {
    sed -n '2,/^set -/s/^# \{0,1\}//p' "$0" | sed '$d'
}

for arg in "$@"; do
    case "$arg" in
        --tag=*) TAG="${arg#*=}"; BUILD_OPTIONS=1 ;;
        --ref=*) REF="${arg#*=}"; BUILD_OPTIONS=1 ;;
        --arch=*) ARCHES="${arg#*=}"; BUILD_OPTIONS=1 ;;
        --draft) DRAFT=1 ;;
        --prerelease) PRERELEASE=1; BUILD_OPTIONS=1 ;;
        --no-test) RUN_TESTS=0; BUILD_OPTIONS=1 ;;
        --no-publish) PUBLISH=0; BUILD_OPTIONS=1 ;;
        --prepare-only) PREPARE_ONLY=1; PUBLISH=0; BUILD_OPTIONS=1 ;;
        --verify-prepared=*)
            VERIFY_PREPARED="${arg#*=}"
            [ -n "$VERIFY_PREPARED" ] || { echo "ERROR: --verify-prepared requires a tag" >&2; exit 1; }
            ;;
        --publish-prepared=*)
            PUBLISH_PREPARED="${arg#*=}"
            [ -n "$PUBLISH_PREPARED" ] || { echo "ERROR: --publish-prepared requires a tag" >&2; exit 1; }
            ;;
        --prepared-review=*)
            PREPARED_REVIEW="${arg#*=}"
            [ -n "$PREPARED_REVIEW" ] || { echo "ERROR: --prepared-review requires a file" >&2; exit 1; }
            ;;
        --resume-draft=*)
            RESUME_DRAFT="${arg#*=}"
            case "$RESUME_DRAFT" in
                ''|0*|*[!0-9]*) echo "ERROR: --resume-draft requires a numeric draft ID" >&2; exit 1 ;;
            esac
            ;;
        --resume-create=*)
            RESUME_CREATE="${arg#*=}"
            [ -n "$RESUME_CREATE" ] || { echo "ERROR: --resume-create requires a tag" >&2; exit 1; }
            ;;
        --package-review=*)
            BUILD_OPTIONS=1
            PACKAGE_REVIEW="${arg#*=}"
            if [ ! -d "$PACKAGE_REVIEW" ]; then
                echo "ERROR: --package-review requires an existing directory" >&2
                exit 1
            fi
            PACKAGE_REVIEW="$(CDPATH= cd -- "$PACKAGE_REVIEW" && pwd)"
            ;;
        --yes|-y) ASSUME_YES=1 ;;
        --repo=*) REPO="${arg#*=}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $arg" >&2; exit 1 ;;
    esac
done

BUILD_AMD64=0
BUILD_ARM64=0
IFS=, read -r -a arch_list <<< "$ARCHES"
for arch in "${arch_list[@]}"; do
    case "$arch" in
        amd64|x86_64) BUILD_AMD64=1 ;;
        arm64|aarch64) BUILD_ARM64=1 ;;
        *) echo "ERROR: unknown architecture: $arch" >&2; exit 1 ;;
    esac
done

step() {
    echo
    echo "==> $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need() {
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
    done
}

human_size() {
    "$SCRIPT_DIR/build-support/human-size" "$1"
}

file_size() {
    wc -c < "$1" | tr -d ' '
}

# ── What to build ──────────────────────────────────────────────────────────

need git cc
if [ -n "$PREPARED_REVIEW" ]; then
    [ -n "$PUBLISH_PREPARED" ] || die "--prepared-review requires --publish-prepared"
    case "$PREPARED_REVIEW" in
        /*) ;;
        *) PREPARED_REVIEW="$PWD/$PREPARED_REVIEW" ;;
    esac
fi
cd "$SCRIPT_DIR"
post_build=0
for action in "$RESUME_DRAFT" "$RESUME_CREATE" "$VERIFY_PREPARED" "$PUBLISH_PREPARED"; do
    if [ -n "$action" ]; then
        [ "$post_build" -eq 0 ] || die "choose one verification, publication or recovery action"
        post_build=1
    fi
done
if [ "$post_build" -eq 1 ]; then
    [ "$BUILD_OPTIONS" -eq 0 ] || die "build options cannot be used with verification, publication or recovery"
else
    need curl clang ld.lld xorriso rsync mformat mmd mcopy
    COMMIT="$(git rev-parse --verify "$REF^{commit}")" || die "no such commit: $REF"
    SHORT="$(git rev-parse --short=10 "$COMMIT")"
    if [ "$REF" = HEAD ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "NOTE: this checkout has uncommitted changes; the release is built from $SHORT without them."
    fi
fi

WORK="$SCRIPT_DIR/build-release/work"
CACHE="$SCRIPT_DIR/build-release/cache"
SRC="$WORK/src"
mkdir -p "$WORK"
. "$SCRIPT_DIR/build-support/find-v.sh"
ASSET_WORK="$(mktemp -d "$WORK/release-assets.XXXXXX")"
ASSET_STAGE="$ASSET_WORK/upload"
trap 'rm -rf "$ASSET_WORK"' EXIT
"$V" -backend c -prod -cc cc -o "$ASSET_WORK/release-lock" \
    "$SCRIPT_DIR/build-support/isoboot/release-lock.v"
exec 9<"$WORK"
"$ASSET_WORK/release-lock" lock
cleanup_release() {
    # Release the lock even if a child inherited the workspace descriptor.
    "$ASSET_WORK/release-lock" unlock || true
    rm -rf "$ASSET_WORK"
}
trap cleanup_release EXIT

build_release_assets() {
    "$V" -backend c -prod -cc cc \
        -path "@vlib|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/tools/accounts" \
        -o "$ASSET_WORK/release-assets" "$SCRIPT_DIR/build-support/isoboot/release-assets.v"
}

if [ -n "$VERIFY_PREPARED" ]; then
    git check-ref-format "refs/tags/$VERIFY_PREPARED" || die "invalid prepared release tag: $VERIFY_PREPARED"
    build_release_assets
    "$ASSET_WORK/release-assets" verify-prepared "$SCRIPT_DIR/build-release/$VERIFY_PREPARED" "$VERIFY_PREPARED" "$REPO"
    exit 0
fi

prerelease=false
[ "$PRERELEASE" -eq 1 ] && prerelease=true
if [ -n "$RESUME_DRAFT$RESUME_CREATE$PUBLISH_PREPARED" ]; then
    build_release_assets
    if [ -n "$PUBLISH_PREPARED" ]; then
        git check-ref-format "refs/tags/$PUBLISH_PREPARED" || die "invalid prepared release tag: $PUBLISH_PREPARED"
        OUT="$SCRIPT_DIR/build-release/$PUBLISH_PREPARED"
        recovery="$("$ASSET_WORK/release-assets" restore-prepared "$OUT" "$PUBLISH_PREPARED" \
            "$ASSET_WORK" "$PREPARED_REVIEW")"
    elif [ -n "$RESUME_CREATE" ]; then
        git check-ref-format "refs/tags/$RESUME_CREATE" || die "invalid recovery tag: $RESUME_CREATE"
        OUT="$SCRIPT_DIR/build-release/$RESUME_CREATE"
        recovery="$("$ASSET_WORK/release-assets" restore-creation "$OUT" "$RESUME_CREATE" "$ASSET_WORK")"
    else
        recovery="$("$ASSET_WORK/release-assets" restore-draft "$WORK" "$RESUME_DRAFT" "$ASSET_WORK")"
    fi
    IFS=$'\t' read -r recovery_repo TAG COMMIT prerelease <<< "$recovery"
    [ -z "$REPO" ] || [ "$REPO" = "$recovery_repo" ] || die "release $TAG belongs to $recovery_repo"
    REPO="$recovery_repo"
    SHORT="${COMMIT:0:10}"
fi

github_api() {
    gh api --hostname=github.com "$@"
}

if [ "$PUBLISH" -eq 1 ]; then
    need gh
    if [ -z "$REPO" ]; then
        repo_url="$(gh repo view --json url --jq .url)" || die "cannot determine the checkout's repository. Pass --repo=OWNER/NAME."
        case "$repo_url" in
            https://github.com/*) REPO="${repo_url#https://github.com/}" ;;
            *) die "the checkout's repository is on a different host. Pass --repo=OWNER/NAME for GitHub.com." ;;
        esac
    fi
elif [ "$PREPARE_ONLY" -eq 1 ]; then
    REPO="${REPO:-vlang/vinix}"
fi
if [ "$PUBLISH" -eq 1 ] || [ "$PREPARE_ONLY" -eq 1 ]; then
    if [[ ! "$REPO" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9._-]+$ ]] ||
        [ "${REPO#*/}" = . ] || [ "${REPO#*/}" = .. ]; then
        die "expected a GitHub.com repository in OWNER/NAME form"
    fi
fi
if [ "$PUBLISH" -eq 1 ]; then
    gh auth status --hostname=github.com >/dev/null 2>&1 ||
        die "gh is not logged in to GitHub.com. Run gh auth login --hostname github.com."
    # A release is created at a commit GitHub already has. Pushing is left to
    # whoever runs this.
    if ! github_api "repos/$REPO/commits/$COMMIT" --silent >/dev/null 2>&1; then
        die "$SHORT is not on github.com/$REPO yet; push it first"
    fi
    "$V" -backend c -prod -cc cc -o "$ASSET_WORK/release-tag" \
        "$SCRIPT_DIR/build-support/isoboot/release-tag.v"
    release_api="repos/$REPO/releases"
fi

confirm_publish() {
    if [ "$ASSUME_YES" -ne 1 ]; then
        [ -t 0 ] || die "not a terminal; pass --yes to publish without asking"
        local answer
        read -r -p "Publish? [y/N] " answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo "Not published. Everything is in $OUT"; exit 0 ;;
        esac
    fi
}

verify_release() {
    local release_id="$1" response="$2" state="$3" release_url
    release_url="$("$ASSET_WORK/release-assets" verify-release "$ASSET_WORK" "$response" \
        "$REPO" "$release_id" "$TAG" "$prerelease" "$state")" || return
    "$ASSET_WORK/release-tag" verify "$REPO" "$TAG" "$COMMIT" || return
    echo "$release_url"
}

finish_draft() {
    local release_id="$1" response="$2" original="${3:-}" release_url
    "$ASSET_WORK/release-assets" upload-draft "$ASSET_STAGE" "$ASSET_WORK" \
        "$response" "$REPO" "$release_id" "$TAG" "$prerelease" "$original"
    github_api "$release_api/$release_id" > "$ASSET_WORK/draft.json"
    release_url="$(verify_release "$release_id" "$ASSET_WORK/draft.json" draft)"
    if [ "$DRAFT" -eq 1 ]; then
        step "Saved verified draft"
    else
        if ! github_api "$release_api/$release_id" --method PATCH -F draft=false --silent; then
            echo "Publish request failed. Checking GitHub for release $release_id." >&2
        fi
        github_api "$release_api/$release_id" > "$ASSET_WORK/published.json" ||
            die "cannot read back release $release_id; retry with --resume-draft=$release_id"
        release_url="$(verify_release "$release_id" "$ASSET_WORK/published.json" published)"
        step "Published"
    fi
    echo "$release_url"
}

find_created_draft() {
    local candidate_id candidate_tag release_id=''
    github_api "$release_api?per_page=100" --paginate \
        --jq '.[] | select(.draft == true) | [.id, .tag_name] | @tsv' > "$ASSET_WORK/release-list" ||
        die "cannot list GitHub drafts for $TAG. Retry with --resume-create=$TAG"
    while IFS=$'\t' read -r candidate_id candidate_tag; do
        [ "$candidate_tag" = "$TAG" ] || continue
        case "$candidate_id" in
            ''|0*|*[!0-9]*) die "GitHub returned an invalid draft ID for $TAG" ;;
        esac
        [ -z "$release_id" ] || die "multiple GitHub drafts use $TAG"
        release_id="$candidate_id"
    done < "$ASSET_WORK/release-list"
    [ -n "$release_id" ] || die "no GitHub draft found for $TAG. Retry with --resume-create=$TAG"
    echo "$release_id"
}

finish_creation() {
    local response="$1" candidate_id="$2" release_id
    release_id="$("$ASSET_WORK/release-assets" record-draft "$WORK" "$OUT" "$ASSET_WORK" "$response" \
        "$TAG" "$candidate_id")"
    echo "  Recovery record: $WORK/draft-$release_id.json"
    finish_draft "$release_id" "$response"
}

if [ -n "$RESUME_CREATE" ]; then
    step "Recovering GitHub draft creation for $TAG at $SHORT"
    "$ASSET_WORK/release-tag" verify "$REPO" "$TAG" "$COMMIT"
    candidate_id="$(find_created_draft)"
    github_api "$release_api/$candidate_id" > "$ASSET_WORK/created-draft.json"
    confirm_publish
    "$ASSET_WORK/release-assets" stage "$OUT" "$ASSET_WORK/SHA256SUMS" "$ASSET_STAGE"
    finish_creation "$ASSET_WORK/created-draft.json" "$candidate_id"
    exit 0
fi

if [ -n "$RESUME_DRAFT" ]; then
    git check-ref-format "refs/tags/$TAG" || die "invalid Git tag in recovery record: $TAG"
    OUT="$SCRIPT_DIR/build-release/$TAG"
    step "Resuming GitHub draft $RESUME_DRAFT for $TAG at $SHORT"
    "$ASSET_WORK/release-tag" verify "$REPO" "$TAG" "$COMMIT"
    github_api "$release_api/$RESUME_DRAFT" > "$ASSET_WORK/resume-draft.json"
    release_state="$("$ASSET_WORK/release-assets" release-state "$ASSET_WORK/resume-draft.json")"
    if [ "$release_state" = published ]; then
        [ "$DRAFT" -eq 0 ] || die "GitHub release $RESUME_DRAFT is already published"
        "$ASSET_WORK/release-assets" check "$OUT" "$ASSET_WORK/SHA256SUMS"
        release_url="$(verify_release "$RESUME_DRAFT" "$ASSET_WORK/resume-draft.json" published)"
        step "Confirmed published release"
        echo "$release_url"
        exit 0
    fi
    confirm_publish
    finish_draft "$RESUME_DRAFT" "$ASSET_WORK/resume-draft.json" "$OUT"
    exit 0
fi

release_exists() {
    local status=0
    grep -Fqx -- "$1" "$ASSET_WORK/release-tags" || status=$?
    [ "$status" -le 1 ] || die "cannot read the GitHub release tag list"
    return "$status"
}

refresh_release_tags() {
    github_api "$release_api?per_page=100" --paginate \
        --jq 'if type != "array" then error("expected a release list")
              else .[] | .tag_name | if type != "string" then error("invalid release tag")
              elif index("\n") != null or index("\r") != null then error("invalid release tag")
              else . end end' > "$ASSET_WORK/release-tags" ||
        die "cannot list GitHub releases on $REPO"
}

check_pending_creation() {
    local tag="$1" record="$SCRIPT_DIR/build-release/$1/.draft-creation.json"
    if [ -e "$record" ] || [ -L "$record" ]; then
        die "draft creation record already exists. Recover it with --resume-create=$tag"
    fi
}

check_build_output() {
    local tag="$1" record="$SCRIPT_DIR/build-release/$1/.prepared-release.json"
    check_pending_creation "$tag"
    if [ -e "$record" ] || [ -L "$record" ]; then
        die "prepared release record already exists. Use --publish-prepared=$tag or choose another tag."
    fi
}

if [ -n "$TAG" ]; then
    if [ "$PUBLISH" -eq 1 ] || [ "$PREPARE_ONLY" -eq 1 ]; then
        git check-ref-format "refs/tags/$TAG" || die "invalid Git tag: $TAG"
    fi
    if [ -z "$PUBLISH_PREPARED" ]; then check_build_output "$TAG"; fi
fi
if [ "$PUBLISH" -eq 1 ]; then
    refresh_release_tags
fi

refuse_existing_release() {
    if release_exists "$TAG"; then
        die "release $TAG already exists on $REPO"
    fi
}

check_tag_commit() {
    local tag_commit
    tag_commit="$("$ASSET_WORK/release-tag" resolve "$REPO" "$TAG")"
    [ -z "$tag_commit" ] || [ "$tag_commit" = "$COMMIT" ] ||
        die "GitHub tag $TAG points to $tag_commit, expected $COMMIT"
}

publish_staged_assets() {
    local candidate_id=''
    refresh_release_tags
    refuse_existing_release
    "$ASSET_WORK/release-tag" prepare "$REPO" "$TAG" "$COMMIT"
    "$ASSET_WORK/release-assets" prepare-creation "$OUT" "$ASSET_WORK" "$REPO" \
        "$TAG" "$COMMIT" "$prerelease"
    # The prepared handoff retains the notes covered by its verification report.
    if [ -z "$PUBLISH_PREPARED" ]; then
        cp "$ASSET_WORK/RELEASE_NOTES.md" "$ASSET_WORK/public-notes"
        mv -f "$ASSET_WORK/public-notes" "$OUT/RELEASE_NOTES.md"
    fi
    echo "  If draft creation is interrupted, retry with --resume-create=$TAG"
    if ! github_api "$release_api" --method POST -f "tag_name=$TAG" \
        -f "target_commitish=$COMMIT" -f "name=Vinix $TAG" -F "body=@$ASSET_WORK/RELEASE_NOTES.md" \
        -F draft=true -F "prerelease=$prerelease" > "$ASSET_WORK/created-draft.json"; then
        echo "Draft creation request failed. Looking for the draft on GitHub." >&2
        candidate_id="$(find_created_draft)"
        github_api "$release_api/$candidate_id" > "$ASSET_WORK/created-draft.json"
    fi
    finish_creation "$ASSET_WORK/created-draft.json" "$candidate_id"
}

if [ -n "$PUBLISH_PREPARED" ]; then
    check_pending_creation "$TAG"
    refuse_existing_release
    check_tag_commit
    step "Publishing prepared release $TAG from $SHORT to github.com/$REPO"
    confirm_publish
    cmp -s "$ASSET_WORK/SHA256SUMS" "$OUT/SHA256SUMS" || die "prepared SHA256SUMS changed"
    cmp -s "$ASSET_WORK/RELEASE_NOTES.md" "$OUT/RELEASE_NOTES.md" || die "prepared release notes changed"
    if [ -n "$PREPARED_REVIEW" ]; then
        "$ASSET_WORK/release-assets" stage-reviewed "$OUT" "$ASSET_WORK" "$ASSET_STAGE" \
            "$REPO" "$TAG" "$COMMIT" "$prerelease"
    else
        "$ASSET_WORK/release-assets" stage "$OUT" "$ASSET_WORK/SHA256SUMS" "$ASSET_STAGE"
    fi
    publish_staged_assets
    exit 0
fi

if [ -z "$TAG" ]; then
    base_tag="iso-$(date +%Y-%m-%d)"
    TAG="$base_tag"
    n=2
    while [ "$PUBLISH" -eq 1 ]; do
        if ! release_exists "$TAG"; then
            tag_commit="$("$ASSET_WORK/release-tag" resolve "$REPO" "$TAG")"
            [ -n "$tag_commit" ] || break
        fi
        TAG="$base_tag-$n"
        n=$((n + 1))
    done
    check_build_output "$TAG"
elif [ "$PUBLISH" -eq 1 ]; then
    refuse_existing_release
    check_tag_commit
fi

if [ "$PREPARE_ONLY" -eq 1 ] && [ "${VINIX_RELEASE-$TAG}" != "$TAG" ]; then
    die "prepared builds require VINIX_RELEASE to match the release tag"
fi
OUT="$SCRIPT_DIR/build-release/$TAG"
mkdir -p "$OUT" "$CACHE"

if [ -n "${VINIX_UI2_SOURCE:-}" ]; then
    UI2_SOURCE="$VINIX_UI2_SOURCE"
elif [ -f "$SCRIPT_DIR/../ui2/v.mod" ]; then
    UI2_SOURCE="$(cd "$SCRIPT_DIR/../ui2" && pwd)"
else
    UI2_SOURCE="$SCRIPT_DIR/third_party/ui2"
fi
[ -f "$UI2_SOURCE/v.mod" ] || die "ui2 not found at $UI2_SOURCE; clone it: git clone https://github.com/vlang/ui2 third_party/ui2"

echo "Release $TAG from $SHORT ($(git log -1 --format=%s "$COMMIT"))"
echo "  V:   $V ($("$V" version 2>/dev/null || echo 'version unknown'))"
echo "  ui2: $UI2_SOURCE"
echo "  out: $OUT"

# Freeze the expected selection before building. The receipt tool belongs to
# this release driver, including when --ref selects an older desktop source.
package_inputs_selected() {
    local variable target
    for variable in VINIX_PACKAGE_IMAGE_CONFIG VINIX_PACKAGE_IMAGE_REPOSITORIES VINIX_PACKAGE_IMAGE_APPLICATIONS; do
        target="${variable}_$1"
        if [ -n "${!target:-}${!variable:-}" ]; then return 0; fi
    done
    return 1
}

plan_package_selection() {
    local target="$1" architecture="$2" plan reviewed
    plan="$PACKAGE_WORK/$target.plan"
    "$PACKAGE_WORK/receipt" plan "$architecture" > "$plan"
    if [ -n "$PACKAGE_REVIEW" ]; then
        reviewed="$PACKAGE_REVIEW/$target.json"
        [ -s "$plan" ] || die "$target has no package inputs to match its reviewed plan"
        [ -f "$reviewed" ] || die "$target is missing its reviewed package plan at $reviewed"
        cmp -s "$reviewed" "$plan" || die "$target package inputs differ from its reviewed plan at $reviewed"
    fi
}

PACKAGE_WORK=''
PACKAGE_RECEIPTS=()
if [ -n "$PACKAGE_REVIEW" ] ||
   { [ "$BUILD_AMD64" -eq 1 ] && package_inputs_selected X86_64; } ||
   { [ "$BUILD_ARM64" -eq 1 ] && package_inputs_selected AARCH64; }; then
    step "Preflighting selected release package inputs"
    PACKAGE_WORK="$ASSET_WORK"
    "$V" -backend c -prod -cc cc \
        -path "@vlib|@vmodules|$SCRIPT_DIR|$SCRIPT_DIR/build-support|$SCRIPT_DIR/tools/accounts" \
        -o "$PACKAGE_WORK/receipt" "$SCRIPT_DIR/build-support/isoboot/package-receipt.v"
    if [ "$BUILD_AMD64" -eq 1 ]; then
        plan_package_selection amd64 x86_64
    fi
    if [ "$BUILD_ARM64" -eq 1 ]; then
        plan_package_selection arm64 aarch64
    fi
fi

# ── A clean tree at the release commit ─────────────────────────────────────

step "Checking out $SHORT in $SRC"
if [ -e "$SRC/.git" ]; then
    git -C "$SRC" checkout --quiet --detach --force "$COMMIT"
else
    rm -rf "$SRC"
    git worktree prune
    git worktree add --quiet --detach "$SRC" "$COMMIT"
fi
# The kernel's pinned C dependencies. Start from this checkout's copies, if it
# has them, and let get-deps move them to whatever the release commit pins.
for dependency in freestnd-c-hdrs cc-runtime c/flanterm c/uacpi uacpi-repository \
    lwip-repository c/lwip; do
    if [ -d "$SCRIPT_DIR/kernel/$dependency" ]; then
        mkdir -p "$SRC/kernel/$dependency"
        rsync -a --delete "$SCRIPT_DIR/kernel/$dependency/" "$SRC/kernel/$dependency/"
    fi
done
cp -f "$SCRIPT_DIR"/kernel/c/nanoprintf* "$SRC/kernel/c/" 2>/dev/null || true
(cd "$SRC/kernel" && ./get-deps) > "$WORK/get-deps.log" 2>&1 || {
    tail -20 "$WORK/get-deps.log" >&2
    die "fetching the kernel's dependencies failed"
}

# Release kernels are production builds.
unset PROD
export V
# Each image records the release it is as /etc/vinix-release. At boot it asks
# vinix-os.org/version for the newest one and, when that is newer, the desktop
# tells the user to download it (build-support/vinix-version-check). A test
# build that is not to be published can set VINIX_RELEASE= (empty) to make
# development images instead, which take X11 and the iOS runtime from the newest
# release rather than from a tag that will never have them.
export VINIX_RELEASE="${VINIX_RELEASE-$TAG}"

IMAGES=()
# The X11 bundles and their checksum files, uploaded beside the images.
BUNDLES=()

# ── amd64 ──────────────────────────────────────────────────────────────────

# The desktops are assembled from package layers built by their own scripts.
# They hold Alpine's and upstream binaries rather than Vinix source, so this
# checkout's copies are used as they are.
layer_missing=0
check_layer() {
    if [ ! -e "$1" ]; then
        echo "  missing: $1 (build it with $2)" >&2
        layer_missing=1
    fi
}

if [ "$BUILD_AMD64" -eq 1 ]; then
    step "Building the amd64 image"
    for layer in x11 network-tools; do
        check_layer "$SCRIPT_DIR/build-amd64-$layer/staging" "./build-$layer-amd64.sh"
    done
    [ "$layer_missing" -eq 0 ] || die "build the missing layers in $SCRIPT_DIR first"
    rm -f "$OUT/vinix-amd64.iso"
    VINIX_UI2_SOURCE="$UI2_SOURCE" \
    VINIX_AMD64_X11_STAGING="$SCRIPT_DIR/build-amd64-x11/staging" \
    VINIX_AMD64_NETWORK_TOOLS_STAGING="$SCRIPT_DIR/build-amd64-network-tools/staging" \
    VINIX_AMD64_DESKTOP_BUILD_DIR="$WORK/amd64-desktop" \
    VINIX_AMD64_USERLAND_BUILD_DIR="$CACHE/amd64-userland" \
    VINIX_AMD64_BUILD_DIR="$SRC/build-amd64-kernel" \
    VINIX_AMD64_DESKTOP_ISO="$OUT/vinix-amd64.iso" \
    VINIX_AMD64_X11_BUNDLE="$OUT/vinix-x11-amd64.tar.gz" \
        "$SRC/scripts/build-desktop-amd64.sh"
    [ -f "$OUT/vinix-amd64.iso" ] || die "the amd64 build made no ISO"
    [ -s "$OUT/vinix-x11-amd64.tar.gz.sha256" ] || die "the amd64 build made no X11 bundle"
    IMAGES+=("$OUT/vinix-amd64.iso")
    BUNDLES+=("$OUT/vinix-x11-amd64.tar.gz" "$OUT/vinix-x11-amd64.tar.gz.sha256")
fi

# ── arm64 ──────────────────────────────────────────────────────────────────

if [ "$BUILD_ARM64" -eq 1 ]; then
    step "Building the arm64 image"
    check_layer "$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar" ./scripts/build-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-userland/staging" ./scripts/build-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-x11/staging" ./scripts/build-x11-aarch64.sh
    check_layer "$SCRIPT_DIR/build-aarch64-network-tools/staging" ./scripts/build-network-tools-aarch64.sh
    [ "$layer_missing" -eq 0 ] || die "build the missing layers in $SCRIPT_DIR first"

    mkdir -p "$SRC/build-support/init-aarch64"
    ln -sf "$SCRIPT_DIR/build-support/init-aarch64/initramfs.tar" \
        "$SRC/build-support/init-aarch64/initramfs.tar"

    # Kernel generators resolve ../tests and ../build-support beside their
    # build directory. Keep both builds inside the clean release checkout.
    VINIX_AARCH64_BUILD_DIR="$SRC/build-arm64-kernel" \
        "$SRC/scripts/build-aarch64.sh" --no-userland --no-iso

    VINIX_UI2_SOURCE="$UI2_SOURCE" \
    VINIX_AARCH64_USERLAND_BUILD_DIR="$SCRIPT_DIR/build-aarch64-userland" \
    VINIX_AARCH64_APP_CACHE="$CACHE/arm64-desktop-apps" \
    VINIX_NETWORK_TOOLS_STAGING="$SCRIPT_DIR/build-aarch64-network-tools/staging" \
    VINIX_X11_STAGING="$SCRIPT_DIR/build-aarch64-x11/staging" \
    VINIX_GPU_SYSROOT="$SCRIPT_DIR/build-aarch64-x11/sysroot" \
    VINIX_DESKTOP_INITRAMFS="$WORK/arm64-initramfs-desktop.tar" \
    VINIX_X11_BUNDLE="$OUT/vinix-x11-arm64.tar.gz" \
        "$SRC/scripts/build-desktop-aarch64.sh" --compact-initramfs
    [ -s "$OUT/vinix-x11-arm64.tar.gz.sha256" ] || die "the arm64 build made no X11 bundle"
    BUNDLES+=("$OUT/vinix-x11-arm64.tar.gz" "$OUT/vinix-x11-arm64.tar.gz.sha256")

    # The iOS runtime the first-run app page offers, which machines download
    # from their release rather than build: the images carry no V compiler.
    IOS_RUNTIME="$OUT/vinix-ios-runtime-arm64"
    if [ -n "${VINIX_IOS_RELEASE_RUNTIME:-}" ]; then
        : "${VINIX_IOS_RELEASE_RUNTIME_SHA256:?set the published iOS runtime checksum}"
        : "${VINIX_IOS_RELEASE_RUNTIME_ORIGIN:?set the published iOS runtime origin}"
        "$SRC/build-support/run-v-tool.sh" "$SRC/build-support/ios/stage-release-runtime.v" \
            "$VINIX_IOS_RELEASE_RUNTIME" "$IOS_RUNTIME" "$VINIX_IOS_RELEASE_RUNTIME_SHA256"
    else
        VINIX_IOS_BUILD_DIR="$WORK/ios" \
        VINIX_AARCH64_SYSROOT="$SCRIPT_DIR/build-aarch64-userland/staging" \
            "$SRC/scripts/build-ios-aarch64.sh" --runner-only
        install -m755 "$WORK/ios/staging/usr/bin/run-ios" "$IOS_RUNTIME"
    fi
    file "$IOS_RUNTIME" | grep -q 'ARM aarch64.*statically linked' ||
        die "the iOS runtime is not a static arm64 executable"
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$OUT" && sha256sum vinix-ios-runtime-arm64)
    else
        (cd "$OUT" && shasum -a 256 vinix-ios-runtime-arm64)
    fi > "$IOS_RUNTIME.sha256"
    BUNDLES+=("$IOS_RUNTIME" "$IOS_RUNTIME.sha256")

    rm -f "$OUT/vinix-arm64.iso"
    VINIX_AARCH64_KERNEL="$SRC/build-arm64-kernel/bin/vinix" \
    VINIX_AARCH64_INITRAMFS="$WORK/arm64-initramfs-desktop.tar" \
    VINIX_AARCH64_ISO="$OUT/vinix-arm64.iso" \
    VINIX_AARCH64_ISO_BUILD_DIR="$WORK/arm64-iso" \
        "$SRC/build-support/build-aarch64-iso.sh"
    IMAGES+=("$OUT/vinix-arm64.iso")
fi

[ "${#IMAGES[@]}" -gt 0 ] || die "nothing was built"
ASSET_DIRECTORY="$OUT"
build_release_assets
capture=capture-upload
if [ "$PUBLISH" -eq 0 ] && [ "$PREPARE_ONLY" -eq 0 ]; then
    capture=capture
    "$ASSET_WORK/release-assets" check-upload-sizes "$OUT" "${IMAGES[@]##*/}"
fi
if [ "$RUN_TESTS" -eq 1 ] || [ -n "$PACKAGE_WORK" ]; then
    step "Capturing release assets"
    "$ASSET_WORK/release-assets" "$capture" "$OUT" "$ASSET_STAGE" \
        "${IMAGES[@]##*/}" "${BUNDLES[@]##*/}"
    ASSET_DIRECTORY="$ASSET_STAGE"
elif [ "$PUBLISH" -eq 1 ] || [ "$PREPARE_ONLY" -eq 1 ]; then
    "$ASSET_WORK/release-assets" check-upload-sizes "$OUT" "${IMAGES[@]##*/}" "${BUNDLES[@]##*/}"
fi

staged_images=()
for image in "${IMAGES[@]}"; do
    name="${image##*/}"
    staged_images+=("$ASSET_STAGE/$name")
done

if [ -n "$PACKAGE_WORK" ]; then
    step "Checking package inputs embedded in the release ISOs"
    for arch in amd64 arm64; do
        plan="$PACKAGE_WORK/$arch.plan"
        if [ ! -s "$plan" ]; then continue; fi
        name="vinix-packages-$arch.json"
        "$PACKAGE_WORK/receipt" verify-staged "$ASSET_STAGE/vinix-$arch.iso" "$plan" > "$ASSET_STAGE/$name"
        cp "$ASSET_STAGE/$name" "$PACKAGE_WORK/public-receipt"
        mv -f "$PACKAGE_WORK/public-receipt" "$OUT/$name"
        PACKAGE_RECEIPTS+=("$OUT/$name")
        BUNDLES+=("$OUT/$name")
    done
fi

# Capture the complete upload list before boot tests can change an output.
step "Recording checksums for release assets"
: > "$ASSET_WORK/package-pins"
for receipt in ${PACKAGE_RECEIPTS[@]+"${PACKAGE_RECEIPTS[@]}"}; do
    "$PACKAGE_WORK/receipt" checksums "$ASSET_STAGE/${receipt##*/}" >> "$ASSET_WORK/package-pins"
done
"$ASSET_WORK/release-assets" record "$ASSET_DIRECTORY" "$ASSET_WORK/package-pins" \
    "${IMAGES[@]##*/}" "${BUNDLES[@]##*/}" > "$ASSET_WORK/SHA256SUMS"

# ── Boot tests ─────────────────────────────────────────────────────────────

TEST_SUMMARY=''
if [ "$RUN_TESTS" -eq 1 ]; then
    step "Boot-testing the images"
    rm -rf "$OUT/test"
    if ! "$SRC/scripts/test-iso.sh" --out="$OUT/test" "${staged_images[@]}" | tee "$OUT/test.log"; then
        die "the boot tests failed; nothing was published (logs in $OUT/test)"
    fi
    "$ASSET_WORK/release-assets" check "$ASSET_STAGE" "$ASSET_WORK/SHA256SUMS"
    TEST_SUMMARY="$(sed -n 's/^  PASS  //p' "$OUT/test.log")"
fi

# ── Checksums and notes ────────────────────────────────────────────────────

step "Writing checksums and release notes"
"$ASSET_WORK/release-assets" check "$OUT" "$ASSET_WORK/SHA256SUMS"
cp "$ASSET_WORK/SHA256SUMS" "$ASSET_WORK/public-checksums"
mv -f "$ASSET_WORK/public-checksums" "$OUT/SHA256SUMS"
cat "$OUT/SHA256SUMS"

describe_boot() {
    case "$1" in
        qemu-amd64-bios) echo "QEMU, BIOS (i440fx, no HPET, one CPU: VirtualBox's defaults)" ;;
        qemu-amd64-uefi) echo "QEMU, UEFI (q35), installing onto a blank SATA disk" ;;
        qemu-amd64-uefi-disk) echo "QEMU, UEFI (q35), again, from the system on that disk" ;;
        qemu-arm64-virtio) echo "QEMU, UEFI (virt, virtio keyboard and tablet), installing onto a blank virtio disk" ;;
        qemu-arm64-virtio-disk) echo "QEMU, UEFI (virt), again, from the system on that disk" ;;
        qemu-arm64-usb) echo "QEMU, UEFI (virt, USB keyboard and tablet)" ;;
        virtualbox-amd64) echo "VirtualBox, BIOS, installing onto a blank SATA disk" ;;
        virtualbox-arm64) echo "VirtualBox, EFI" ;;
        *) echo "$1" ;;
    esac
}

{
    echo "Vinix built from $COMMIT ($(git log -1 --format=%cs "$COMMIT")). Both images boot"
    echo "into the Vinix desktop."
    echo
    echo "| Image | Size | Runs on |"
    echo "|---|---|---|"
    for image in "${IMAGES[@]}"; do
        name="$(basename "$image")"
        size="$(human_size "$(file_size "$image")")"
        case "$name" in
            *amd64*) echo "| [$name](https://github.com/${REPO:-vlang/vinix}/releases/download/$TAG/$name) | $size | x86-64: QEMU, VirtualBox on Intel and AMD hosts, PCs (BIOS or UEFI) |" ;;
            *arm64*) echo "| [$name](https://github.com/${REPO:-vlang/vinix}/releases/download/$TAG/$name) | $size | arm64: QEMU, VirtualBox on Apple Silicon Macs (UEFI) |" ;;
        esac
    done
    echo
    echo "Give the VM **at least 4 GiB** of memory and one **writable disk of 4 GiB or more**"
    echo "(16 GiB leaves room for apps). Choose **Install Vinix on an empty disk** at"
    echo "the ISO boot menu. To reuse a disk, back it up, disconnect other drives,"
    echo "and use **Erase a disk and install Vinix**. This replaces all partitions"
    echo "and files on the target disk. Once the desktop starts, shut down, detach the ISO or"
    echo "remove the USB stick, and boot the installed disk. Users, files and apps"
    echo "persist on that disk. **Try Vinix** starts a temporary session in memory."
    echo
    echo "Vinix drives IDE and SATA disks on amd64 and VirtIO block devices on arm64."
    echo
    echo "### QEMU"
    echo
    echo '```sh'
    echo '# amd64 (use -accel kvm -cpu host on Linux, -accel hvf on an Intel Mac)'
    echo 'qemu-img create -f qcow2 vinix-amd64.qcow2 16G'
    echo 'qemu-system-x86_64 -machine q35 -m 4096 -smp 2 -cdrom vinix-amd64.iso \'
    echo '    -drive file=vinix-amd64.qcow2,format=qcow2 -nic user,model=e1000'
    echo
    echo '# arm64 (use -accel kvm on an arm64 Linux host)'
    echo 'qemu-img create -f qcow2 vinix-arm64.qcow2 16G'
    echo 'qemu-system-aarch64 -machine virt -accel hvf -cpu host -m 4096 -smp 4 \'
    echo '    -bios "$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd" \'
    echo '    -device virtio-scsi-pci -device scsi-cd,drive=cd \'
    echo '    -drive if=none,id=cd,media=cdrom,file=vinix-arm64.iso \'
    echo '    -drive if=none,id=hd,file=vinix-arm64.qcow2,format=qcow2 \'
    echo '    -device virtio-blk-device,drive=hd \'
    echo '    -device ramfb -device qemu-xhci -device usb-kbd -device usb-tablet \'
    echo '    -netdev user,id=net0 -device virtio-net-device,netdev=net0'
    echo '```'
    echo
    if [ "${#PACKAGE_RECEIPTS[@]}" -gt 0 ]; then
        echo "### Signed packages from the images"
        echo
        echo "Each receipt records the bundled publisher keys, signed indexes and any"
        echo "release applications selected for review in Software."
        for receipt in "${PACKAGE_RECEIPTS[@]}"; do
            echo "- [$(basename "$receipt")](https://github.com/${REPO:-vlang/vinix}/releases/download/$TAG/$(basename "$receipt"))"
        done
        echo
    fi
    echo "Optional apps offered by legacy setup use \`pkg install\` and need networking."
    echo "Vinix drives VirtIO and Intel e1000 cards. The images leave out"
    echo "X11: the first graphical Linux application brings it, from the"
    echo "\`vinix-x11-*.tar.gz\` files of this release. Python is a \`pkg install python3\`"
    echo "away; the V compiler and Oh My Zsh are left out too. The iOS runtime the first"
    echo "launch offers on arm64 is \`vinix-ios-runtime-arm64\`, prebuilt."
    if [ "$BUILD_ARM64" -eq 1 ] && [ -n "${VINIX_IOS_RELEASE_RUNTIME:-}" ]; then
        echo
        echo "The optional iOS runtime is retained from $VINIX_IOS_RELEASE_RUNTIME_ORIGIN."
        echo "Its verified SHA-256 is \`$VINIX_IOS_RELEASE_RUNTIME_SHA256\`."
    fi
    echo
    echo "### VirtualBox"
    echo
    echo "VirtualBox runs guests of its host's architecture: the amd64 image on Intel and"
    echo "AMD machines, the arm64 image on Apple Silicon Macs."
    echo
    echo "Create a VM of type **Other/Unknown (64-bit)** or **Other/Unknown (ARM 64-bit)**,"
    echo "give it **4096 MB** of memory and two CPUs, and attach the ISO to its optical"
    echo "drive. For amd64, add a new **16 GB** hard disk on a **SATA** controller; Vinix"
    echo "has no driver for the disk controllers VirtualBox gives an arm64 VM, so that one"
    echo "runs from memory. For the network, set the adapter type to **Intel PRO/1000 MT"
    echo "Desktop (82540EM)**. Everything else can stay as VirtualBox sets it; the amd64"
    echo "image boots with EFI switched on or off. From a checkout of this repository,"
    echo "\`./scripts/run-iso-virtualbox.sh vinix-amd64.iso\` creates and starts such a VM, disk"
    echo "included."
    if [ -n "$TEST_SUMMARY" ]; then
        echo
        echo "### Tested before release"
        echo
        echo "Booted from the images above to the desktop, with typing and the pointer checked:"
        echo
        while IFS= read -r boot; do
            [ -n "$boot" ] && echo "- $(describe_boot "$boot")"
        done <<< "$TEST_SUMMARY"
    fi
    echo
    echo "SHA-256 checksums are in \`SHA256SUMS\`."
} > "$ASSET_WORK/RELEASE_NOTES.md"
cp "$ASSET_WORK/RELEASE_NOTES.md" "$ASSET_WORK/public-notes"
mv -f "$ASSET_WORK/public-notes" "$OUT/RELEASE_NOTES.md"

if [ "$PREPARE_ONLY" -eq 1 ]; then
    "$ASSET_WORK/release-assets" save-prepared "$OUT" "$ASSET_WORK" "$REPO" "$TAG" "$COMMIT" "$prerelease"
    step "Saved prepared release $TAG"
    echo "Publish these assets with --publish-prepared=$TAG"
    exit 0
fi
if [ "$PUBLISH" -eq 0 ]; then
    step "Done; not publishing (--no-publish)"
    echo "Images and notes are in $OUT"
    exit 0
fi

# ── Publish ────────────────────────────────────────────────────────────────

step "Preparing $TAG for github.com/$REPO"
kind=release
[ "$PRERELEASE" -eq 1 ] && kind=pre-release
[ "$DRAFT" -eq 1 ] && kind="draft $kind"
echo "  $kind $TAG at $SHORT, with:"
for image in "${IMAGES[@]}"; do
    echo "    $(basename "$image") ($(human_size "$(file_size "$image")"))"
done
echo "    SHA256SUMS"
for bundle in ${BUNDLES[@]+"${BUNDLES[@]}"}; do
    echo "    $(basename "$bundle") ($(human_size "$(file_size "$bundle")"))"
done
confirm_publish

cmp -s "$ASSET_WORK/SHA256SUMS" "$OUT/SHA256SUMS" ||
    die "SHA256SUMS changed after verification"
if [ "$ASSET_DIRECTORY" = "$ASSET_STAGE" ]; then
    "$ASSET_WORK/release-assets" check-upload-sizes "$ASSET_STAGE" "${IMAGES[@]##*/}" "${BUNDLES[@]##*/}"
    "$ASSET_WORK/release-assets" check "$OUT" "$ASSET_WORK/SHA256SUMS"
else
    step "Preparing verified release copies"
    "$ASSET_WORK/release-assets" stage "$OUT" "$ASSET_WORK/SHA256SUMS" "$ASSET_STAGE"
fi
publish_staged_assets
