#!/usr/bin/env python3
"""Non-interactive policy adapter for the pinned upstream Asahi installer.

Disk choice, allocation, and destructive confirmation have already been made in
the ui2 app. Apple machine-owner authentication remains intentionally
interactive. The actual APFS/stub installation stays in upstream code.
"""

import logging
import os
import re
import shlex
import subprocess
import sys
import time

import main as upstream


class VinixInstaller(upstream.InstallerMain):
    def __init__(self, version):
        super().__init__(version)
        self.target_disk = os.environ.get("VINIX_TARGET_DISK", "")
        self.allocation = int(os.environ.get("VINIX_SPACE_BYTES", "0"))
        if not re.fullmatch(r"disk[0-9]+", self.target_disk):
            raise ValueError("Invalid target disk identifier")
        if self.allocation < 16_000_000_000:
            raise ValueError("Vinix allocation must be at least 16 GB")

    def input(self):
        # The graphical app owns acknowledgement and confirmation. These are
        # upstream informational pauses, not authentication prompts.
        return ""

    def yesno(self, prompt, default=False):
        upstream.p_info(f"  Confirmed in Vinix Installer: {prompt}")
        return True

    def get_min_free_space(self, part):
        # Expert mode is needed only so upstream enumerates supported external
        # boot disks. Keep its normal 38 GB macOS safety margin regardless.
        if part.os and any(item.version for item in part.os):
            return upstream.MIN_FREE_OS
        return upstream.MIN_FREE

    def choice(self, prompt, options, default=None):
        if prompt == "Action":
            if self.cur_disk != self.target_disk:
                if "d" not in options:
                    raise RuntimeError(f"Selected disk {self.target_disk} is not available")
                return "d"
            if self.cur_disk != self.sys_disk:
                if "w" not in options:
                    raise RuntimeError(f"External disk {self.target_disk} cannot be installed")
                return "w"

            free_sizes = [part.size for part in self.parts if part.free]
            if "f" in options and free_sizes and max(free_sizes) >= self.allocation:
                return "f"
            if "r" in options:
                return "r"
            raise RuntimeError(
                f"No APFS container on {self.target_disk} can safely provide "
                f"{upstream.ssize(self.allocation)}"
            )
        if prompt == "Version":
            # The last entry is upstream's newest compatible, non-broken
            # firmware choice. Expert mode merely made this prompt visible.
            return len(options) - 1
        return super().choice(prompt, options, default)

    def action_select_disk(self):
        eligible = {
            disk["DeviceIdentifier"] for disk in (self.external_disks or [])
        }
        if self.target_disk not in eligible:
            raise RuntimeError(
                f"{self.target_disk} is not an m1n1-bootable external USB disk"
            )
        self.cur_disk = self.target_disk
        return True

    def action_resize(self, resizable):
        # Never guess between APFS containers: resize the one containing the
        # booted macOS. A surprising layout gets a clean failure instead.
        candidates = [
            part for part in resizable if self.cur_os in (part.os or [])
        ]
        if len(candidates) != 1:
            raise RuntimeError(
                "Could not unambiguously identify the booted macOS APFS container"
            )
        return super().action_resize(candidates)

    def get_size(self, prompt, default=None, min=None, max=None, total=None):
        if prompt == "New size" and total is not None:
            new_macos_size = upstream.align_up(
                total - self.allocation, upstream.PART_ALIGN
            )
            if min is not None and new_macos_size < min:
                raise RuntimeError(
                    f"Allocating {upstream.ssize(self.allocation)} would leave macOS "
                    f"below its safe minimum of {upstream.ssize(min)}"
                )
            return new_macos_size
        return super().get_size(prompt, default, min, max, total)

    def choose_os(self):
        os_list = self.data.get("os_list", [])
        if len(os_list) != 1 or os_list[0].get("name") != "Vinix":
            raise RuntimeError("The signed Vinix installer profile is missing")
        return os_list[0]

    def get_os_size_and_info(self, free_size, min_size, template):
        if self.allocation < min_size:
            raise RuntimeError(
                f"Vinix needs {upstream.ssize(min_size)} on this disk"
            )
        if self.allocation > free_size:
            raise RuntimeError(
                f"Only {upstream.ssize(free_size)} of contiguous space is available"
            )

        self.osins.name = "Vinix"
        upstream.p_message(
            f"Vinix will be allocated {upstream.ssize(self.allocation)}."
        )
        ipsw = self.choose_ipsw(template.get("supported_fw", None))
        logging.info("Chosen IPSW version: %s", ipsw.version)
        self.ins = upstream.stub.StubInstaller(
            self.sysinfo, self.dutil, self.osinfo
        )
        self.ins.load_ipsw(ipsw)
        # action_install_into_free/action_wipe pass OS partition size here;
        # the 2.5 GB stub was already counted in the user-visible allocation.
        return self.allocation - upstream.STUB_SIZE

    def step2_indirect(self, report=False):
        self.ins.prepare_for_step2()
        self.install_info(report)
        print()
        upstream.p_success("Vinix and m1n1 are installed.")
        upstream.p_message("The Mac must fully shut down before the first boot:")
        upstream.p_message("  1. Press Enter below and wait at least 25 seconds.")
        upstream.p_message("  2. Press and HOLD the power button until startup options appear.")
        upstream.p_message("  3. Select Vinix (it may briefly appear as macOS Recovery).")
        upstream.p_message("  4. Complete the one-time Finish Installation screen.")
        print()
        upstream.input_prompt("Press Enter to shut down: ")
        time.sleep(1)
        os.system("shutdown -h now")

    def step2_completed(self, report=False):
        self.install_info(report)
        print()
        upstream.p_success("Vinix and m1n1 are installed.")
        upstream.p_message(
            "After restart, hold the power button to open startup options and select Vinix."
        )
        upstream.input_prompt("Press Enter to restart: ")
        time.sleep(1)
        os.system("shutdown -r now")


def run():
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s %(name)-12s %(levelname)-8s %(message)s",
        datefmt="%m-%d %H:%M",
        filename="installer.log",
        filemode="w",
    )
    console = logging.StreamHandler()
    console.setLevel(logging.ERROR)
    console.setFormatter(
        logging.Formatter("%(name)-12s: %(levelname)-8s %(message)s")
    )
    logging.getLogger("").addHandler(console)
    try:
        version = open("version.tag", "r", encoding="utf-8").read().strip()
        VinixInstaller(version).main()
    except KeyboardInterrupt:
        print()
        upstream.p_error("Interrupted; no further disk changes will be made.")
        return 130
    except subprocess.CalledProcessError as error:
        command = shlex.join(error.cmd)
        upstream.p_error(f"Failed to run process: {command}")
        if error.output is not None:
            upstream.p_error(f"Output: {error.output}")
        logging.exception("Process execution failed")
        upstream.p_warning("Installer files and installer.log were retained for diagnosis.")
        return 1
    except Exception as error:
        upstream.p_error(str(error))
        logging.exception("Installation failed")
        upstream.p_warning("Installer files and installer.log were retained for diagnosis.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(run())
