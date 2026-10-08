// Original independent edk2 fixture bytes, retained verbatim.
module ovmffixture

pub const case_names = [
	'test_explicit_toolchain_takes_precedence_and_normalizes_prefix',
	'test_missing_llvm_tools_stop_before_basetools',
	'test_missing_lld_reports_install_command_before_basetools',
	'test_separate_lld_on_path_is_available_to_build',
	'test_homebrew_discovers_llvm_and_separate_keg_only_lld',
	'test_fresh_and_already_patched_checkouts',
	'test_fresh_bootstrap_fetches_shallow_direct_submodules_only',
	'test_existing_checkout_recovers_missing_submodules',
	'test_incomplete_mode_is_rejected',
	'test_incompatible_source_reports_git_diagnostic',
	'test_setup_accepts_unset_variables_and_restores_strict_mode',
	'test_setup_failure_stops_before_driver_build',
]

const upstream = 'STATIC EFI_GRAPHICS_OUTPUT_MODE_INFORMATION  mQemuRamfbModeInfo[] = {
  {
    0,    // Version
    640,  // HorizontalResolution
    480,  // VerticalResolution
  },{
    0,    // Version
    800,  // HorizontalResolution
    600,  // VerticalResolution
  },{
    0,    // Version
    1024, // HorizontalResolution
    768,  // VerticalResolution
  }
};

STATIC EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE  mQemuRamfbMode = {
  ARRAY_SIZE (mQemuRamfbModeInfo),                // MaxMode
  0,                                              // Mode
  mQemuRamfbModeInfo,                             // Info
  sizeof (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION),  // SizeOfInfo
};
'
const patch_path = 'patches/edk2/qemu-ramfb-2048x1536.patch'
const driver_path = 'OvmfPkg/QemuRamfbDxe/QemuRamfb.c'
const sentinel = 73

const setup_optional = '
SetupPythonCommand() {
    if [ -n "\$PYTHON_COMMAND" ]; then
        return 0
    fi
    export PYTHON_COMMAND=python3
}
SetupPythonCommand
if [ -z "\$WORKSPACE" ]; then
    export WORKSPACE="\$PWD"
fi
if [ -z "\$EDK_TOOLS_PATH" ]; then
    export EDK_TOOLS_PATH="\$WORKSPACE/BaseTools"
fi
if [ -z "\$CONF_PATH" ]; then
    export CONF_PATH="\$WORKSPACE/Conf"
fi
if [ -n "\$PACKAGES_PATH" ]; then
    echo \'test: unexpected packages path\' >&2
    return 72
fi
build() {
    case "\$-" in
        *u*) ;;
        *) echo \'test: nounset was not restored\' >&2; return 72 ;;
    esac
    case "\$-" in
        *e*) ;;
        *) echo \'test: errexit was disabled\' >&2; return 72 ;;
    esac
    echo "test: ramfb build \$*"
    return 73
}
'

const setup_failure = '
build() {
    echo \'test: unexpected ramfb build\'
    return 73
}
echo \'test: setup failed\' >&2
return 61
'
