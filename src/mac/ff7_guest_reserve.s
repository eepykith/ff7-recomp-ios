// Reserve the guest PE image range in the executable itself (Rosetta x86_64 Mac boot).
//
// pcrecomp's pe_loader maps ff7_en.exe with MAP_FIXED at its ImageBase (0x400000,
// SizeOfImage 0xB6F000). With the 0x1000 PAGEZERO that the flat guest needs, the kernel and
// dyld otherwise place the Rosetta runtime, libobjc-trampolines and its .aot image in that
// range before the game thread starts, and MAP_FIXED clobbers them ("rosetta error: invalid
// Mach-O magic"). A zero-fill segment pinned there by `-segaddr __FF7GUEST 0x400000` makes
// the range ours from exec, so the later MAP_FIXED only replaces our own pages.
    .zerofill __FF7GUEST,__image,_ff7_guest_image_reserve,0xB6F000,12
    .globl _ff7_guest_image_reserve
