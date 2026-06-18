package script

import "core:fmt"

@(export)
ubuild_script :: proc() -> string {
	fmt.println("Hello script! REMIX2...")
	return "main.c"
}
