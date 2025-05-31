/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h"
    // #define YYDEBUG 1
    // int yydebug = 1;

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

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

    /* Symbol table storage */
    #define MAX_SYM 100
    static char* sym_names[MAX_SYM];
    static char* sym_types[MAX_SYM];
    static char* sym_funcsig[MAX_SYM];
    static int sym_addrs[MAX_SYM];
    static int sym_scopes[MAX_SYM];
    static int sym_linenos[MAX_SYM];
    static int sym_mut[MAX_SYM]; // Added for mutability
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
      { dump_sym_table(0); /* Dump global symbol table at the end */ }
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
        printf("func: %s\n", $2);
        if (strcmp($2, "main") == 0) {
            main_func_lineno = yylineno;
        }
        insert_sym_entry($2, -1, 0, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = -1;
        sym_scopes[sym_count] = 0;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "func";
        sym_funcsig[sym_count] = "(V)V";
        sym_count++;
        current_scope_level++;   
        next_addr = 0;          
        create_sym_table();      
    } Block {
        dump_sym_table(current_scope_level); 
        current_scope_level--;               
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
        sym_mut[sym_count] = 1;
        sym_funcsig[sym_count] = "-";
        sym_count++;
        next_addr++;
    }
    | LET IDENT ':' '[' INT ';' INT_LIT { printf("INT_LIT %d\n", $7); } ']' '=' '[' ExprList ']' ';' { // Array declaration
        // Size already printed by mid-rule action.
        // ExprList elements are handled by their own Expr rules, which should print them.
        insert_sym_entry($2, next_addr, current_scope_level, yylineno);
        sym_names[sym_count] = strdup($2);
        sym_addrs[sym_count] = next_addr;
        sym_scopes[sym_count] = current_scope_level;
        sym_linenos[sym_count] = yylineno;
        sym_types[sym_count] = "array"; // Type is "array"
        sym_mut[sym_count] = 0;     // Mutability (0 for let)
        sym_funcsig[sym_count] = "-"; // Placeholder for detailed array type sig
        sym_count++;
        next_addr++; // Simplified address management
    }
    | IDENT '=' Expr ';' {
        int var_idx = lookup_symbol_index($1);
        if (var_idx == -1) { // LHS undefined
            printf("error:%d: undefined: %s\n", yylineno, $1);
        } else { // LHS is defined
            printf("ASSIGN\n"); // Print ASSIGN if LHS is defined
            // Only check for mutability or other assignment errors if RHS was valid
            if (strcmp($3, "") != 0) { 
                if (sym_mut[var_idx] == 0 && strcmp(sym_types[var_idx], "func") != 0) {
                    printf("error:%d: cannot borrow immutable borrowed content `%s` as mutable\n", yylineno, $1);
                }
                // TODO: Add type checking for assignment sym_types[var_idx] vs $3 if needed
            }
            // If $3 (RHS type) is "", it means RHS had an error, which was already printed.
            // The mutability error for LHS is suppressed in this case to match answer a09_error.out for x = x << z;
        }
    }
    | IDENT ADD_ASSIGN Expr ';' { printf("ADD_ASSIGN\n"); }
    | IDENT SUB_ASSIGN Expr ';' { printf("SUB_ASSIGN\n"); }
    | IDENT MUL_ASSIGN Expr ';' { printf("MUL_ASSIGN\n"); }
    | IDENT DIV_ASSIGN Expr ';' { printf("DIV_ASSIGN\n"); }
    | IDENT REM_ASSIGN Expr ';' { printf("REM_ASSIGN\n"); }
    | PRINTLN '(' Expr ')' ';' {
        if (strcmp($3, "") != 0) {
             printf("PRINTLN %s\n", $3);
        }
    }
    | PRINT '(' Expr ')' ';' {
        if (strcmp($3, "") != 0) {
            printf("PRINT %s\n", $3);
        }
    }
    | PrintStmt
    | IfStmt
    | WhileStmt
    | ScopedBlock
    | NEWLINE
;

Expr
    : INT_LIT { printf("INT_LIT %d\n", $1); $$ = "i32"; }
    | FLOAT_LIT { printf("FLOAT_LIT %f\n", $1); $$ = "f32"; }
    | '"' '"' { printf("STRING_LIT \"\"\n"); $$ = "str"; }
    | '"' STRING_LIT '"' { printf("STRING_LIT \"%s\"\n", $2); $$ = "str"; }
    | IDENT { 
        $$ = lookup_type($1); 
        if (strcmp($$, "") == 0) {
            printf("error:%d: undefined: %s\n", yylineno, $1);
        } else {
            printf("IDENT (name=%s, address=%d)\n", $1, lookup_addr($1));
        }
    }
    | TRUE { printf("bool TRUE\n"); $$ = "bool"; }
    | FALSE { printf("bool FALSE\n"); $$ = "bool"; }
    | '-' Expr %prec UMINUS {
        if (strcmp($2, "i32") == 0 || strcmp($2, "f32") == 0) {
            printf("NEG\n"); $$ = $2;
        } else {
            if (strcmp($2, "") != 0) { 
                 printf("error:%d: invalid operation: NEG (mismatched types %s)\n", yylineno, strcmp($2,"")==0 ? "undefined": $2);
            }
            $$ = "";
        }
    }
    | '!' Expr {
        if (strcmp($2, "bool") == 0) {
            printf("NOT\n"); $$ = "bool";
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
        if ((strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) || (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0)) {
            printf("MUL\n"); $$ = $1;
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
        if ((strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) || (strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0)) {
            printf("DIV\n"); $$ = $1;
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
        if ((strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0)) {
            printf("REM\n"); $$ = $1;
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
        if ((strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0)) {
            printf("ADD\n"); $$ = "i32";
        } else if ((strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0)) {
            printf("ADD\n"); $$ = "f32";
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
        if ((strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0)) {
            printf("SUB\n"); $$ = "i32";
        } else if ((strcmp($1, "f32") == 0 && strcmp($3, "f32") == 0)) {
            printf("SUB\n"); $$ = "f32";
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
        }
        printf("GTR\n"); // Print GTR opcode regardless, as per answer
        $$ = "bool"; // Result is always bool for comparison
    }
    | Expr '<' Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        int t1_is_num = (strcmp($1, "i32") == 0 || strcmp($1, "f32") == 0);
        int t2_is_num = (strcmp($3, "i32") == 0 || strcmp($3, "f32") == 0);
        if (t1_is_num && t2_is_num) {
            printf("LSS\n");
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LSS (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
        }
        $$ = "bool";
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
            printf("EQL\n");
        } else {
             if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: EQL (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
        }
        $$ = "bool";
    }
    | Expr LAND Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "bool") == 0 && strcmp($3, "bool") == 0) {
            printf("LAND\n"); $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LAND (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "bool";
        }
    }
    | Expr LOR Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        if (strcmp($1, "bool") == 0 && strcmp($3, "bool") == 0) {
            printf("LOR\n"); $$ = "bool";
        } else {
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) {
                printf("error:%d: invalid operation: LOR (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
            $$ = "bool";
        }
    }
    | Expr LSHIFT Expr {
        char t1_print[20], t2_print[20];
        strcpy(t1_print, strcmp($1,"")==0 ? "undefined" : $1);
        strcpy(t2_print, strcmp($3,"")==0 ? "undefined" : $3);
        
        if (! (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) ) { // If not (i32 LSHIFT i32)
            if (! (strcmp($1,"")==0 && strcmp($3,"")==0 ) ) { // Avoid error if both were already undefined
                printf("error:%d: invalid operation: LSHIFT (mismatched types %s and %s)\n", yylineno, t1_print, t2_print);
            }
        }
        printf("LSHIFT\n"); // Print LSHIFT opcode regardless, as per answer

        if (strcmp($1, "i32") == 0 && strcmp($3, "i32") == 0) {
            $$ = "i32";
        } else {
            $$ = ""; // Error type
        }
    }
    | Expr AS INT { 
        if (strcmp($1, "f32") == 0) { printf("f2i\n"); $$ = "i32"; }
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
    | IDENT { printf("IDENT (name=%s, address=%d)\n", $1, lookup_addr($1)); } 
      '[' Expr ']' 
      { 
          char* array_base_type_val = lookup_type($1);
          if (strcmp(array_base_type_val, "array") != 0) {
              if(strcmp(array_base_type_val, "") != 0) {
                printf("error:%d: type %s does not support indexing\n", yylineno, strcmp(array_base_type_val,"")==0 ? "undefined" : array_base_type_val);
              }
              $$ = "";
          } else if (strcmp($4, "i32") != 0) {
              if(strcmp($4, "") != 0) {
                printf("error:%d: array index must be an integer, found %s\n", yylineno, strcmp($4,"")==0 ? "undefined" : $4);
              }
              $$ = "";
          }
          else {
            $$ = "array";
          }
      }
;

ExprList
    : Expr
    | ExprList ',' Expr
;

PrintStmt
    : PRINTLN '(' STRING_LIT ')' ';' { 
        printf("STRING_LIT \"%s\"\n", $3);
        printf("PRINTLN str\n");
    }
;

ScopedBlock
    : '{' { current_scope_level++; create_sym_table(); } StmtList '}' {
        dump_sym_table(current_scope_level);
        while (sym_count > 0 && sym_scopes[sym_count-1] == current_scope_level) sym_count--;
        current_scope_level--;
    }
;

IfStmt
    : IF Expr ScopedBlock
    | IF Expr ScopedBlock ELSE ScopedBlock
    | IF Expr ScopedBlock ELSE IfStmt
;

WhileStmt
    : WHILE Expr ScopedBlock
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
    
    yyparse();

    int total_lines_to_print = yylineno;
    if (total_lines_to_print > 0) { 
        total_lines_to_print--;
    }
	printf("Total lines: %d\n", total_lines_to_print);
    
    fclose(yyin);
    return 0;
}

static void create_sym_table() {
    printf("> Create symbol table (scope level %d)\n", current_scope_level);
}

static void insert_sym_entry(const char* name, int addr, int scope_level, int lineno) {
    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, addr, scope_level);
}

static void dump_sym_table(int scope_level) {
    printf("\n> Dump symbol table (scope level: %d)\n", scope_level);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s\n",
        "Index", "Name", "Mut","Type", "Addr", "Lineno", "Func_sig");
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
            printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
                local_idx, sym_names[i], mut_flag, type_to_print, sym_addrs[i], sym_linenos[i], sym_funcsig[i]);
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