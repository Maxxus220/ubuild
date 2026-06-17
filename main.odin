package main

import "base:runtime"
import "core:dynlib"
import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:thread"

/**
  * TODO-LIST
  * - Specify what script provides to build tool
  * - Give user utilities to build C/C++
  *   - Build something (0->100)
  * - Figure out how to package Odin
  * - Figure out how we want users to provide tools
  * - Provide a framework for running shell commands in a visible way
  * - Provide a framework for "tasks" that depend on each other and have outputs
 */

Script_Api :: struct {
	lib:    dynlib.Library,
	script: proc(),
}

custom_flag_checker :: proc(
	model: rawptr,
	name: string,
	value: any,
	args_tag: string,
) -> (
	error: string,
) {
	if name == "script_path" {
		script_path := value.(string)
		if !os.exists(script_path) {
			return fmt.aprintf(
				"Path '%s' was passed as 'script_path' but does not exist.",
				script_path,
			)
		}
		if !os.is_file(script_path) {
			return fmt.aprintf(
				"Path '%s' was passed as 'script_path' but is not a regular file.",
				script_path,
			)
		}
	}
	return
}

main :: proc() {
	defer free_all(context.temp_allocator)

	// Arg parsing
	Options :: struct {
		script_path: string `args:"pos=0,required" usage:"Path to the user's script"`,
	}
	cli_opts: Options
	flags.register_flag_checker(custom_flag_checker)
	parse_err := flags.parse(&cli_opts, os.args[1:])
	if parse_err != nil {
		_, is_help := parse_err.(flags.Help_Request)
		flags.print_errors(typeid_of(Options), parse_err, os.args[0])
		if is_help {
			os.exit(0)
		} else {
			flags.print_errors(Options, flags.Help_Request{}, os.args[0])
			os.exit(1)
		}
	}

	fmt.printf("%#v\n", cli_opts)

	// thread_pool : thread.Pool
	// thread.pool_init(&thread_pool, context.allocator, thread_count = 4)

	// process_desc := os.Process_Desc{command = {"which", "gcc"}}
	// state, stdout, stderr, proc_err := os.process_exec(process_desc, context.temp_allocator)
	// fmt.printf("%s\n", stdout)

	// Find odin binary
	which_odin_proc_desc := os.Process_Desc {
		command = {"which", "odin"},
	}
	state, stdout, stderr, proc_err := os.process_exec(
		which_odin_proc_desc,
		context.temp_allocator,
	)
	assert(proc_err == os.General_Error.None, fmt.tprintf("'which odin' failed: %v", proc_err))
	which_odin_stdout_cleaned := strings.trim_space(cast(string)stdout)
	fmt.printf("which odin: %s\n", which_odin_stdout_cleaned)

	abs_odin_filepath, abs_err := filepath.abs(which_odin_stdout_cleaned, context.temp_allocator)
	assert(
		abs_err == mem.Allocator_Error.None,
		fmt.tprintf("Failed to get abs path of %s: %v", which_odin_stdout_cleaned, abs_err),
	)
	fmt.printf("abs_odin_filepath: %s\n", abs_odin_filepath)

	// Build user script into .so
	fmt.printf("user script file: %s\n", cli_opts.script_path)
	build_user_script_command: []string = {
		"odin",
		"build",
		cli_opts.script_path,
		"-file",
		"-build-mode:shared",
		"-out:script.so",
	}
	odin_build_script_proc_desc := os.Process_Desc {
		command = build_user_script_command,
	}
	state, stdout, stderr, proc_err = os.process_exec(
		odin_build_script_proc_desc,
		context.temp_allocator,
	)
	assert(
		proc_err == nil,
		fmt.tprintf(
			"Error while running '%s': %v\n",
			strings.join(build_user_script_command, " ", context.temp_allocator),
			proc_err,
		),
	)
	if state.exit_code != 0 {
		stdout_trimmed := strings.trim_space(cast(string)stdout)
		stderr_trimmed := strings.trim_space(cast(string)stderr)
		fmt.printf(
			"'%s' failed with exit-code: %v\n",
			strings.join(build_user_script_command, " ", context.temp_allocator),
			state.exit_code,
		)
		fmt.printf("stdout:\n%s\n", stdout_trimmed)
		fmt.printf("stderr:\n%s\n", stderr_trimmed)
		os.exit(1)
	}
	fmt.println("Built 'script.so'")

	// Load user script
	script_api := Script_Api{}
	count, load_ok := dynlib.initialize_symbols(
		&script_api,
		"./script.so",
		symbol_prefix = "ubuild_",
		handle_field_name = "lib",
	)
	assert(load_ok, fmt.tprintf("Failed to initialize script API: %v", dynlib.last_error()))

	script_api.script()
}
