import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 source := os.read_file(area + '/maintained-third.v')!
 os.write_file(area + '/maintained-fourth.v', source.replace("'/states/m3'", "'/states/m4'"))!
}
