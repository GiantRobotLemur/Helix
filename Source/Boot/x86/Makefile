# Trivial makefile to build and test the boot loader in Bochs

CURRENT_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
OUT_DRIVE := w
OUT_DIR := $(abspath $(CURRENT_DIR)../build)
DOS_OUT_DIR := $(patsubst /cygdrive/$(OUT_DRIVE)/%,$(OUT_DRIVE):/%,$(OUT_DIR))
AS := i686-elf-gcc
CXX := i686-elf-g++
LDXX := i686-elf-g++
ASMFLAGS := -D__ASM__
CPPFLAGS := -I$(CURRENT_DIR)../Include
CFLAGS := -ffreestanding -Wall -Wextra -Wpedantic -Wshadow
CXXFLAGS := -ffreestanding -Wall -Wextra -Wpedantic -Wshadow
LDXXFLAGS := -nostdlib -Wl,-Ttext=0x100000,--oformat=binary

ISO_IMAGE_NAME := $(OUT_DIR)/Helix.iso
DOS_IMAGE_NAME := $(subst $(OUT_DIR),$(DOS_OUT_DIR),$(ISO_IMAGE_NAME))

# Create a bootable ISO image containing the loader.
$(ISO_IMAGE_NAME) : $(OUT_DIR)/IsoImage/Boot.sys
	@echo Creating bootable CD image...
	@mkdir -p $(dir $@)
	@genisoimage -J -r -b Boot.sys \
		-no-emul-boot -boot-info-table -input-charset iso8859-1 \
		-o $@ $(OUT_DIR)/IsoImage

# Create the combined 16/32-bit loader file.
$(OUT_DIR)/IsoImage/Boot.sys : $(OUT_DIR)/Loader16.sys $(OUT_DIR)/Loader32.sys
	@echo Creating $(notdir $@)...
	@mkdir -p $(dir $@)
	@cat $^ > $@

# Assemble the 16-bit portion of the loader.
$(OUT_DIR)/Loader16.sys : Loader16.S Loader_x86.h
	@echo Assembling $< ...
	@mkdir -p $(dir $@)
	@$(AS) $(ASMFLAGS) -nostdlib \
		-Wl,--oformat=binary,-Ttext=0x0000 -o $@ $<

# Assemble the 32-bit entry point to the C++ portion of the loader.
$(OUT_DIR)/Entry32.o : Entry32.S Loader_x86.h
	@echo Assembling $< ...
	@mkdir -p $(dir $@)
	@$(AS) $(ASMFLAGS) -c -o $@ $<

# Compile the 32-bit C++ loader code.
$(OUT_DIR)/Main.o : Main.cpp
	@echo Compiling $< ...
	@mkdir -p $(dir $@)
	@$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

# Link the 32-bit loader.
$(OUT_DIR)/Loader32.sys : $(OUT_DIR)/Entry32.o $(OUT_DIR)/Main.o
	@echo Linking $(notdir $<) ...
	@mkdir -p $(dir $@)
	@$(LDXX) $(LDXXFLAGS) -o $@ $^

clean :
	@echo Removing binaries and intermetdiate files...
	@$(RM) -Rf $(OUT_DIR)

run : $(ISO_IMAGE_NAME) $(CURRENT_DIR)bochsrc
	@echo $(OUT_DOS_DIR)
	@echo Creating bochs configuration...
	@cp $(CURRENT_DIR)bochsrc $(OUT_DIR)/bochsrc

	@echo "ata0-slave: type=cdrom, status=inserted, path=$(DOS_IMAGE_NAME)" >> $(OUT_DIR)/bochsrc
	@echo Running bochs...
	bochs-i686-debugger -f $(DOS_OUT_DIR)/bochsrc -q

# Define utility targets.
all : iso
iso : $(OUT_DIR)/Helix.iso

.PHONY : all iso clean run

.DEFAULT_GOAL : iso