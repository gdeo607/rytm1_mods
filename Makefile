# Analog Rytm MK1 firmware mods (ported from the MKII project, rytm-mods).
# Build and verify use only the Python standard library; python3 >= 3.11.
PY := python3

.PHONY: all setup symbols layout build verify control disasm clean

all: verify

# The container tool, pinned to the commit the MKII project verified against, plus
# one local patch: ELE2 containers are padded to 4 bytes, as the stock MK1 file is
# (the tool pads to 2). With it, rebuilding the untouched stock .syx reproduces it
# byte for byte, which `make verify` asserts.
EFT_URL := https://github.com/mischa85/elektron-firmware-tool
EFT_REV := a5bce9a6af644386d900924082993a805e812874
EFT_DIR := vendor/elektron-firmware-tool

setup:
	test -d $(EFT_DIR)/.git || git clone $(EFT_URL) $(EFT_DIR)
	git -C $(EFT_DIR) checkout --quiet $(EFT_REV)
	git -C $(EFT_DIR) apply --check ../../tools/eft-ele2-align4.patch 2>/dev/null \
		&& git -C $(EFT_DIR) apply ../../tools/eft-ele2-align4.patch || true
	grep -q "stock pads to 4" $(EFT_DIR)/container.c
	$(MAKE) -C $(EFT_DIR)

symbols:
	$(PY) tools/symbols.py

layout:
	$(PY) tools/layout.py

build: symbols layout
	$(PY) tools/gen_cut_tables.py --check
	$(PY) tools/build.py

verify: build
	$(PY) tools/verify.py $(if $(TAG),--tag $(TAG),)

# The pipeline test: no mods at all, stock MAIN OS recompressed by our tool.
control: symbols layout
	$(PY) tools/build.py --mods --tag control
	$(PY) tools/verify.py --tag control

# Whole-image disassembly with EMAC decoding.
MAINOS_BASE := 0x40000400
disasm: build
	printf '\t.section .archtag,"a"\n\tmovclr.l %%acc0,%%d0\n\t.text\n\t.incbin "build/stock_mainos.bin"\n' \
		> build/mainos_wrap.s
	$$($(PY) -c 'import sys; sys.path.insert(0,"tools"); from toolchain import prefix; print(prefix())')as \
		-mcpu=5475 build/mainos_wrap.s -o build/mainos_wrap.o
	$$($(PY) -c 'import sys; sys.path.insert(0,"tools"); from toolchain import prefix; print(prefix())')objdump \
		-d -j .text --adjust-vma=$(MAINOS_BASE) build/mainos_wrap.o | sed 's/^ *//' > build/mainos_emac.dis

clean:
	rm -rf build
