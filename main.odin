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
  * - Figure out how to package Odin
  * - Figure out how we want users to provide tools
  * - Provide a framework for running shell commands in a visible way
  * - Provide a framework for "tasks" that depend on each other and have outputs
 */

Script_Api :: struct {
	lib:    dynlib.Library,
	script: proc() -> string,
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

	// Set up logger
	log_file, log_file_err := os.open("ubuild.log", os.File_Flags{.Create, .Write})
	assert(log_file_err == nil, fmt.tprintf("Failed to open log file: %v", log_file_err))
	console_logger := log.create_console_logger()
	file_logger := log.create_file_logger(log_file)
	multi_logger := log.create_multi_logger(console_logger, file_logger)
	context.logger = multi_logger

	// Arg parsing
	Options :: struct {
		script_path: string `args:"pos=0,required" usage:"Path to the user's script"`,
	}
	cli_opts: Options
	{
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
	}

	// thread_pool : thread.Pool
	// thread.pool_init(&thread_pool, context.allocator, thread_count = 4)

	// process_desc := os.Process_Desc{command = {"which", "gcc"}}
	// state, stdout, stderr, proc_err := os.process_exec(process_desc, context.temp_allocator)
	// fmt.printf("%s\n", stdout)

	// Find odin binary (currently not being used other than printing)
	{
		which_odin_proc_desc := os.Process_Desc {
			command = {"which", "odin"},
		}
		state, stdout, stderr, proc_err := os.process_exec(
			which_odin_proc_desc,
			context.temp_allocator,
		)
		assert(proc_err == nil, fmt.tprintf("'which odin' failed: %v", proc_err))
		which_odin_stdout_cleaned := strings.trim_space(cast(string)stdout)
		log.infof("which odin: %s", which_odin_stdout_cleaned)

		abs_odin_filepath, abs_err := filepath.abs(
			which_odin_stdout_cleaned,
			context.temp_allocator,
		)
		assert(
			abs_err == nil,
			fmt.tprintf("Failed to get abs path of %s: %v", which_odin_stdout_cleaned, abs_err),
		)
		log.infof("abs_odin_filepath: %s", abs_odin_filepath)
	}

	// Build user script into .so
	{
		log.infof("user script file: %s", cli_opts.script_path)
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
		state, stdout, stderr, proc_err := os.process_exec(
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
			log.errorf(
				"'%s' failed with exit-code: %v",
				strings.join(build_user_script_command, " ", context.temp_allocator),
				state.exit_code,
			)
			log.infof("stdout:\n%s", stdout_trimmed)
			log.infof("stderr:\n%s", stderr_trimmed)
			os.exit(1)
		}
		log.info("Built 'script.so'")
	}

	// Load user script
	script_api := Script_Api{}
	{
		count, load_ok := dynlib.initialize_symbols(
			&script_api,
			"./script.so",
			symbol_prefix = "ubuild_",
			handle_field_name = "lib",
		)
		assert(load_ok, fmt.tprintf("Failed to initialize script API: %v", dynlib.last_error()))
	}

	file_to_build := script_api.script()
	log.infof("%s", file_to_build)

	// Find gcc binary
	abs_gcc_filepath: string
	{
		which_gcc_proc_desc := os.Process_Desc {
			command = {"which", "gcc"},
		}
		state, stdout, stderr, proc_err := os.process_exec(
			which_gcc_proc_desc,
			context.temp_allocator,
		)
		assert(proc_err == nil, fmt.tprintf("'which gcc' failed: %v", proc_err))
		which_gcc_stdout_cleaned := strings.trim_space(cast(string)stdout)
		log.infof("which gcc: %s", which_gcc_stdout_cleaned)

		temp_abs_gcc_filepath, abs_err := filepath.abs(
			which_gcc_stdout_cleaned,
			context.temp_allocator,
		)
		assert(
			abs_err == nil,
			fmt.tprintf("Failed to get abs path of %s: %v", which_gcc_stdout_cleaned, abs_err),
		)
		log.infof("abs_gcc_filepath: %s", temp_abs_gcc_filepath)
		abs_gcc_filepath = temp_abs_gcc_filepath
	}

	// Build the file
	{
		log.info(abs_gcc_filepath)
		log.info(file_to_build)
		build_command := os.Process_Desc {
			command = {abs_gcc_filepath, file_to_build},
		}
		build_command_str, join_alloc_err := strings.join(
			build_command.command,
			" ",
			context.temp_allocator,
		)
		assert(
			join_alloc_err == nil,
			fmt.tprintf("Failed to join build command string: %v", join_alloc_err),
		)
		state, stdout, stderr, proc_err := os.process_exec(build_command, context.temp_allocator)
		assert(proc_err == nil, fmt.tprintf("'%s' failed: %v", build_command_str, proc_err))
		log.info("Built the thing")
	}
}
