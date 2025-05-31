## NCKU Compiler-2025 Spring Homework 3: Java Assembly Code Generation Todolist

**Overall Goal:** Extend your compiler from HW2 to generate Jasmin assembly code, compile it to Java bytecode using Jasmin, and ensure it runs correctly on the JVM.

**Submission Deliverables:**

- `compiler.l`
- `compiler.y`
- `compiler_common.h`
- `Makefile`
- Compressed into a single archive named after your student ID.

---

### Phase 1: Setup & Boilerplate Generation

1.  **[ ] Review HW2 Code:**

    - Ensure your `compiler.l` and `compiler.y` from Homework 2 are functional and correctly parse the language.
    - Understand how you currently output the "analysis order" in your semantic actions; this is where you'll now insert Jasmin code generation.

2.  **[ ] Configure Output File:**

    - In your `main` function (or wherever `yyparse()` is called), ensure `yyout` is opened and set to write to `Main.j`.
      ```c
      #include <stdio.h> // Make sure this is included
      // ...
      FILE *yyout; // Declare yyout globally or pass it around
      // ...
      int main(int argc, char **argv) {
          // ...
          yyout = fopen("Main.j", "w");
          if (!yyout) {
              perror("Error opening Main.j");
              return 1;
          }
          // ... Call yyparse()
          fclose(yyout);
          // ...
      }
      ```

3.  **[ ] Implement `CODEGEN` Macro (Optional, but Recommended):**

    - If not already provided, define a macro like this in `compiler_common.h` or directly in `compiler.y` (though `compiler_common.h` is better for consistency):
      ```c
      #define CODEGEN(...) fprintf(yyout, __VA_ARGS__)
      ```

4.  **[ ] Generate Basic Jasmin Boilerplate:**
    - At the very beginning of your code generation process (e.g., at the start of your `program` rule's semantic action in `compiler.y`), output the initial Jasmin header:
      ```
      .source Main.j
      .class public Main
      .super java/lang/Object
      ```
    - At the start of your `main` function generation (e.g., when entering the `main` method scope):
      ```
      .method public static main([Ljava/lang/String;)V
      .limit stack 100     ; Adjust as needed, 100 is a safe start
      .limit locals 100    ; Adjust as needed, 100 is a safe start
      ```
    - At the end of your `main` function generation:
      ```
      return
      .end method
      ```
    - Remember to handle other user-defined methods similarly (see Phase 4).

---

### Phase 2: Expression & Basic Statement Generation

1.  **[ ] Literals:**

    - **Integers:** `ldc <integer_value>` (e.g., `ldc 30`)
    - **Floats:** `ldc <float_value>` (e.g., `ldc 6.28`)
    - **Strings:** `ldc "<string_value>"` (e.g., `ldc "Hello World!\n"`)

2.  **[ ] Unary Operators:**

    - **Negation (`-`):**
      - Generate code for the operand.
      - If integer: `ineg`
      - If float: `fneg`

3.  **[ ] Binary Operators:**

    - For all binary operations: Generate code for the left operand, then the right operand (they will be pushed onto the stack). Then apply the operator instruction.
    - **Arithmetic (Integer):** `iadd`, `isub`, `imul`, `idiv`, `irem`
    - **Arithmetic (Float):** `fadd`, `fsub`, `fmul`, `fdiv` (Note: `irem` not applicable for floats)
    - **Bitwise (Integer):** `iand`, `ior`, `ixor`, `ishl`, `ishr`, `iushr`

4.  **[ ] Variable Declaration & Assignment (`=`):**

    - **Symbol Table Management:** This is CRITICAL.
      - Implement a symbol table (or extend your existing one) to store:
        - Variable name.
        - Its Jasmin local variable _address_ (e.g., `0`, `1`, `2`...).
        - Its _type_ (int, float, string, array, etc.).
      - Keep track of the `next_available_local_address` for the current scope (method).
      - When a new variable is declared, assign it the `next_available_local_address` and increment it.
      - Update the `.limit locals` value for the method based on the maximum address used.
    - **Assignment (`=`):**
      - Generate code for the Right-Hand Side (RHS) expression (pushes its value onto the stack).
      - Load the Jasmin local variable address for the Left-Hand Side (LHS) from your symbol table.
      - Store the value:
        - Integer: `istore <addr>`
        - Float: `fstore <addr>`
        - String/Object: `astore <addr>`

5.  **[ ] Variable Loading (from local to stack):**

    - When a variable is used in an expression:
      - Load its address and type from your symbol table.
      - Load its value onto the stack:
        - Integer: `iload <addr>`
        - Float: `fload <addr>`
        - String/Object: `aload <addr>`

6.  **[ ] `println()` and `print()` Statements:**

    - These follow a standard pattern:
      ```
      getstatic java/lang/System/out Ljava/io/PrintStream;  ; Push PrintStream object onto stack
      ; ... code to generate the argument to print ...     ; Push value to print onto stack
      invokevirtual java/io/PrintStream/println(<sig>)V   ; Call println/print
      ```
    - **Signatures (`<sig>`):**
      - `println(I)V` for integers.
      - `println(F)V` for floats.
      - `println(Ljava/lang/String;)V` for strings.
      - `print` has similar signatures.
    - You'll need type information from your semantic analysis to choose the correct signature.

7.  **[ ] Type Conversions:**
    - When an operation requires operands of the same type, or an assignment needs a type cast:
      - `i2f` (int to float)
      - `f2i` (float to int)
      - `i2l`, `l2i`, etc. (if you support long/double, not explicitly in basic requirement)
    - Insert these instructions as needed in your semantic actions (e.g., `x = x + (int)6.28;` -> `f2i` instruction after `ldc 6.28`).

---

### Phase 3: Control Flow Generation (If/Else)

1.  **[ ] Label Generation:**

    - Implement a counter to generate unique labels for jumps (e.g., `L_X`, `L_Y`, where `X` and `Y` are incrementing numbers).
      ```c
      static int label_counter = 0;
      char label_name[32];
      sprintf(label_name, "L_%d", label_counter++);
      CODEGEN("%s:\n", label_name); // To define a label
      CODEGEN("goto %s\n", label_name); // To jump to a label
      ```

2.  **[ ] Conditional Jumps (`if`):**

    - **Comparison Logic:**
      - For `x == 10`: Generate code for `x`, `ldc 10`, then `isub`. The stack now holds `x - 10`.
      - Then use `ifeq <label>` to jump if `x - 10 == 0`.
    - **Standard Comparisons (`>`, `<`, `>=`, `<=`):**
      - Generate code for both operands (e.g., `op1_code`, `op2_code`).
      - Use `if_icmpeq`, `if_icmpne`, `if_icmplt`, `if_icmple`, `if_icmpgt`, `if_icmpge` to compare the top two stack values and jump.
    - **`if/else` Structure:**
      ```
      ; ... code for condition ...
      ; (e.g., iload 0, ldc 10, isub)
      ifeq L_true_block      ; Or other conditional jump to true block
      ; --- ELSE BLOCK (false) ---
      ; ... code for else block ...
      goto L_exit_if_else    ; Jump past the true block
      L_true_block:
      ; --- IF BLOCK (true) ---
      ; ... code for if block ...
      L_exit_if_else:
      ```
    - Consider generating `iconst_0`/`iconst_1` for boolean results of comparisons if your language uses explicit booleans.

3.  **[ ] Loops (Implicit, using jumps):**
    - While loops, for loops, etc., are implemented using similar jump instructions and labels.
    - Example `while (condition) { body }`:
      ```
      L_loop_start:
      ; ... code for condition ...
      ; (e.g., iload 0, ldc 10, if_icmplt L_loop_end)
      ifeq L_loop_end     ; Or other conditional jump to exit loop if condition is false
      ; --- LOOP BODY ---
      ; ... code for loop body ...
      goto L_loop_start   ; Jump back to check condition
      L_loop_end:
      ```

---

### Phase 4: Function (Method) Generation

1.  **[ ] Function Definition:**

    - For each function (other than `main`):
      ```
      .method public static <method_name>(<signature>)<return_type>
      .limit stack <size>
      .limit locals <size>
      ; ... method body ASM code ...
      <return_instruction>
      .end method
      ```
    - **Signature (`<signature>`):** Define how your language types map to Java JNI types (e.g., `int` -> `I`, `float` -> `F`, `String` -> `Ljava/lang/String;`).
    - **Local Variable Addresses:**
      - Function parameters (arguments) occupy initial local variable addresses starting from `0`.
      - `local 0` for first arg, `local 1` for second, etc.
      - Your custom local variables declared inside the function should start _after_ the parameters. Adjust your `next_available_local_address` accordingly for each function.
    - **Stack/Locals Limits:** Dynamically calculate or use a generous fixed value (e.g., `100`).

2.  **[ ] Function Calls (`invokestatic`):**

    - **Parameter Passing:** Generate code for each argument, pushing them onto the stack in the correct order _before_ the `invokestatic` instruction.
    - **Invocation:**
      ```
      invokestatic Main/<method_name>(<signature>)<return_type>
      ```
    - If the function returns a value, it will be on the stack. Your code should then either pop it (`pop`) if unused, or store it into a variable (`istore`, `fstore`, `astore`).

3.  **[ ] Return Statements:**
    - `ireturn` for integer return types.
    - `freturn` for float return types.
    - `areturn` for object/string return types.
    - `return` for `void` methods (like `main`).
    - Generate code for the return expression first (if any), then the `return` instruction.

---

### Phase 5: Array Generation (if applicable in your language)

1.  **[ ] Array Creation:**

    - `ldc <size>` (push array size)
    - `newarray <type>` (e.g., `newarray int`, `newarray float`, `newarray short` for string, `newarray char` for string if your string is char array)
    - **Initialization (e.g., `[10, 20, 30]`):**
      - `dup` (duplicate array ref on stack)
      - `ldc <index>` (push index)
      - `ldc <value>` (push value)
      - `iastore` (store int value into array at index)
      - Repeat `dup`, `ldc <index>`, `ldc <value>`, `iastore` for each element.
    - Finally, `astore <addr>` to store the array reference into a local variable.

2.  **[ ] Array Element Load (`a[index]` for reading):**

    - Generate code to load the array reference onto the stack (e.g., `aload <array_addr>`).
    - Generate code for the index expression (e.g., `ldc 0`).
    - `iaload` (for int), `faload` (for float), `aaload` (for object/string).

3.  **[ ] Array Element Store (`a[index] = value` for writing):**
    - Generate code to load the array reference onto the stack (e.g., `aload <array_addr>`).
    - Generate code for the index expression (e.g., `ldc 0`).
    - Generate code for the value to store (e.g., `ldc 10`).
    - `iastore` (for int), `fastore` (for float), `aastore` (for object/string).

---

### Phase 6: Testing & Debugging

1.  **[ ] `Makefile` Integration:**

    - Update your `Makefile` to include the Jasmin assembly step.
    - Typical flow:
      - Your compiler (`./compiler`) generates `Main.j`.
      - Jasmin (`java -jar jasmin.jar Main.j`) generates `Main.class`.
      - JVM (`java Main`) executes the bytecode.
    - Example `Makefile` snippet (adjust paths as needed):

      ```makefile
      JASMIN_JAR = /path/to/jasmin.jar # Or put it in the same directory
      BUILD_DIR = ./build/out

      .PHONY: all clean run

      all: $(BUILD_DIR)/Main.class

      $(BUILD_DIR)/Main.class: Main.j
          mkdir -p $(BUILD_DIR)
          java -jar $(JASMIN_JAR) -d $(BUILD_DIR) Main.j

      Main.j: compiler.l compiler.y compiler_common.h
          # Assuming your compiler executable is named 'compiler'
          ./compiler < input.your_lang > Main.j

      run: $(BUILD_DIR)/Main.class
          java -cp $(BUILD_DIR) Main

      clean:
          rm -f Main.j $(BUILD_DIR)/*.class $(BUILD_DIR)/*.j *~
          rm -rf $(BUILD_DIR) # Only if build_dir only contains compiled output
          rm -f compiler # Your compiler executable
      ```

2.  **[ ] Use `javap` for Debugging:**

    - `javac Main.java && javap -c -v Main` to see how Java's own compiler translates your code. This is an invaluable reference.
    - `javap -c -v ./build/out/Main.class` to inspect the bytecode _your_ compiler generated. Compare it with the `javac` output.

3.  **[ ] Incremental Testing:**
    - Start with simple programs (e.g., `println(10);`).
    - Add variables (`x = 5; println(x);`).
    - Add operators (`println(x + 3 * 2);`).
    - Add control flow (`if`).
    - Add functions.
    - Add arrays.
    - Test each new feature thoroughly.

---

### Phase 7: Final Review & Submission

1.  **[ ] Code Review:**

    - Ensure your `compiler.l`, `compiler.y`, `compiler_common.h`, and `Makefile` are clean, well-commented, and free of unnecessary debug prints (except for `yyout`).
    - Verify `limit stack` and `limit locals` values are sufficient for your test cases.

2.  **[ ] Final Testing:**

    - Run all provided test cases (if any) or create comprehensive ones.
    - Ensure the output matches the expected behavior on JVM.

3.  **[ ] Create Submission Archive:**
    - Compress `compiler.l`, `compiler.y`, `compiler_common.h`, `Makefile` into a single zip/tar.gz file named after your student ID.
    - Double-check that _only_ these files are included and the name is correct.
