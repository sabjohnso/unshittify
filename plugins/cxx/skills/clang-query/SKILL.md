---
description: Query and explore a C++ codebase's abstract syntax tree with clang-query, using Clang's AST matcher language to find every occurrence of a structural pattern — a call to a specific function, every override of a virtual method, every use of a deprecated type — precisely, rather than approximating it with a text search. Covers compilation-database setup, batch vs. interactive invocation, matcher syntax, and output control. Use when the user asks to find, locate, or search for a C++ code pattern structurally, or to write or debug a clang-tidy check matcher.
allowed-tools: Bash(clang-query:*), Read, Grep, Glob
---

# Querying the AST with clang-query

clang-query runs Clang's AST matcher language — the same matcher DSL used to write clang-tidy checks and Tooling library passes — against real, compiled C++ source, so a structural pattern can be searched for precisely instead of approximated with a text search or regex.

## Prerequisites: a compilation database

clang-query needs the same include paths, defines, and language standard the file was actually compiled with, or it will fail to parse a complete AST.

- With CMake, configure with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`; this produces `compile_commands.json` in the build directory. Point clang-query at it with `-p <build-dir>`.
- With a build system that doesn't emit one directly, generate it with `bear -- <build command>` (Bear) or `intercept-build <build command>`.
- Without a compilation database, pass the compiler flags directly after `--`: `clang-query file.cpp -- -std=c++20 -Iinclude`.

## Running: batch vs. interactive

- **Batch (scriptable)** — pass one or more `-c "<command>"` flags, or `-f <command-file>`, and clang-query runs them in sequence and exits:
  ```sh
  clang-query -p build -c "set output dump" -c 'match functionDecl(hasName("foo"))' file.cpp
  ```
  Prefer this form when running clang-query as part of a scripted search: the interactive REPL (Read-Eval-Print Loop) waits on a prompt that a headless invocation cannot answer.
- **Interactive** — run `clang-query -p build file.cpp` with no `-c`/`-f` flags to get a prompt, then type `match <matcher>` (or `m` for short) directly, iterating on the matcher expression until it captures the intended pattern.

## Matcher language

- **Node matchers** select AST nodes by kind, named in camelCase after the underlying Clang node type: `functionDecl`, `cxxRecordDecl`, `varDecl`, `callExpr`, `cxxMemberCallExpr`, `binaryOperator`, `ifStmt`, `cxxNewExpr`.
- **Narrowing matchers** take the outer matcher as an argument and restrict which nodes of that kind match: `hasName("...")`, `hasType(...)`, `isConstexpr()`, `hasParameter(...)`, `isOverride()`.
- **Traversal matchers** cross node boundaries to match based on context: `hasParent(...)`, `hasAncestor(...)`, `hasDescendant(...)`, `forEachDescendant(...)`.
- **Combinators**: `allOf(...)`, `anyOf(...)`, `unless(...)`.
- **Binding**: `.bind("x")` tags a matched node with a name so it can be referenced in output, independent of which node the overall match expression returns.

## Recipes

| Question                                                          | Matcher                                                                   |
|---------------------------------------------------------------------|------------------------------------------------------------------------------|
| Every call to a specific function                                   | `callExpr(callee(functionDecl(hasName("foo"))))`                             |
| Every override of a virtual method                                   | `cxxMethodDecl(isOverride())`                                                |
| Every use of a specific type by name                                 | `declRefExpr(hasType(hasDeclaration(cxxRecordDecl(hasName("OldType")))))`     |
| Matches confined to the file being compiled, not included headers    | add `isExpansionInMainFile()` to any of the above as a narrowing matcher     |

## Output control

- `set output dump` — print the full AST dump of the matched (and any bound) nodes.
- `set output print` — pretty-print the matched source text instead of the AST structure.
- `set output diag` — print only `file:line:col`, like a compiler diagnostic.
- `set bind-root false` — suppress printing the outermost matched node when only a `.bind()`ed inner node is of interest.
- `set traversal-kind IgnoreUnlessSpelledInSource` — hide implicit AST nodes (implicit casts, compiler-generated constructors) that otherwise clutter matches against ordinary source code.

## Rules that prevent rework

- **Always pass `-p <build-dir>` or the raw compiler flags after `--`.** Without the real include paths and language standard, clang-query does not error loudly — it fails to build a complete AST, and matchers silently return nothing.
- **Use batch mode (`-c`/`-f`), not the interactive prompt, for anything scripted.** The interactive REPL blocks on a prompt that a non-interactive caller cannot answer.
- **Start with the narrowest matcher and broaden only on zero matches.** A bare `callExpr()` matches every call expression in the translation unit, including everything pulled in from headers; add `hasName(...)` or `isExpansionInMainFile()` before widening scope, not after.
- **Bind the node that actually matters, and turn off `bind-root` when the outer match is just context.** `set output dump` on an unbound, unfiltered match prints the entire matched subtree — usually far more than needed to answer the question.
