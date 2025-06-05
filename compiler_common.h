#ifndef COMPILER_COMMON_H
#define COMPILER_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
/* Add what you need */

extern FILE *yyout;
#define CODEGEN(fmt, ...) fprintf(yyout, fmt, ##__VA_ARGS__)

#endif /* COMPILER_COMMON_H */