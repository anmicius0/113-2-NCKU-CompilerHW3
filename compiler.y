/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h"
    // #define YYDEBUG 1
    // int yydebug = 1;

    #define LABEL_BUF_SIZE 32 // Added for label string buffers

    static char current_processing_func_name[LABEL_BUF_SIZE]; // Added for RETURN statement context

    // Globals for array initialization workaround
    #define MAX_ARRAY_INIT_SIZE 50 // Max number of literal initializers for an array
    typedef struct {
        // For now, only int literals. Extend if float/string literals in array init are supported.
        int val_int;
    } LiteralValue;
    static LiteralValue g_array_init_values[MAX_ARRAY_INIT_SIZE];
    static int g_array_init_count = 0;
    static bool g_is_array_init = false;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;
    FILE *yyout; // Added yyout

    int yylex_destroy ();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno, s);
    }

    /* Symbol table function - you can add new functions if needed. */
    // Global variable to track the current scope level
    static int current_scope_level = 0;
    // To store the line number of the 'main' function for the final symbol table dump
    static int main_func_lineno = 0;

    static void create_sym_table();
    static void insert_sym_entry(const char* name, int addr, int scope_level, int lineno);
    static void dump_sym_table(int scope_level);
    extern int lookup_addr(const char *name);
    extern char *lookup_type(const char *name);
    static int lookup_symbol_index(const char *name); // Added

    /* Global variables */
    bool HAS_ERROR = false;
    static int next_addr = 0;
    static int label_counter = 0; // Added label_counter

    // Helper macro for generating new labels
    #define NEW_LABEL(buf) sprintf(buf, "L%d", label_counter++)

    /* Symbol table storage */
    #define MAX_SYM 100
    static char* sym_names[MAX_SYM];
    static char* sym_types[MAX_SYM];
    static char* sym_funcsig[MAX_SYM];
    static int sym_addrs[MAX_SYM];
    static int sym_scopes[MAX_SYM];
    static int sym_linenos[MAX_SYM];
    static int sym_mut[MAX_SYM]; // Added for mutability
    static char* sym_element_types[MAX_SYM]; // Added for array element types
    static int sym_count = 0;
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    int i_val;
    float f_val;
    char *s_val;
    /* ... */
}
%type <s_val> Expr
%type <s_val> IfCondAction TrueBlockAndPassLabel ElseMidAction // For If Stmt
%type <s_val> WhileStart WhileCond // For While Stmt
%type <s_val> ExprOpt ExprList ExprListOpt // For Function Calls / Returns

/* Token without return */
%token LET MUT NEWLINE
%token INT FLOAT BOOL STR
%token TRUE FALSE
%token GEQ LEQ EQL NEQ LOR LAND
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%token IF ELSE FOR WHILE LOOP
%token PRINT PRINTLN
%token FUNC RETURN BREAK
%token ARROW AS IN DOTDOT RSHIFT LSHIFT

%left LOR
%left LAND
%left '>' '<' GEQ LEQ EQL NEQ
%left '+' '-'
%left '*' '/' '%'
%right '!' UMINUS

/* Token with return, which need to sepcify type */
%token <i_val> INT_LIT
%token <f_val> FLOAT_LIT
%token <s_val> STRING_LIT 
%token <s_val> IDENT 
%token '"'           

/* Nonterminal with return, which need to sepcify type */
/* %type <s_val> Type */

/* Yacc will start at this nonterminal */
%start Program

/* Grammar section */
%%

Program
    : GlobalStatementList
      {
        CODEGEN(".source Main.j\n");
        CODEGEN(".class public Main\n");
        CODEGEN(".super java/lang/Object\n");
        CODEGEN("\n");
        dump_sym_table(0); /* Dump global symbol table at the end */
      }
;

GlobalStatementList 
    : GlobalStatementList GlobalStatement
    | GlobalStatement
;

GlobalStatement
    : FunctionDeclStmt
    | NEWLINE
;

FunctionDeclStmt
    : FUNC IDENT '(' ')' { 
        // printf("func: %s\n", $2); // Original printf
        insert_sym_entry($2, -1, 0, yylineno); // Insert first to allow lookup
        sym_names[sym_count] = strdup($2); // TODO: This direct manipulation of sym_table is risky if insert_sym_entry does it too.
        sym_addrs[sym_count] = -1;
        sym_scopes[sym_count] = 0;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "func"; // Mark as function type

        // IMPORTANT: For this phase, assume sym_funcsig is set correctly by grammar if language supports it.
        // If grammar is just FUNC IDENT '()', then sym_funcsig needs a default or simple logic.
        // The provided compiler.y sets it to "(V)V", so we'll use that as a basis.
        // If your language was e.g. `fn foo() -> i32`, the rule for `-> i32` should update sym_funcsig.
        // For now, let's assume it's already "(V)V" or similar from symbol insertion logic.
        // If not set by a more specific rule, default it here:
        if (sym_funcsig[sym_count] == NULL) { // If not set by more specific grammar rules
             sym_funcsig[sym_count] = strdup("(V)V"); // Default for FUNC IDENT '()'
        }
        // sym_funcsig[sym_count] = "(V)V"; // This was the original line. We need it to be dynamic based on grammar.

        char func_name_str[LABEL_BUF_SIZE];
        strncpy(func_name_str, $2, LABEL_BUF_SIZE - 1);
        func_name_str[LABEL_BUF_SIZE - 1] = '\0';

        strncpy(current_processing_func_name, func_name_str, LABEL_BUF_SIZE - 1);
        current_processing_func_name[LABEL_BUF_SIZE - 1] = '\0';

        if (strcmp(func_name_str, "main") == 0) {
            main_func_lineno = yylineno; // Already done or can be here
            CODEGEN("\n.method public static main([Ljava/lang/String;)V\n");
            // Limits for main were set in Phase 1. If they need adjustment based on locals, that's a later refinement.
        } else {
            char param_sig_jasmin[LABEL_BUF_SIZE] = "";
            char return_sig_jasmin[LABEL_BUF_SIZE] = "V";

            int func_idx = lookup_symbol_index(func_name_str); // Should find the one just inserted/updated
            if (func_idx != -1 && sym_funcsig[func_idx] != NULL) {
                const char* sig = sym_funcsig[func_idx];
                if (strlen(sig) >= 3 && sig[0] == '(') {
                    const char* closing_paren = strchr(sig, ')');
                    if (closing_paren != NULL ) { // Closing paren must exist
                        if (closing_paren > sig + 1) { // Params exist
                            strncpy(param_sig_jasmin, sig + 1, closing_paren - (sig + 1));
                            param_sig_jasmin[closing_paren - (sig + 1)] = '\0';
                        } else {
                            param_sig_jasmin[0] = '\0'; // No params "()"
                        }
                        if (*(closing_paren + 1) != '\0') {
                            strncpy(return_sig_jasmin, closing_paren + 1, LABEL_BUF_SIZE - 1);
                            return_sig_jasmin[LABEL_BUF_SIZE - 1] = '\0';
                        }
                    }
                }
            }
            CODEGEN("\n.method public static %s(%s)%s\n", func_name_str, param_sig_jasmin, return_sig_jasmin);
        }

        // For ALL functions (main and others), limits should be set.
        // Let's ensure main's limits from phase 1 are not overwritten if they were specific.
        // Or, unify limit setting here. For now, Phase 1 sets main, this sets others.
        // `next_addr` should be max number of local vars used.
        if (strcmp(func_name_str, "main") != 0) { // main's limits are supposedly handled by Phase 1
           CODEGEN(".limit stack 100\n");   // Placeholder
           CODEGEN(".limit locals 100\n");  // Placeholder, should be num_params + declared_locals
        }
        CODEGEN("\n"); // Blank line after method signature and limits

        sym_count++; // Increment after all fields for current symbol are set.
        current_scope_level++;   
        next_addr = 0; // Reset for new scope (params are locals at index 0, 1, ...)
        create_sym_table(); // For the new scope
    } Block {
        char func_name_end_str[LABEL_BUF_SIZE];
        strncpy(func_name_end_str, $2, LABEL_BUF_SIZE - 1);
        func_name_end_str[LABEL_BUF_SIZE-1] = '\0';

        int func_idx_end = lookup_symbol_index(func_name_end_str);
        char actual_return_char = 'V';
        if (func_idx_end != -1 && sym_funcsig[func_idx_end] != NULL) {
            const char* sig = sym_funcsig[func_idx_end];
            const char* closing_paren = strchr(sig, ')');
            if (closing_paren != NULL && *(closing_paren + 1) != '\0') {
                actual_return_char = *(closing_paren + 1);
            }
        }

        // Implicit return based on function signature if no explicit return hit last.
        // This logic might be too simple if the last generated bytecode was already a return.
        // For now, it adds a return based on the function's declared type.
        if (actual_return_char == 'I') CODEGEN("iconst_0\nireturn\n"); // Return default 0 for int if no explicit return
        else if (actual_return_char == 'F') CODEGEN("fconst_0\nfreturn\n"); // Return default 0.0 for float
        else if (actual_return_char == 'L') CODEGEN("aconst_null\nareturn\n"); // Return default null for String/Object
        else CODEGEN("return\n"); // Handles 'V' (void)

        CODEGEN(".end method\n\n");

        dump_sym_table(current_scope_level); 
        current_scope_level--;
        current_processing_func_name[0] = '\0'; // Clear current function name
    }
;

Block
    : '{' StmtList '}'
;

StmtList
    : StmtList Stmt
    | Stmt
;

Stmt
    : LET IDENT ':' INT '=' Expr ';' {
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "i32"; // Corrected type
        sym_mut[sym_count] = 0;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("istore %d\n", lookup_addr($2));
    }
    | LET IDENT ':' FLOAT '=' Expr ';' {
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "f32"; // Corrected type
        sym_mut[sym_count] = 0;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("fstore %d\n", lookup_addr($2));
    }
    | LET IDENT ':' BOOL '=' Expr ';' {
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "bool";
        sym_mut[sym_count] = 0;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("istore %d\n", lookup_addr($2)); // bool stored as int
    }
    | LET IDENT ':' STR '=' Expr ';' {
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "str";
        sym_mut[sym_count] = 0;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("astore %d\n", lookup_addr($2));
    }
    | LET IDENT ':' '&' STR '=' Expr ';' {
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "str";
        sym_mut[sym_count] = 0;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("astore %d\n", lookup_addr($2)); // Assuming '&' STR is still a string ref
    }
    | LET MUT IDENT ':' INT '=' Expr ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "i32"; // Corrected type
        sym_mut[sym_count] = 1;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("istore %d\n", lookup_addr($3));
    }
    | LET MUT IDENT ':' FLOAT '=' Expr ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "f32"; // Corrected type
        sym_mut[sym_count] = 1;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("fstore %d\n", lookup_addr($3));
    }
    | LET MUT IDENT ':' BOOL '=' Expr ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "bool";
        sym_mut[sym_count] = 1;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("istore %d\n", lookup_addr($3)); // bool stored as int
    }
    | LET MUT IDENT ':' STR '=' Expr ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "str";
        sym_mut[sym_count] = 1;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("astore %d\n", lookup_addr($3));
    }
    | LET MUT IDENT ':' '&' STR '=' Expr ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "str";
        sym_mut[sym_count] = 1;     // Set mutability
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        CODEGEN("astore %d\n", lookup_addr($3)); // Assuming '&' STR is still a string ref
    }
    | LET MUT IDENT '=' Expr ';' { // New rule for type-inferred mutable declaration
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = strdup($5); // Corrected from $4 to $5, type inferred from Expr
        sym_mut[sym_count] = 1;     // Set mutability to 1
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
        // Code generation for storing the value from Expr ($5 is type, $4 is value source)
        char* var_type = $5; // Type of the variable IDENT, inferred from Expr
        int var_addr = lookup_addr($3);
        if (strcmp(var_type, "i32") == 0 || strcmp(var_type, "bool") == 0) { // bool stored as int
            CODEGEN("istore %d\n", var_addr);
        } else if (strcmp(var_type, "f32") == 0) {
            CODEGEN("fstore %d\n", var_addr);
        } else if (strcmp(var_type, "str") == 0) {
            CODEGEN("astore %d\n", var_addr);
        }
    }
    | LET MUT IDENT ':' INT ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "i32";
        sym_mut[sym_count] = 1;
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
    }
    | LET MUT IDENT ':' FLOAT ';' {
        insert_sym_entry($3, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($3);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "f32";
        sym_element_types[sym_count] = "-"; // Default for non-arrays
        sym_mut[sym_count] = 1;
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
    }
    // Array Declaration: LET IDENT ($2) ':' '[' INT ($5) ';' INT_LIT ($7) ']' '=' '[' (action $9) ExprList ($10) (action $11) ']' ($12) ';' ($13)
    | LET IDENT ':' '[' INT ';' INT_LIT
      {
        // Action before ExprList for array initialization ($9 based on counting tokens from LET)
        // Original printf("INT_LIT %d\n", $7); is removed by replacing the whole rule.
        g_is_array_init = true;
        g_array_init_count = 0;
      }
      ']' '=' '[' ExprList
      {
        // Action after ExprList ($12 based on counting tokens from LET)
        g_is_array_init = false;
      }
      ']' ';'
    {
        // Main action for array declaration
        // $2=IDENT, $5=INT (type token), $7=INT_LIT (size value)
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2); // Assuming direct manipulation is intended alongside insert_sym_entry
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "array";
        sym_mut[sym_count] = 0;     // LET is immutable
        sym_funcsig[sym_count] = "-";

        // Set element type based on $5 (INT token value, not its string name)
        // Assuming INT token corresponds to "i32". If language had FLOAT token for type:
        // if ($5 == INT) sym_element_types[sym_count] = strdup("i32");
        // else if ($5 == FLOAT) sym_element_types[sym_count] = strdup("f32"); etc.
        // For now, the grammar is fixed to INT type for arrays.
        sym_element_types[sym_count] = strdup("i32");

        CODEGEN("ldc %d\n", $7); // Push array size from INT_LIT ($7)

        // Generate newarray based on element type stored
        if (strcmp(sym_element_types[sym_count], "i32") == 0) CODEGEN("newarray int\n");
        // else if (strcmp(sym_element_types[sym_count], "f32") == 0) CODEGEN("newarray float\n"); // Future
        // else if (strcmp(sym_element_types[sym_count], "bool") == 0) CODEGEN("newarray boolean\n"); // Future, or use int
        // else if (strcmp(sym_element_types[sym_count], "str") == 0) CODEGEN("anewarray java/lang/String\n"); // Future
        else { printf("error:%d: Unsupported array element type for newarray.\n", yylineno); }

        // Array initialization loop using g_array_init_values
        // This currently only supports int literals due to g_array_init_values structure
        if (strcmp(sym_element_types[sym_count], "i32") == 0) { // Also for bool if stored as int
            for (int i = 0; i < g_array_init_count; ++i) {
               CODEGEN("dup\n");
               CODEGEN("ldc %d\n", i);
               CODEGEN("ldc %d\n", g_array_init_values[i].val_int);
               CODEGEN("iastore\n");
            }
        } // Add loops for other types if g_array_init_values is extended & sym_element_types allows

        CODEGEN("astore %d\n", lookup_addr($2));

        sym_count++; // Increment symbol count *after* all fields are set
        next_addr++;
    }
    | IDENT '=' Expr ';' {
        int var_idx = lookup_symbol_index($1);
        if (var_idx == -1) { // LHS undefined
            printf("error:%d: undefined: %s\n", yylineno, $1);
        } else { // LHS is defined
            // Expr ($3) code has been generated, its value is on the stack.
            // Type of Expr is in $3 (as char*)
            if (strcmp($3, "") != 0) { // Check if RHS had an error
                if (sym_mut[var_idx] == 0 && strcmp(sym_types[var_idx], "func") != 0) {
                    printf("error:%d: cannot borrow immutable borrowed content `%s` as mutable\n", yylineno, $1);
                    // Pop the value from RHS if assignment is invalid due to mutability
                    if (strcmp($3, "f32") == 0) CODEGEN("pop\n"); // Potentially pop2 for 8-byte types if any
                    else CODEGEN("pop\n");
                } else {
                    // TODO: Add type checking for assignment sym_types[var_idx] vs $3 if needed
                    // For now, assume types match or are compatible as per previous phases
                    char* var_type = sym_types[var_idx];
                    int var_addr = sym_addrs[var_idx];
                    if (strcmp(var_type, "i32") == 0 || strcmp(var_type, "bool") == 0) {
                        CODEGEN("istore %d\n", var_addr);
                    } else if (strcmp(var_type, "f32") == 0) {
                        CODEGEN("fstore %d\n", var_addr);
                    } else if (strcmp(var_type, "str") == 0) {
                        CODEGEN("astore %d\n", var_addr);
                    } else {
                        // Unknown type, pop value to keep stack clean
                        printf("error:%d: unknown type %s for variable %s in assignment\n", yylineno, var_type, $1);
                        if (strcmp($3, "f32") == 0) CODEGEN("pop\n");
                        else CODEGEN("pop\n");
                    }
                }
            }
            // If $3 (RHS type) is "", it means RHS had an error, which was already printed.
            // The value from RHS might not be on stack or could be garbage.
        }
    }
    | IDENT ADD_ASSIGN Expr ';' { printf("ADD_ASSIGN\n"); }
    | IDENT SUB_ASSIGN Expr ';' { printf("SUB_ASSIGN\n"); }
    | IDENT MUL_ASSIGN Expr ';' { printf("MUL_ASSIGN\n"); }
    | IDENT DIV_ASSIGN Expr ';' { printf("DIV_ASSIGN\n"); }
    | IDENT REM_ASSIGN Expr ';' { printf("REM_ASSIGN\n"); }
    | PRINTLN '(' Expr ')' ';' {
        // Expr ($3) code is generated first, its type is also in $3 (as char*)
        // The action for Expr itself would have generated the code to put its value on stack.
        // Then this semantic block runs.
        // Value is on top, PrintStream needs to be below it for invokevirtual.
        // Sequence: [value] -> getstatic -> [value][PrintStream] -> swap -> [PrintStream][value] -> invokevirtual
        if (strcmp($3, "") != 0) { // $3 is type of Expr. If empty, Expr had an error.
            CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");
            CODEGEN("swap\n"); // Value from Expr was on stack, PrintStream obj pushed, now swap
            if (strcmp($3, "i32") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/println(I)V\n");
            } else if (strcmp($3, "f32") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/println(F)V\n");
            } else if (strcmp($3, "str") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n");
            } else if (strcmp($3, "bool") == 0) { // Bools (0 or 1) are printed as integers
                CODEGEN("invokevirtual java/io/PrintStream/println(I)V\n");
            } else {
                // Unknown type, pop the already pushed value and PrintStream to prevent stack errors
                // Assuming non-float types take 1 stack slot, float takes 1 (or 2 for double but we use f32)
                printf("error:%d: println cannot print type %s\n", yylineno, $3);
                CODEGEN("pop\n"); // Pop PrintStream
                CODEGEN("pop\n"); // Pop the unknown value
            }
        }
        // If $3 was "", Expr already had an error, value might not be on stack or is invalid.
        // No specific cleanup here as stack state is uncertain from prior error.
    }
    | PRINT '(' Expr ')' ';' {
        if (strcmp($3, "") != 0) { // $3 is type of Expr
            CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");
            CODEGEN("swap\n");
            if (strcmp($3, "i32") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/print(I)V\n");
            } else if (strcmp($3, "f32") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/print(F)V\n");
            } else if (strcmp($3, "str") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/print(Ljava/lang/String;)V\n");
            } else if (strcmp($3, "bool") == 0) {
                CODEGEN("invokevirtual java/io/PrintStream/print(I)V\n");
            } else {
                printf("error:%d: print cannot print type %s\n", yylineno, $3);
                CODEGEN("pop\n");
                CODEGEN("pop\n");
            }
        }
    }
    | PrintStmt
    | IfStmt
    | WhileStmt
    | ScopedBlock
    | RETURN ret_expr_val=ExprOpt ';' {
        // $2 (ret_expr_val) is the type string from ExprOpt (e.g., "i32", "f32", "str", or "" for void/no expr)
        // Code for Expr (if any) has been generated by ExprOpt's rule, value is on stack.

        if (current_processing_func_name[0] == '\0') {
            printf("error:%d: RETURN statement outside of function\n", yylineno);
            // Attempt to pop value if any, though context is lost.
            if (strcmp($2, "") != 0 && strcmp($2,"ProcessedArgs")!=0) { // ProcessedArgs is a placeholder, real types are i32, f32 etc.
                 if (strcmp($2, "f32") == 0 /*|| other 2-slot types*/) CODEGEN("pop2\n"); else CODEGEN("pop\n");
            }
        } else {
            int current_func_idx = lookup_symbol_index(current_processing_func_name);
            if (current_func_idx == -1) {
                printf("error:%d: Could not find current function %s in symbol table (compiler bug)\n", yylineno, current_processing_func_name);
            } else {
                char expected_ret_char_jasmin = 'V'; // Default to void
                const char* current_sig = sym_funcsig[current_func_idx];
                const char* current_closing_paren = strchr(current_sig, ')');
                if (current_closing_paren != NULL && *(current_closing_paren + 1) != '\0') {
                    expected_ret_char_jasmin = *(current_closing_paren + 1);
                }

                // Basic Type Checking (Simplified)
                // $2 is the type of the returned expression e.g. "i32", "f32", "str", "" (for void ExprOpt)
                char actual_ret_char_source = 'V';
                if (strcmp($2, "i32") == 0 || strcmp($2, "bool") == 0) actual_ret_char_source = 'I'; // bools are i32 internally
                else if (strcmp($2, "f32") == 0) actual_ret_char_source = 'F';
                else if (strcmp($2, "str") == 0) actual_ret_char_source = 'L'; // Assuming L for any object/string ref
                else if (strcmp($2, "") == 0) actual_ret_char_source = 'V'; // No expression given

                if (expected_ret_char_jasmin == 'V' && actual_ret_char_source != 'V') {
                    printf("error:%d: Cannot return a value from void function %s\n", yylineno, current_processing_func_name);
                    // Pop the erroneous value
                    if (actual_ret_char_source == 'F') CODEGEN("pop\n"); /*fstore uses 1 slot for f32 per .locals*/ else CODEGEN("pop\n");
                    CODEGEN("return\n"); // Generate void return
                } else if (expected_ret_char_jasmin != 'V' && actual_ret_char_source == 'V') {
                    printf("error:%d: Must return a value from non-void function %s (expected %c)\n", yylineno, current_processing_func_name, expected_ret_char_jasmin);
                    // Cannot magically put a value on stack, this will likely lead to JVM error.
                    // For robustness, could push a default and return, but that hides user error.
                    // Fallthrough to generate typed return, JVM will verify stack.
                    if (expected_ret_char_jasmin == 'I') CODEGEN("ireturn\n");
                    else if (expected_ret_char_jasmin == 'F') CODEGEN("freturn\n");
                    else if (expected_ret_char_jasmin == 'L') CODEGEN("areturn\n");
                    else CODEGEN("return\n"); // Should not happen if logic is correct
                } else if (expected_ret_char_jasmin != actual_ret_char_source && actual_ret_char_source != 'V') {
                    // Basic type mismatch, e.g. function expects int, user returns float
                    printf("error:%d: Return type mismatch in function %s. Expected type compatible with %c, got %c.\n", yylineno, current_processing_func_name, expected_ret_char_jasmin, actual_ret_char_source);
                    // Pop incorrect value from stack
                    if (actual_ret_char_source == 'F') CODEGEN("pop\n"); else CODEGEN("pop\n");
                    // Then generate expected return, which will likely fail at runtime if no default is pushed.
                    if (expected_ret_char_jasmin == 'I') CODEGEN("ireturn\n");
                    else if (expected_ret_char_jasmin == 'F') CODEGEN("freturn\n");
                    else if (expected_ret_char_jasmin == 'L') CODEGEN("areturn\n");
                    else CODEGEN("return\n");
                }
                else { // Types match or void returning void
                    if (expected_ret_char_jasmin == 'I') CODEGEN("ireturn\n");
                    else if (expected_ret_char_jasmin == 'F') CODEGEN("freturn\n");
                    else if (expected_ret_char_jasmin == 'L') CODEGEN("areturn\n");
                    else CODEGEN("return\n"); // Void function
                }
            }
        }
        if ($2 != NULL && strcmp($2,"")!=0 && strcmp($2,"ProcessedArgs")!=0) free($2); // Free type string from ExprOpt if strdup'd
    }
    | NEWLINE
;

// Helper non-terminals for If Stmt
IfCondAction %type <s_val>
    : { // Executes after Expr. Assumes Expr left 0/1 on stack.
        char *label = (char*)malloc(LABEL_BUF_SIZE);
        NEW_LABEL(label);
        CODEGEN("ifeq %s\n", label); // If false (0), jump to label
        $$ = label; // Pass label name (L_else or L_endif)
      }
    ;

// Helper for If Stmt to pass label from IfCondAction after ScopedBlock (true-branch)
TrueBlockAndPassLabel %type <s_val>
    : cond_label=IfCondAction ScopedBlock
      { // $1 is cond_label (L_else or L_endif from IfCondAction)
        $$ = $1; // Pass L_else/L_endif along
      }
    ;

// Helper for If Stmt to generate goto L_end, define L_else, and return L_end
ElseMidAction %type <s_val>
    : true_block_res=TrueBlockAndPassLabel // true_block_res is L_else from IfCondAction via TrueBlockAndPassLabel
      {
        // $1 is L_else (result of TrueBlockAndPassLabel)
        char *l_end = (char*)malloc(LABEL_BUF_SIZE);
        NEW_LABEL(l_end);
        CODEGEN("goto %s\n", l_end); // Jump over the else block
        CODEGEN("%s:\n", $1);       // Define L_else (where execution jumps if condition was false)
        free($1);                   // Free L_else string
        $$ = l_end;                 // Return L_end
      }
    ;

// Helper non-terminals for While Stmt
WhileStart %type <s_val>
    : { // Executed at the start of the while loop construct, before Expr
        char* start_label = (char*)malloc(LABEL_BUF_SIZE);
        NEW_LABEL(start_label);
        CODEGEN("%s:\n", start_label); // Define loop start label
        $$ = start_label;
      }
    ;

WhileCond %type <s_val>
    : { // Executed after Expr. Assumes Expr left 0/1 on stack.
        char* end_label = (char*)malloc(LABEL_BUF_SIZE);
        NEW_LABEL(end_label);
        CODEGEN("ifeq %s\n", end_label); // If false (0), jump to end_label
        $$ = end_label; // Pass loop end label name
      }
    ;

Expr
    : INT_LIT {
        if (g_is_array_init) {
            if (g_array_init_count < MAX_ARRAY_INIT_SIZE) {
                g_array_init_values[g_array_init_count++].val_int = $1;
            } else {
                printf("error:%d: Too many initializers for array\n", yylineno);
            }
        } else {
            CODEGEN("ldc %d\n", $1);
        }
        $$ = "i32";
    }
    | FLOAT_LIT {
        if (g_is_array_init) printf("error:%d: Float literals in array init not supported yet.\n", yylineno);
        else CODEGEN("ldc %f\n", $1);
        $$ = "f32";
    }
    | '"' '"' {
        if (g_is_array_init) printf("error:%d: String literals in array init not supported yet.\n", yylineno);
        else CODEGEN("ldc \"\"\n");
        $$ = "str";
    }
    | '"' STRING_LIT '"' {
        if (g_is_array_init) printf("error:%d: String literals in array init not supported yet.\n", yylineno);
        else CODEGEN("ldc \"%s\"\n", $2);
        $$ = "str";
    }
    | IDENT { 
        $$ = lookup_type($1); 
        if (strcmp($$, "") == 0) {
            printf("error:%d: undefined: %s\n", yylineno, $1);
        } else {
            int var_addr = lookup_addr($1);
            char* var_type = $$;

            if (g_is_array_init) {
                 printf("error:%d: Variables not allowed in array literal initializers.\n", yylineno);
            } else {
                if (strcmp(var_type, "i32") == 0 || strcmp(var_type, "bool") == 0) {
                    CODEGEN("iload %d\n", var_addr);
                } else if (strcmp(var_type, "f32") == 0) {
                    CODEGEN("fload %d\n", var_addr);
                } else if (strcmp(var_type, "str") == 0 || strcmp(var_type, "array") == 0) {
                    CODEGEN("aload %d\n", var_addr);
                }
            }
        }
    }
    | TRUE {
        if (g_is_array_init) {
            if (g_array_init_count < MAX_ARRAY_INIT_SIZE) {
                 g_array_init_values[g_array_init_count++].val_int = 1;
            } else {
                 printf("error:%d: Too many initializers for array\n", yylineno);
            }
        } else {
            CODEGEN("iconst_1\n");
        }
        $$ = "bool";
    }
    | FALSE {
        if (g_is_array_init) {
             if (g_array_init_count < MAX_ARRAY_INIT_SIZE) {
                 g_array_init_values[g_array_init_count++].val_int = 0;
            } else {
                 printf("error:%d: Too many initializers for array\n", yylineno);
            }
        } else {
            CODEGEN("iconst_0\n");
        }
        $$ = "bool";
    }
    | '-' Expr %prec UMINUS {
        if (g_is_array_init) printf("error:%d: Unary minus not supported in array literal initializers.\n", yylineno);
        if (strcmp($2, "i32") == 0) {
            CODEGEN("ineg\n"); $$ = "i32";
        } else if (strcmp($2, "f32") == 0) {
            CODEGEN("fneg\n"); $$ = "f32";
        } else {
            if (strcmp($2, "") != 0) { 
                 printf("error:%d: invalid operation: NEG (mismatched types %s)\n", yylineno, strcmp($2,"")==0 ? "undefined": $2);
            }
            $$ = "";
        }
    }
    | '!' Expr {
        // Assuming the expression $2 leaves 1 (true) or 0 (false) on the stack
        if (strcmp($2, "bool") == 0) {
            CODEGEN("iconst_1\n"); // Load 1 (true)
            CODEGEN("ixor\n");    // XOR with 1 flips 0 to 1 and 1 to 0
            $$ = "bool";
        } else {
            if (strcmp($2, "") != 0) {
                printf("error:%d: invalid operation: NOT (mismatched types %s)\n", yylineno, strcmp($2,"")==0 ? "undefined": $2);
            }
            $$ = "";
        }
    }
    | '(' Expr ')' { $$ = $2; }
    | Expr '*' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("imul\n"); $$ = "i32";
        } else if (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0) {
            CODEGEN("fmul\n"); $$ = "f32";
        } else {
            if (strcmp($1,"")!=0 && strcmp($3,"")!=0) {
                printf("error:%d: invalid operation: MUL (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr '/' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("idiv\n"); $$ = "i32";
        } else if (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0) {
            CODEGEN("fdiv\n"); $$ = "f32";
        } else {
            if (strcmp($1,"")!=0 && strcmp($3,"")!=0) {
                printf("error:%d: invalid operation: DIV (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr '%' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("irem\n"); $$ = "i32";
        } else {
            if (strcmp($1,"")!=0 && strcmp($3,"")!=0) {
                printf("error:%d: invalid operation: REM (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr '+' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("iadd\n"); $$ = "i32";
        } else if (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0) {
            CODEGEN("fadd\n"); $$ = "f32";
        } else {
             if (strcmp($1,"")!=0 && strcmp($3,"")!=0) {
                printf("error:%d: invalid operation: ADD (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr '-' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("isub\n"); $$ = "i32";
        } else if (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0) {
            CODEGEN("fsub\n"); $$ = "f32";
        } else {
            if (strcmp($1,"")!=0 && strcmp($3,"")!=0) {
                printf("error:%d: invalid operation: SUB (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr '>' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);

        if (! (t1_is_num && t2_is_num) ) { // If types are not both numeric
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) { // Avoid error if both operands were already undefined
                 printf("error:%d: invalid operation: GTR (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error
        } else {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "i32") == 0) { // Assuming i32 for now, f32 needs fcmpl
                CODEGEN("if_icmpgt %s\n", true_label);
            } else { // f32
                CODEGEN("fcmpl\n"); // Compares $1 and $3, result on stack (-1, 0, or 1)
                CODEGEN("ifgt %s\n", true_label); // If result > 0 ($1 > $3)
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        }
    }
    | Expr '<' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        if (t1_is_num && t2_is_num) {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "i32") == 0) {
                CODEGEN("if_icmplt %s\n", true_label);
            } else { // f32
                CODEGEN("fcmpl\n");
                CODEGEN("iflt %s\n", true_label); // If result < 0 ($1 < $3)
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LSS (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error
        }
    }
    | Expr EQL Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        int t1_is_bool = strcmp($1, "bool") == 0;
        int t2_is_bool = strcmp($3, "bool") == 0;

        if ((t1_is_num && t2_is_num) || (t1_is_bool && t2_is_bool) || (strcmp($1,$3)==0 && strcmp($1,"str")==0) ) {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "f32") == 0) { // Floats need fcmpl first
                CODEGEN("fcmpl\n"); // leaves 0 on stack if equal
                CODEGEN("ifeq %s\n", true_label); // So jump if equal
            } else if (strcmp($1, "str") == 0) { // Strings use aequals
                // This assumes direct ldc for strings. If strings are stored as objects, this needs change.
                // For now, this is a placeholder as string comparison in Jasmin is more complex (object refs)
                // This will likely not work correctly without proper string object handling.
                CODEGEN("; TODO: String EQL not fully implemented for direct ldc values\n");
                 printf("error:%d: String equality comparison with 'ldc' values is complex and not fully implemented yet.\n", yylineno);
                $$ = ""; // Mark as error for now
                return $$; // Avoid generating further code for this path for now
            }
            else { // Integers and booleans (0 or 1) can use if_icmpeq
                 CODEGEN("if_icmpeq %s\n", true_label);
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
             if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: EQL (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error
        }
    }
    // Assuming NEQ, GEQ, LEQ follow a similar pattern and exist in the grammar
    | Expr NEQ Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        int t1_is_bool = strcmp($1, "bool") == 0;
        int t2_is_bool = strcmp($3, "bool") == 0;

        if ((t1_is_num && t2_is_num) || (t1_is_bool && t2_is_bool) || (strcmp($1,$3)==0 && strcmp($1,"str")==0) ) {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "f32") == 0) {
                CODEGEN("fcmpl\n");
                CODEGEN("ifne %s\n", true_label); // Jump if not equal
            } else if (strcmp($1, "str") == 0) {
                 CODEGEN("; TODO: String NEQ not fully implemented for direct ldc values\n");
                 printf("error:%d: String non-equality comparison with 'ldc' values is complex and not fully implemented yet.\n", yylineno);
                $$ = ""; return $$;
            } else {
                 CODEGEN("if_icmpne %s\n", true_label);
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
             if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: NEQ (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr GEQ Expr { // Greater than or Equal
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        if (t1_is_num && t2_is_num) {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "i32") == 0) {
                CODEGEN("if_icmpge %s\n", true_label);
            } else { // f32
                CODEGEN("fcmpl\n"); // $1 < $3 -> -1, $1 == $3 -> 0, $1 > $3 -> 1
                CODEGEN("ifge %s\n", true_label); // If result >= 0 ($1 >= $3)
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                 printf("error:%d: invalid operation: GEQ (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr LEQ Expr { // Less than or Equal
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        if (t1_is_num && t2_is_num) {
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            if (strcmp($1, "i32") == 0) {
                CODEGEN("if_icmple %s\n", true_label);
            } else { // f32
                CODEGEN("fcmpl\n"); // $1 < $3 -> -1, $1 == $3 -> 0, $1 > $3 -> 1
                CODEGEN("ifle %s\n", true_label); // If result <= 0 ($1 <= $3)
            }
            CODEGEN("iconst_0\n");
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n");
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                 printf("error:%d: invalid operation: LEQ (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "";
        }
    }
    | Expr LAND Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "bool") == 0 && strcmp($3, "bool") == 0) {
            // Code for $1 (leaves 0 or 1 on stack) is already generated
            char false_label[20], end_label[20];
            NEW_LABEL(false_label);
            NEW_LABEL(end_label);
            CODEGEN("ifeq %s\n", false_label); // if $1 is 0 (false), jump to load 0
            // code for $3 (leaves 0 or 1 on stack) will be generated now by Bison
            // No explicit call here, it's part of the rule reduction for $3
            // Result of $3 is on stack if $1 was true
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", false_label);
            CODEGEN("iconst_0\n"); // load 0 if $1 was false
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LAND (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error type if not bool && bool
        }
    }
    | Expr LOR Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "bool") == 0 && strcmp($3, "bool") == 0) {
            // Code for $1 is already generated
            char true_label[20], end_label[20];
            NEW_LABEL(true_label);
            NEW_LABEL(end_label);
            CODEGEN("ifne %s\n", true_label); // if $1 is 1 (true), jump to load 1
            // code for $3 will be generated by Bison
            // Result of $3 is on stack if $1 was false
            CODEGEN("goto %s\n", end_label);
            CODEGEN("%s:\n", true_label);
            CODEGEN("iconst_1\n"); // load 1 if $1 was true
            CODEGEN("%s:\n", end_label);
            $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LOR (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error type if not bool || bool
        }
    }
    | Expr LSHIFT Expr { // Assuming LSHIFT exists
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        
        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("ishl\n"); // Integer Shift Left
            $$ = "i32";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LSHIFT (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error type
        }
    }
    | Expr RSHIFT Expr { // Assuming RSHIFT exists
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);

        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            CODEGEN("ishr\n"); // Integer Shift Right (Arithmetic)
            // If logical shift right is needed, it's 'iushr'
            $$ = "i32";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: RSHIFT (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = ""; // Error type
        }
    }
    | IDENT '(' args_opt=ExprListOpt ')' {
        char* func_name = $1;
        // Args code from 'args=ExprListOpt' has been generated by its rules.
        // $3 (args_opt.s_val) is a placeholder string "ProcessedArgs" or "" for now.

        int func_idx = lookup_symbol_index(func_name);
        if (func_idx == -1) {
            printf("error:%d: undefined function %s\n", yylineno, func_name);
            $$ = ""; // Error type
        } else {
            char param_sig_jasmin_call[LABEL_BUF_SIZE] = "";
            char return_sig_jasmin_call[LABEL_BUF_SIZE] = "V"; // Default void

            const char* sig_call = sym_funcsig[func_idx];
            if (sig_call != NULL && strlen(sig_call) >= 3 && sig_call[0] == '(') {
                const char* closing_paren_call = strchr(sig_call, ')');
                if (closing_paren_call != NULL) { // Closing paren must exist
                    if (closing_paren_call > sig_call + 1) { // Params exist
                       strncpy(param_sig_jasmin_call, sig_call + 1, closing_paren_call - (sig_call + 1));
                       param_sig_jasmin_call[closing_paren_call - (sig_call + 1)] = '\0';
                    } else {
                        param_sig_jasmin_call[0] = '\0'; // No params "()"
                    }
                    if (*(closing_paren_call + 1) != '\0') {
                       strncpy(return_sig_jasmin_call, closing_paren_call + 1, LABEL_BUF_SIZE-1);
                       return_sig_jasmin_call[LABEL_BUF_SIZE-1] = '\0';
                    }
                }
            } else {
                // This case should ideally not happen if sym_funcsig is always set for functions
                printf("warning:%d: could not parse signature for function %s. Assuming ()V.\n", yylineno, func_name);
            }

            CODEGEN("invokestatic Main/%s(%s)%s\n", func_name, param_sig_jasmin_call, return_sig_jasmin_call);

            // Convert return_sig_jasmin_call back to compiler's type string for $$
            if (strcmp(return_sig_jasmin_call, "I") == 0) $$ = "i32";
            else if (strcmp(return_sig_jasmin_call, "F") == 0) $$ = "f32";
            else if (strcmp(return_sig_jasmin_call, "Ljava/lang/String;") == 0) $$ = "str"; // Assuming "str" is our type for String
            else if (strcmp(return_sig_jasmin_call, "Z") == 0) $$ = "bool"; // Assuming "bool" for Boolean
            else if (strcmp(return_sig_jasmin_call, "V") == 0) $$ = ""; // Void expression type
            else {
                printf("warning:%d: unhandled Jasmin return type %s for function %s call\n", yylineno, return_sig_jasmin_call, func_name);
                $$ = ""; // Unknown type
            }
        }
        free($1); // IDENT s_val was strdup'd by lexer
        if ($3 != NULL && strcmp($3, "") != 0) free($3); // Free result from ExprListOpt if it was strdup'ed
    }
    | Expr AS INT { 
        if (strcmp($1, "f32") == 0) { CODEGEN("f2i\n"); $$ = "i32"; }
        else if (strcmp($1, "i32") == 0) { $$ = "i32"; }
        else { 
            if (strcmp($1,"")!=0) printf("error:%d: invalid cast from %s to i32\n",yylineno, strcmp($1,"")==0 ? "undefined": $1);
            $$ = "";
        }
    }
    | Expr AS FLOAT { 
        if (strcmp($1, "i32") == 0) { printf("i2f\n"); $$ = "f32"; }
        else if (strcmp($1, "f32") == 0) { $$ = "f32"; }
        else {
            if (strcmp($1,"")!=0) printf("error:%d: invalid cast from %s to f32\n",yylineno, strcmp($1,"")==0 ? "undefined": $1);
            $$ = "";
        }
    }
    // Array Element Load: IDENT ($1) '[' index_expr ($4) ']'
    | IDENT '[' Expr ']'
      { 
          char* array_name = $1;
          char* index_expr_type = $3; // Type of the index expression $3 (Expr)
          $$ = ""; // Default to error/unknown type

          int array_idx = lookup_symbol_index(array_name);
          if (array_idx == -1) {
              printf("error:%d: undefined array %s\n", yylineno, array_name);
          } else if (strcmp(sym_types[array_idx], "array") != 0) {
              printf("error:%d: %s is not an array\n", yylineno, array_name);
          } else if (strcmp(index_expr_type, "i32") != 0) {
              printf("error:%d: array index must be an integer, found %s\n", yylineno, index_expr_type);
          } else {
              // Code for index Expr ($3) has already been generated.
              CODEGEN("aload %d\n", sym_addrs[array_idx]); // Load array reference
              CODEGEN("swap\n"); // Swap array_ref and index, so stack is: array_ref, index
                                 // This is needed because index_expr code ran first.

              const char* elem_type = sym_element_types[array_idx];
              if (strcmp(elem_type, "i32") == 0) {
                  CODEGEN("iaload\n"); $$ = "i32";
              } else if (strcmp(elem_type, "f32") == 0) { // Assuming f32 elements are supported
                  CODEGEN("faload\n"); $$ = "f32";
              } else if (strcmp(elem_type, "bool") == 0) { // Assuming bool elements are stored as int
                  CODEGEN("iaload\n"); $$ = "bool"; // conceptually bool, loaded as int by iaload
              } else if (strcmp(elem_type, "str") == 0) { // Assuming str elements are supported
                  CODEGEN("aaload\n"); $$ = "str";
              } else {
                  printf("error:%d: unsupported array element type %s for aload\n", yylineno, elem_type);
              }
          }
          free($1); // Free IDENT s_val
          // $3 (index_expr_type) is likely a pointer to static string or complex type, handle memory if it was result of strdup
      }
;

ExprList
    : Expr { $$ = $1; /* Type of the single expression, not really used by ExprListOpt for now */ }
    | ExprList ',' Expr { $$ = $3; /* Type of the last expression, again, not critical for current ExprListOpt */ }
;

ExprListOpt: /* empty */ { $$ = strdup(""); /* No args, empty string or special marker */ }
           | ExprList  { $$ = strdup("ProcessedArgs"); /* Placeholder, indicates args were processed */ }
           ;

ExprOpt: /* empty */ { $$ = strdup(""); /* Indicates no expression / void type */ }
       | Expr      { $$ = $1; /* Type of expression, might need strdup if $1 is transient */ }
       ;


PrintStmt
    : PRINTLN '(' STRING_LIT ')' ';' { 
        CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");
        CODEGEN("ldc \"%s\"\n", $3); // $3 is the string value from STRING_LIT token
        CODEGEN("invokevirtual java/io/PrintStream/println(Ljava/lang/String;)V\n");
    }
;

ScopedBlock
    : '{' { current_scope_level++; create_sym_table(); } StmtList '}' {
        dump_sym_table(current_scope_level);
        while (sym_count > 0 && sym_scopes[sym_count-1] == current_scope_level) sym_count--;
        current_scope_level--;
    }
;

IfStmt:
    IF Expr true_block_res=TrueBlockAndPassLabel // $2 is Expr, $3 is true_block_res
    {
        // Simple IF: IF Expr {L_endif=IfCondAction} ScopedBlock {define L_endif}
        // true_block_res is L_endif from IfCondAction passed through TrueBlockAndPassLabel
        CODEGEN("%s:\n", $3);
        free($3);
    }
  | IF Expr main_else_setup=ElseMidAction ELSE ScopedBlock // $2 is Expr, $3 is main_else_setup, $5 is ScopedBlock (else part)
    {
        // IF-ELSE: IF Expr {L_else=IfCondAction} ScopedBlock {L_end=ElseMidAction(L_else)} ELSE ScopedBlock {define L_end}
        // main_else_setup is L_end from ElseMidAction
        CODEGEN("%s:\n", $3);
        free($3);
    }
  | IF Expr main_else_setup_rec=ElseMidAction ELSE IfStmt // $2 is Expr, $3 is main_else_setup_rec, $5 is IfStmt (recursive)
    {
        // IF-ELSE-IF:
        // main_else_setup_rec is L_end from ElseMidAction
        // This L_end is for the current IF-ELSE structure. The recursive IfStmt handles its own.
        CODEGEN("%s:\n", $3);
        free($3);
    }
;

WhileStmt
    : WHILE start_lab=WhileStart Expr cond_lab=WhileCond ScopedBlock
      { // $2=start_lab, $3=Expr, $4=cond_lab, $5=ScopedBlock
        CODEGEN("goto %s\n", $2);   // Jump back to start_label (ws)
        CODEGEN("%s:\n", $4);     // Define end_label (wc)
        free($2); // free start_label
        free($4); // free end_label
      }
;

%%

/* C code section */
int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }

    yylineno = 1; 
    
    create_sym_table(); 

    yyout = fopen("Main.j", "w");
    if (!yyout) {
        perror("Error opening Main.j");
        return 1;
    }
    
    yyparse();

    int total_lines_to_print = yylineno;
    if (total_lines_to_print > 0) { 
        total_lines_to_print--;
    }
	printf("Total lines: %d\n", total_lines_to_print);
    
    if (yyin != stdin) { // Ensure yyin is not stdin before closing
        fclose(yyin);
    }
    fclose(yyout); // Added fclose(yyout)
    return 0;
}

static void create_sym_table() {
    printf("> Create symbol table (scope level %d)\n", current_scope_level);
}

static void insert_sym_entry(const char* name, int addr, int scope_level, int lineno) {
    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, addr, scope_level);
    // Initialize element type to "-" or some default for non-arrays
    if (sym_count < MAX_SYM) { // Should match the check in actual symbol table logic
        sym_element_types[sym_count -1] = "-"; // Assuming insert_sym_entry might increment sym_count
                                            // Or, this should be done where sym_types etc. are set.
                                            // For this subtask, will set it explicitly in array decl rule.
    }
}

static void dump_sym_table(int scope_level) {
    printf("\n> Dump symbol table (scope level: %d)\n", scope_level);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s%-15s\n", // Added column for ElemType
        "Index", "Name", "Mut","Type", "Addr", "Lineno", "Func_sig", "ElemType");
    int local_idx = 0;
    for (int i = 0; i < sym_count; i++) {
        if (sym_scopes[i] == scope_level) {
            int mut_flag;
            if (strcmp(sym_types[i], "func") == 0) {
                mut_flag = -1;
            } else {
                mut_flag = sym_mut[i];
            }
            char type_to_print[20];
            if (sym_types[i] == NULL || strcmp(sym_types[i], "") == 0) {
                strcpy(type_to_print, "undefined");
            } else {
                strcpy(type_to_print, sym_types[i]);
            }
            char elem_type_to_print[20];
            if (sym_element_types[i] == NULL || strcmp(sym_element_types[i], "") == 0) {
                 strcpy(elem_type_to_print, "-");
            } else {
                 strcpy(elem_type_to_print, sym_element_types[i]);
            }
            printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s%-15s\n",
                local_idx, sym_names[i], mut_flag, type_to_print, sym_addrs[i], sym_linenos[i], sym_funcsig[i], elem_type_to_print);
            local_idx++;
        }
    }
}

static int lookup_symbol_index(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (sym_names[i] != NULL && strcmp(sym_names[i], name) == 0) {
            return i;
        }
    }
    return -1;
}

int lookup_addr(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (strcmp(sym_names[i], name) == 0) return sym_addrs[i];
    }
    return -1;
}

char *lookup_type(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (strcmp(sym_names[i], name) == 0) return sym_types[i];
    }
    return "";
}