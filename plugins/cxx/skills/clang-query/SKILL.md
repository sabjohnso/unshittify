---
description: Query and explore the abstract syntax tree of a C++ codebase with clang-query. Use the AST matcher language of Clang to find every occurrence of a structural pattern (a call to a specific function, every override of a virtual method, every use of a deprecated type) precisely, and not approximately with a text search. Covers the compilation-database setup, the batch and the interactive call, the matcher syntax, and the output control. Use when the user asks you to find, locate, or search for a C++ code pattern structurally, or to write or debug a clang-tidy check matcher.
allowed-tools: Bash(clang-query:*), Read, Grep, Glob
---

# Query the AST with clang-query

Goal: express the requested structural pattern as a Clang AST matcher. Run it with clang-query against source compiled with the real flags of the project. Report exactly the matching locations.

clang-query runs the AST matcher language of Clang against real, compiled C++ source. That is the same matcher language that clang-tidy checks and Tooling library passes use. So you can search for a structural pattern precisely. A text search or a regex only approximates it.

## Prerequisite: a compilation database that the caller gives

clang-query needs the same include paths, defines, and language standard that the file was compiled with. Otherwise it fails to build a complete AST.

This skill runs `clang-query` and nothing else. The configuration or the run of a build is the job of the caller. `bear -- <build command>` and a CMake configure run arbitrary project commands, and that is a far wider grant than a read-only structural search needs. When no compilation database and no flags are available, report which of the following the caller must run, and stop. Do not build the project to get one.

- With CMake, a configure with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` writes `compile_commands.json` into the build directory. Point clang-query at it with `-p <build-dir>`.
- With a build system that does not emit one directly, `bear -- <build command>` (Bear) or `intercept-build <build command>` records one from a real build.
- With no compilation database, pass the compiler flags directly after `--`: `clang-query file.cpp -- -std=c++20 -Iinclude`.

## The run: batch or interactive

- **Batch (scriptable).** Pass one or more `-c "<command>"` flags, or `-f <command-file>`. clang-query runs them in sequence and exits:
  ```sh
  clang-query -p build -c "set output dump" -c 'match functionDecl(hasName("foo"))' file.cpp
  ```
  Prefer this form when clang-query runs as part of a scripted search. The interactive REPL (Read-Eval-Print Loop) waits on a prompt that a headless call cannot answer.
- **Interactive.** Run `clang-query -p build file.cpp` with no `-c` or `-f` flag to get a prompt. Then type `match <matcher>` (or `m` for short) directly. Adjust the matcher expression until it catches the intended pattern.

## The matcher language

- **Node matchers** select AST nodes by kind. Their names are in camelCase after the Clang node type: `functionDecl`, `cxxRecordDecl`, `varDecl`, `callExpr`, `cxxMemberCallExpr`, `binaryOperator`, `ifStmt`, `cxxNewExpr`.
- **Narrowing matchers** take the outer matcher as an argument and restrict which nodes of that kind match: `hasName("...")`, `hasType(...)`, `isConstexpr()`, `hasParameter(...)`, `isOverride()`.
- **Traversal matchers** cross node boundaries to match on the context: `hasParent(...)`, `hasAncestor(...)`, `hasDescendant(...)`, `forEachDescendant(...)`.
- **Combinators**: `allOf(...)`, `anyOf(...)`, `unless(...)`.
- **A bind**: `.bind("x")` tags a matched node with a name. The output can refer to it, whatever node the whole match expression returns.

## Recipes

| Question                                                          | Matcher                                                                   |
|---------------------------------------------------------------------|------------------------------------------------------------------------------|
| Every call to a specific function                                   | `callExpr(callee(functionDecl(hasName("foo"))))`                             |
| Every override of a virtual method                                   | `cxxMethodDecl(isOverride())`                                                |
| Every use of a specific type by name                                 | `declRefExpr(hasType(hasDeclaration(cxxRecordDecl(hasName("OldType")))))`     |
| Only the matches in the compiled file, not in the included headers   | add `isExpansionInMainFile()` to one of the above as a narrowing matcher     |

## Output control

- `set output dump`. Print the full AST dump of the matched nodes and the bound nodes.
- `set output print`. Print the matched source text instead of the AST structure.
- `set output diag`. Print only `file:line:col`, as a compiler diagnostic does.
- `set bind-root false`. Do not print the outermost matched node when only an inner node with a `.bind()` is of interest.
- `set traversal-kind IgnoreUnlessSpelledInSource`. Hide the implicit AST nodes (implicit casts, compiler-generated constructors) that otherwise clutter the matches against ordinary source code.

## Steps

1. Find the compilation database. Look for `compile_commands.json` in the working directory or in an obvious build directory (`build/`, `out/`). If there is none, ask the caller for one, or for the compiler flags to pass after `--`, per "Prerequisite" above.
2. Draft the narrowest matcher that can catch the requested pattern. Add `isExpansionInMainFile()`, unless the caller also wants the matches from the included headers.
3. Run it in batch mode against one representative file first: `clang-query -p <build-dir> -c "set output diag" -c 'match <matcher>' <file>`.
4. Read the result and adjust the matcher. Zero matches usually means that the flags or the matcher are wrong, not that the pattern is absent. Check the flags first, then widen the matcher. Too many matches means that the matcher needs another narrowing predicate.
5. Repeat steps 2 to 4 until the matches are exactly the intended set. Then run the matcher again across every file in the scope.
6. Report the final matcher expression, the match locations as `file:line:col`, and the exact command line. Thus the search can run again without a reconstruction.

## Rules that prevent rework

- **Always pass `-p <build-dir>` or the raw compiler flags after `--`.** With no real include paths and language standard, clang-query gives no loud error. It fails to build a complete AST, and the matchers return nothing, with no message.
- **Use batch mode (`-c` or `-f`), not the interactive prompt, for each scripted run.** The interactive REPL blocks on a prompt that a non-interactive caller cannot answer.
- **Start with the narrowest matcher, and widen it only on zero matches.** A bare `callExpr()` matches every call expression in the translation unit, with all that the headers pull in. Add `hasName(...)` or `isExpansionInMainFile()` before you widen the scope, not after.
- **Bind the node that matters, and turn off `bind-root` when the outer match is only context.** `set output dump` on an unbound, unfiltered match prints the whole matched subtree, which is usually far more than the answer needs.
