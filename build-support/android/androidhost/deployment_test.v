module androidhost

import json2
import os

fn deployment_golden() !map[string]Value {
	return json2.decode[Value](os.read_file(path_join(os.dir(@FILE), 'testdata/deployment.json'))!)!.object()
}

fn test_original_configuration_and_complete_launch_bytes() {
	gold := deployment_golden()!
	scripts := field(gold, 'scripts').object()
	for value in field(gold, 'cases').items() {
		row := value.object()
		fields := field(row, 'fields').object()
		assert deployment_configuration(fields) == field(row, 'configuration').text()
		assert deployment_launch(fields) == field(row, 'launch').text()
		mut names := []string{}
		for launch in deployment_optional(fields).items() {
			item := launch.object()
			name := field(item, 'name').text()
			names << name
			assert field(item, 'script').text() == field(scripts, name).text()
		}
		names.sort()
		assert names == field(row, 'optional').items().map(it.text())
	}
}

fn test_deployment_result_owns_all_transport_input() {
	gold := deployment_golden()!
	for value in field(gold, 'cases').items() {
		row := value.object()
		for operation in ['runner_configuration', 'runner_optional', 'runner_launch'] {
			mut input := encode(Value(map[string]Value{
				'operation':      Value(operation)
				'fields_encoded': pack_string_value(field(row, 'fields'))
			})).bytes()
			borrowed := unsafe { (&u8(input.data)).vstring_with_len(input.len) }
			output := query(borrowed)!
			expected := output.clone()
			for index in 0 .. input.len { input[index] = `x` }
			assert output == expected
			decoded := unpack_string_value(json2.decode[Value](output)!)!
			if operation == 'runner_configuration' {
				assert decoded.text() == field(row, 'configuration').text()
			} else if operation == 'runner_launch' {
				assert decoded.text() == field(row, 'launch').text()
			} else {
				for launch in decoded.items() {
					item := launch.object()
					assert field(item, 'script').text() == field(field(gold, 'scripts').object(), field(item, 'name').text()).text()
				}
			}
		}
	}
}
