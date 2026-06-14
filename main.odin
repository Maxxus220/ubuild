package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:dynlib"
import "core:strings"
import "core:path/filepath"
import "core:thread"
import "base:runtime"

Script_Api :: struct  {
	lib : dynlib.Library,
	script : proc()
}

main :: proc() {
	defer free_all(context.temp_allocator)

	// thread_pool : thread.Pool
	// thread.pool_init(&thread_pool, context.allocator, thread_count = 4)

	// process_desc := os.Process_Desc{command = {"which", "gcc"}}
	// state, stdout, stderr, proc_err := os.process_exec(process_desc, context.temp_allocator)
	// fmt.printf("%s\n", stdout)

	which_odin_proc_desc := os.Process_Desc{command = {"which", "odin"}}
	state, stdout, stderr, proc_err := os.process_exec(which_odin_proc_desc, context.temp_allocator)
	assert(proc_err == os.General_Error.None, fmt.tprintf("'which odin' failed: %v", proc_err))
	which_odin_stdout_cleaned := strings.trim_space(cast(string)stdout)
	fmt.printf("which odin: %s\n", which_odin_stdout_cleaned)

	abs_odin_filepath, abs_err := filepath.abs(which_odin_stdout_cleaned, context.temp_allocator)
	assert(abs_err == mem.Allocator_Error.None, fmt.tprintf("Failed to get abs path of %s: %v", which_odin_stdout_cleaned, abs_err))
	fmt.printf("abs_odin_filepath: %s\n", abs_odin_filepath)

	odin_build_script_proc_desc := os.Process_Desc{command = {"odin", "build", "script/", "-build-mode:shared"}}
	state, stdout, stderr, proc_err = os.process_exec(odin_build_script_proc_desc, context.temp_allocator)
	assert(proc_err == os.General_Error.None, fmt.tprintf("'odin build script/ -build-mode:shared' failed: %v", proc_err))
	fmt.println("Built 'script.so'")

	script_api := Script_Api{}
	count, load_ok := dynlib.initialize_symbols(&script_api, "./script.so", symbol_prefix = "ubuild_", handle_field_name = "lib")
	assert(load_ok, fmt.tprintf("Failed to initialize script API: %v", dynlib.last_error()))

	script_api.script()
}
