package main

import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"

// TODO(mfeist): assert is toggleable. I should switch a lot of my asserts to ensure. I think allocations should just be ensure without a message.
// TODO(mfeist): In the progress of finishing "which" function. Finishing building multi-file program.

which :: proc(target: string, allocator := context.allocator) -> string {
	temp_arena: virtual.Arena
	arena_alloc_err := virtual.arena_init_growing(&temp_arena)
	log.ensure(arena_alloc_err == nil)
	context.allocator = virtual.arena_allocator(&temp_arena)
	defer free_all(context.allocator)

	which_proc_desc := os.Process_Desc {
		command = {"which", target},
	}
	state, stdout, stderr, proc_err := os.process_exec(
		which_proc_desc,
		allocator = context.allocator,
	)
	assert(proc_err == nil, fmt.tprintf("'which gcc' failed: %v", proc_err))
	which_gcc_stdout_cleaned := strings.trim_space(cast(string)stdout)

	temp_abs_gcc_filepath, abs_err := filepath.abs(
		which_gcc_stdout_cleaned,
		context.temp_allocator,
	)
	assert(
		abs_err == nil,
		fmt.tprintf("Failed to get abs path of %s: %v", which_gcc_stdout_cleaned, abs_err),
	)

}
