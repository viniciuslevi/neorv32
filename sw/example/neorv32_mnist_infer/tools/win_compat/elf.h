// Minimal <elf.h> for building sw/image_gen/image_gen.c on Windows.
// MinGW ships no <elf.h>; image_gen only needs the ELF32 file/section header
// layouts and the magic number (see the ELF specification, "Data Representation").
// Only used when the makefile is run on Windows (see ../makefile).
#ifndef WIN_COMPAT_ELF_H
#define WIN_COMPAT_ELF_H

#include <stdint.h>

#define ELFMAG  "\177ELF"
#define SELFMAG 4
#define EI_NIDENT 16

typedef struct {
  unsigned char e_ident[EI_NIDENT];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint32_t e_entry;
  uint32_t e_phoff;
  uint32_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} Elf32_Ehdr;

typedef struct {
  uint32_t sh_name;
  uint32_t sh_type;
  uint32_t sh_flags;
  uint32_t sh_addr;
  uint32_t sh_offset;
  uint32_t sh_size;
  uint32_t sh_link;
  uint32_t sh_info;
  uint32_t sh_addralign;
  uint32_t sh_entsize;
} Elf32_Shdr;

#endif
