package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:dynlib"
import "core:strings"
import "core:path/filepath"
import "base:runtime"

Script_Api :: struct  {
	lib : dynlib.Library,
	script : proc()
}

main :: proc() {
	my_arena := mem.Arena{}
	data, alloc_err := mem.new([2048]u8)
	assert(alloc_err == .None, fmt.aprintf("Failed to alloc arena memory: %v", alloc_err))
	mem.arena_init(&my_arena, data^[:])

	// process_desc := os.Process_Desc{command = {"which", "gcc"}}
	// state, stdout, stderr, proc_err := os.process_exec(process_desc, mem.arena_allocator(&my_arena))
	// fmt.printf("%s\n", stdout)

	which_odin_proc_desc := os.Process_Desc{command = {"which", "odin"}}
	state, stdout, stderr, proc_err := os.process_exec(which_odin_proc_desc, mem.arena_allocator(&my_arena))
	assert(proc_err == os.General_Error.None, fmt.aprintf("'which odin' failed: %v", proc_err))
	which_odin_stdout_cleaned := strings.trim_space(cast(string)stdout)
	fmt.printf("which odin: %s\n", which_odin_stdout_cleaned)

	abs_odin_filepath, abs_err := filepath.abs(which_odin_stdout_cleaned)
	assert(abs_err == mem.Allocator_Error.None, fmt.aprintf("Failed to get abs path of %s: %v", which_odin_stdout_cleaned, abs_err))
	fmt.printf("abs_odin_filepath: %s\n", abs_odin_filepath)

	odin_build_script_proc_desc := os.Process_Desc{command = {"odin", "build", "script/", "-build-mode:shared"}}
	state, stdout, stderr, proc_err = os.process_exec(odin_build_script_proc_desc, mem.arena_allocator(&my_arena))
	assert(proc_err == os.General_Error.None, fmt.aprintf("'odin build script/ -build-mode:shared' failed: %v", proc_err))
	fmt.println("Built 'script.so'")

	script_api := Script_Api{}
	count, load_ok := dynlib.initialize_symbols(&script_api, "./script.so", symbol_prefix = "ubuild_", handle_field_name = "lib")
	assert(load_ok, fmt.aprintf("Failed to initialize script API: %v", dynlib.last_error()))

	script_api.script()
}
