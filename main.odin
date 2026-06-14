package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:dynlib"
import "base:runtime"

Script_Api :: struct  {
	lib : dynlib.Library,
	script : proc()
}

main :: proc() {
	my_arena := mem.Arena{}
	data, alloc_err := mem.new([2048]u8)
	if alloc_err != runtime.Allocator_Error.None {
		fmt.eprintln(alloc_err)
		os.exit(1)
	}
	mem.arena_init(&my_arena, data^[:])
	process_desc := os.Process_Desc{command = {"which", "gcc"}}
	state, stdout, stderr, proc_err := os.process_exec(process_desc, mem.arena_allocator(&my_arena))
	fmt.printf("%s\n", stdout)

	script_api := Script_Api{}
	count, load_ok := dynlib.initialize_symbols(&script_api, "./script.so", symbol_prefix = "ubuild_", handle_field_name = "lib")
	if !load_ok {
		fmt.eprintln(dynlib.last_error())
		os.exit(1)
	}

	script_api.script()
}
