=================
Design principles
=================

The design of Snowflake is heavily inspired by that of `Bazel`_.
Snowflake is designed with the following requirements in mind:

 - Snowflake can be used to run any compiler (with reasonable limits)
   and does not attach special meaning to contents of source files.

 - The cache key identifying an action includes:
    - the declared inputs to the action;
    - implicit dependencies (such as ``/bin/sh``);
    - computer information such as instruction set architecture; and
    - the build command of the action.

 - An action can depend on individual outputs of another action,
   without depending on other outputs of that action.

 - Actions are run in sandboxed environments.
   An action can only access the Nix store
   and files that are part of its cache key.
   Snowflake fully implements the sandbox environment runtime;
   there is no dependency on Docker or similar systems.

 - The evaluation of build files, as well as the execution of actions,
   run in parallel if parallelism is available on the computer.

 - Snowflake can identify compiler warnings and cache them.
   Warnings are displayed even if the build is skipped due to a cache hit.
   Snowflake can treat warnings as errors if the user requests this,
   without passing ``-Werror`` or equivalent flags to the compiler.
   The user can specify a regular expression to match warning lines.


Non-goals
---------

 - Snowflake working without Nix.
 - Snowflake working on unfree operating systems.
 - Using Snowflake to manage third-party dependencies.


.. _Bazel: https://bazel.build
