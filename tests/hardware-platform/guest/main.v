// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The guest half of the hardware tests: /sbin/init of a machine that has
// nothing else in it.
//
// The controller puts the name of one scenario in /etc/hwtest-scenario. This
// program runs it and says how it went on the serial port, which is all the
// host can see of it:
//
//   HWTEST START <scenario>            the scenario began
//   HWTEST STEP <text>                 a point the host may act on
//   HWTEST INFO <text>                 something measured, for the report
//   HWTEST FAIL <scenario>: <message>  a check did not hold
//   HWTEST PASS <scenario>             every check held
//   HWTEST FAIL <scenario>             at least one did not
//
// A scenario is a function `scenario_<name>(mut t Test)` in a file of its own
// and a line in run_scenario() below.
module main

// Runs the named scenario. False when this program has no such scenario.
fn run_scenario(name string, mut t Test) bool {
	match name {
		'acpi-ec-absent' { scenario_acpi_ec_absent(mut t) }
		'acpi-ec-off' { scenario_acpi_ec_off(mut t) }
		'acpi-ec-selftest', 'acpi-ec-selftest-dsdt' { scenario_acpi_ec_selftest(mut t) }
		'acpi-power' { scenario_acpi_power(mut t) }
		'acpi-thermal' { scenario_acpi_thermal(mut t) }
		'ahci' { scenario_ahci(mut t) }
		'cpu-power' { scenario_cpu_power(mut t) }
		'cpu-power-simulated' { scenario_cpu_power_simulated(mut t) }
		'devices' { scenario_devices(mut t) }
		'drivers-sleep' { scenario_drivers_sleep(mut t) }
		'nvme-sleep' { scenario_nvme_sleep(mut t) }
		'firmware' { scenario_firmware(mut t) }
		'iommu-amd' { scenario_iommu_amd(mut t) }
		'iommu-intel' { scenario_iommu_intel(mut t) }
		'iommu-amd-selftest', 'iommu-intel-selftest' { scenario_iommu_selftest(mut t) }
		'iommu-off' { scenario_iommu_off(mut t) }
		'pci-d3' { scenario_pci_d3(mut t) }
		'pci-d3-off' { scenario_pci_d3_off(mut t) }
		'pci-d3-selftest' { scenario_pci_d3_selftest(mut t) }
		'pci-hotplug' { scenario_pci_hotplug(mut t) }
		'pci-hotplug-acpi' { scenario_pci_hotplug_acpi(mut t) }
		'pci-hotplug-iommu' { scenario_pci_hotplug_iommu(mut t) }
		'power-button-init' { scenario_power_button_init(mut t) }
		'qmp-powerdown' { scenario_qmp_powerdown(mut t) }
		'restart' { scenario_restart(mut t) }
		'screen-sleep' { scenario_screen_sleep(mut t) }
		'suspend' { scenario_suspend(mut t) }
		'suspend-deep' { scenario_suspend_deep(mut t) }
		'suspend-deep-arrival' { scenario_suspend_deep_arrival(mut t) }
		'suspend-deep-departure' { scenario_suspend_deep_departure(mut t) }
		'suspend-deep-ec' { scenario_suspend_deep_ec(mut t) }
		'suspend-deep-bridge' { scenario_suspend_deep_bridge(mut t) }
		'suspend-deep-forced' { scenario_suspend_deep_forced(mut t) }
		'suspend-deep-headless' { scenario_suspend_deep_headless(mut t) }
		'suspend-deep-iommu' { scenario_suspend_deep_iommu(mut t) }
		'suspend-deep-iommu-amd' { scenario_suspend_deep_iommu_amd(mut t) }
		'suspend-deep-undrawable' { scenario_suspend_deep_undrawable(mut t) }
		'suspend-deep-wake' { scenario_suspend_deep_wake(mut t) }
		'suspend-deep-wake-off' { scenario_suspend_deep_wake_off(mut t) }
		'suspend-deep-xapic' { scenario_suspend_deep_xapic(mut t) }
		'thermal' { scenario_thermal(mut t) }
		'thermal-selftest' { scenario_thermal_selftest(mut t) }
		else { return false }
	}
	return true
}

fn main() {
	mut t := new_test()
	name := read_word('/etc/hwtest-scenario')
	t.scenario = if name == '' { 'unknown' } else { name }
	t.say('HWTEST START ${t.scenario}')
	if !run_scenario(name, mut t) {
		t.check(false, 'the guest program has no scenario of this name')
	}
	t.finish()
}
