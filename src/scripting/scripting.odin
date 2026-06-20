package scripting

TranslationUnitBuildSpec :: struct {
	file_name:     string,
	include_paths: [dynamic]string,
}

BuildSpec :: struct {
	tu_build_specs: [dynamic]TranslationUnitBuildSpec,
}
