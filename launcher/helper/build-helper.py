"""Build the tiny Windows x64 helper using GCC and GNU binutils in WSL/Linux."""
from collections import defaultdict
from pathlib import Path
from struct import pack_into, unpack_from
from subprocess import run
from tempfile import TemporaryDirectory
import re

SOURCE = Path(__file__).resolve().parent / "restart.c"
OUTPUT = SOURCE.parent.parent / "app/restart_helper.bin"


def command(*args):
    return run(args, check=True, capture_output=True, text=True).stdout


def fix_coff_relocations(elf, coff):
    # GNU objcopy translates the symbols but emits ADDR32 for ELF PC32.
    # Windows REL32 is relative to the end of a four-byte operand.
    relocations = defaultdict(dict)
    sections = set(re.findall(r"^\s*\d+\s+(\.\S+)\s+", command("objdump", "-h", str(elf)), re.M))
    section_symbols = {}
    for line in command("objdump", "-r", str(elf)).splitlines():
        section = re.match(r"RELOCATION RECORDS FOR \[(.+)\]:", line)
        if section:
            section_name = section[1]
        entry = re.match(r"([0-9a-f]+)\s+(R_X86_64_\w+)\s+(\S+)", line)
        if entry:
            assert entry[2] in ("R_X86_64_PC32", "R_X86_64_PLT32"), entry[2]
            tail = re.search(r"([+-])0x([0-9a-f]+)$", entry[3])
            addend = int(tail[2], 16) * (-1 if tail[1] == "-" else 1) if tail else 0
            target = entry[3].split("+", 1)[0].split("-", 1)[0]
            if target in sections:
                section_symbols.setdefault(target, f"rb{len(section_symbols)}")
            relocations[section_name][int(entry[1], 16)] = (target, addend)

    # BFD loses references to ELF section symbols when converting to COFF.
    # Give each referenced section a fresh local symbol at offset zero.
    if section_symbols:
        options = [f"--add-symbol={symbol}={section}:0,local" for section, symbol in section_symbols.items()]
        command("objcopy", *options, str(coff))
    data = bytearray(coff.read_bytes())
    _, count, _, symbol_offset, symbol_count, optional_size, _ = unpack_from("<HHIIIHH", data)
    indices = {}
    index = 0
    while index < symbol_count:
        symbol = symbol_offset + 18 * index
        name = data[symbol:symbol + 8].split(b"\0", 1)[0].decode("ascii", "ignore")
        indices[name] = index
        index += 1 + data[symbol + 17]
    strings = symbol_offset + 18 * symbol_count
    for index in range(count):
        header = 20 + optional_size + index * 40
        name = data[header:header + 8].split(b"\0", 1)[0]
        if name.startswith(b"/"):
            start = strings + int(name[1:])
            name = data[start:data.index(0, start)]
        raw, entries, _, count_entries = unpack_from("<IIIH", data, header + 20)
        for index_in_section in range(count_entries):
            entry_offset = entries + index_in_section * 10
            offset, index, _ = unpack_from("<IIH", data, entry_offset)
            target, addend = relocations[name.decode()].pop(offset)
            if target in section_symbols:
                index = indices[section_symbols[target]]
            pack_into("<IH", data, entry_offset + 4, index, 4)  # IMAGE_REL_AMD64_REL32
            pack_into("<i", data, raw + offset, addend + 4)
    assert all(not entries for entries in relocations.values())
    coff.write_bytes(data)


def build():
    groups = defaultdict(list)
    for library, name in re.findall(r"^API\((\w+), [^,]+, (\w+),", SOURCE.read_text(), re.M):
        groups[library].append(name)
    with TemporaryDirectory() as directory:
        work = Path(directory)
        libraries = []
        for library, names in groups.items():
            # The linker generates a normal import library from a synthetic DLL.
            # The DLL is never distributed or used. Windows supplies the real one.
            assembly = work / "imports.s"
            assembly.write_text(".text\n" + "".join(f".global {name}\n{name}: ret\n" for name in names))
            definition = work / "imports.def"
            definition.write_text(f"LIBRARY {library.upper()}.dll\nEXPORTS\n" + "\n".join(names) + "\n")
            command("as", "--64", str(assembly), "-o", str(work / "imports.elf"))
            command("objcopy", "-O", "pe-x86-64", str(work / "imports.elf"), str(work / "imports.obj"))
            archive = work / f"{library}.a"
            command("ld", "-mi386pep", "--shared", "--out-implib", str(archive), "-o",
                    str(work / "stub.dll"), str(work / "imports.obj"), str(definition))
            libraries.append(str(archive))
        elf = work / "restart.elf"
        coff = work / "restart.obj"
        command("gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Os", "-mabi=ms",
                "-mno-red-zone", "-fshort-wchar", "-ffreestanding", "-fpie", "-fno-asynchronous-unwind-tables",
                "-fno-stack-protector", "-fno-stack-clash-protection", "-fcf-protection=none", "-fno-ident", "-c", str(SOURCE), "-o", str(elf))
        command("objcopy", "-O", "pe-x86-64", str(elf), str(coff))
        fix_coff_relocations(elf, coff)
        command("ld", "-mi386pep", "--subsystem", "windows", "--entry", "restart_entry",
                "--dynamicbase", "--nxcompat", "--no-insert-timestamp", "-s", "-o", str(OUTPUT), str(coff), *libraries)
        print(f"Built {OUTPUT.name} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    build()
