package script

import "core:fmt"
import "core:path/filepath"
import "ubuild:scripting"

@(export)
ubuild_script :: proc() -> scripting.BuildSpec {
	defer free_all(context.temp_allocator)

	build_spec: scripting.BuildSpec
	source_root, source_alloc_err := filepath.join({#file, ".."}, context.temp_allocator)
	assert(source_alloc_err == nil, fmt.tprintf("Alloc err: %v", source_alloc_err))

	main_file, main_alloc_err := filepath.join({source_root, "main.c"})
	assert(main_alloc_err == nil, fmt.tprintf("Alloc err: %v", main_alloc_err))
	append(&build_spec.tu_build_specs, scripting.TranslationUnitBuildSpec{file_name = main_file})

	foo_file, foo_alloc_err := filepath.join({source_root, "foo.c"})
	assert(foo_alloc_err == nil, fmt.tprintf("Alloc err: %v", foo_alloc_err))
	append(&build_spec.tu_build_specs, scripting.TranslationUnitBuildSpec{file_name = foo_file})

	return build_spec
}
