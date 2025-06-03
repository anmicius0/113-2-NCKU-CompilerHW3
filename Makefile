CC := gcc
CFLAGS := -Wall -O0 -ggdb
YFLAG := -d -v # -d generates y.tab.h, -v generates y.output
LEX_SRC := compiler.l
YAC_SRC := compiler.y
HEADER := compiler_common.h
COMPILER := mycompiler

# Updated and New Variables
JAVABYTECODE := Main.j # Changed from hw3.j
JASMIN_JAR := ./jasmin.jar # Added
BUILD_DIR := build # Added
INPUT_FILE ?= input/a00_helloWorld_comment.rs # Added default input, can be overridden

EXEC := Main # Main class name
v := 0

.PHONY: all clean run judge

all: $(BUILD_DIR)/$(EXEC).class # Changed target

# Rule for building the compiler
$(COMPILER): lex.yy.c y.tab.c $(HEADER) # Added HEADER dependency
	$(CC) $(CFLAGS) -o $@ lex.yy.c y.tab.c # Explicitly list sources

lex.yy.c: $(LEX_SRC) $(HEADER) y.tab.h # Added y.tab.h dependency
	lex $<

y.tab.c y.tab.h: $(YAC_SRC) $(HEADER) # y.tab.h is a co-product
	yacc $(YFLAG) $<

# Rule for generating Main.j from the compiler
$(JAVABYTECODE): $(COMPILER) $(INPUT_FILE) $(LEX_SRC) $(YAC_SRC) $(HEADER)
	./$(COMPILER) $(INPUT_FILE) # Compiler now writes to Main.j directly

# Rule for compiling Main.j to Main.class using Jasmin
$(BUILD_DIR)/$(EXEC).class: $(JAVABYTECODE) $(JASMIN_JAR)
	mkdir -p $(BUILD_DIR)
	java -jar $(JASMIN_JAR) -d $(BUILD_DIR) $(JAVABYTECODE)

# Rule for running the compiled Java code
run: $(BUILD_DIR)/$(EXEC).class
	java -cp $(BUILD_DIR) $(EXEC)

# Judge target (remains mostly the same, depends on 'all')
judge: all
	@judge -v ${v}

# Clean target
clean:
	rm -f $(COMPILER) y.tab.c y.tab.h lex.yy.c y.output # Source generation files
	rm -f $(JAVABYTECODE) # Generated Jasmin file
	rm -rf $(BUILD_DIR) # Build directory and its contents (Main.class)
	rm -f *.j # Remove any other .j files in root, just in case
	rm -f *.class # Remove any .class files in root
