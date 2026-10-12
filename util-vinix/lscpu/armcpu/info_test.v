module armcpu

fn test_vinix_cpuinfo_and_raw_ids() {
	info := parse('processor\t: 0\nBogoMIPS\t: 100.00\nFeatures\t: fp asimd aes\nCPU implementer\t: 0x61\nCPU architecture: 8\nCPU variant\t: 0x0\nCPU part\t: 0x000\nCPU revision\t: 0\n\n')!
	assert info.cpu_count == 1
	assert info.flags == ['aes', 'asimd', 'fp']
	assert info.has_features
	assert info.implementers == ['0x61']
	assert info.parts == ['0x000']
	assert info.text().contains('CPU Count:        1\n')
	assert info.text().contains('CPU part:         0x000\n')
	assert !info.text().contains('Model name:')
}

fn test_heterogeneous_processors_only_report_common_features() {
	info := parse('processor : 0\nFeatures : fp aes fp asimd\nCPU part : 0xd03\n \nprocessor : 4\nFeatures : fp\tasimd crc32\nCPU part : 0xd07\n\nHardware : Example board\n')!
	assert info.cpu_count == 2
	assert info.flags == ['asimd', 'fp']
	assert info.parts == ['0xd03', '0xd07']
	assert info.implementers == ['Unknown']
}

fn test_missing_cpu_fields_are_unknown() {
	info := parse('processor: 0\nFeatures: fp asimd\nCPU implementer: 0x41\n\nprocessor: 1\n')!
	assert !info.has_features
	assert info.flags == []string{}
	assert info.implementers == ['0x41', 'Unknown']
	assert info.text().ends_with('Flags:            Unknown')
}

fn test_malformed_and_duplicate_processor_records_fail() {
	for text in ['', 'Hardware: Board', 'processor: -1', 'processor: abc',
		'processor: 99999999999999999999999999999999', 'processor: 0\nprocessor: 1',
		'processor: 1\n\nprocessor: 01', 'processor: 0\nFeatures: fp\nFeatures: asimd'] {
		if _ := parse(text) {
			assert false, 'accepted invalid CPU information: ' + text
		}
	}
}
