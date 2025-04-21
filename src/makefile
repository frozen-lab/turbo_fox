ASM = nasm
LD = ld
ASMFLAGS = -f elf64
DEBUGFLAGS = -g -F dwarf
TARGET = main
SRC = main.asm
OBJ = main.o

all: clean $(TARGET)

$(TARGET): $(OBJ)
	$(LD) -o $@ $<

$(OBJ): $(SRC)
	$(ASM) $(ASMFLAGS) -o $@ $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJ) $(TARGET)
