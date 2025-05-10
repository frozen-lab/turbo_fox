# assembler & linker
ASM        := nasm
LD         := ld

# flags
DEBUGFLAGS := -g -F dwarf
ASMFLAGS   := -f elf64

# output
TARGET     := main

# collect all `asm` files and map them to `object` files
SRCS       := $(wildcard *.asm)
OBJS       := $(SRCS:.asm=.o)

.PHONY: all run clean

# default target
all: $(TARGET)

# link all object files
$(TARGET): $(OBJS)
	$(LD) -o $@ $^

# assemble each `.asm` -> `.o`
%.o: %.asm
	$(ASM) $(ASMFLAGS) -o $@ $<

# build & run
run: all
	./$(TARGET)

# build and run w/ debubg flags
debug: ASMFLAGS += $(DEBUGFLAGS)
debug: clean all
	./$(TARGET)

# cleanup object and binary files
clean:
	rm -f $(OBJS) $(TARGET)
