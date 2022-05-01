==============
For developers
==============

This chapter describes, at a high level, the internals of Snowflake.
Lower level help can be found in the form of comments in the source code.


Building
--------

Snowflake is currently built using a Bash script.
To create a non-optimized build, run the following command:

.. code:: bash

   nix-shell --pure --run script/build

The output appears in the ``build`` directory.


Context
-------

A *context* object is passed throughout the code base.
This object provides access to the state directory (commonly ``.snowflake``)
and has many useful methods for manipulating the state directory.


Containers
----------

To ensure hermetic builds, Snowflake implements containers.
Performing a run action spawns a container for running the command.
The container is implemented using ``clone3`` and ``chroot``,
using the Linux namespace features for isolation from the parent.


User errors
-----------

Errors that could be traced back to user input are called *user errors*.
This includes syntax errors in build files, failing builds, and so on.
But it does not include Snowflake bugs or unexpected system errors.
Infrastructure for creating and reporting user errors
can be found in the ``snowflake.utility.error`` module.


The os module
-------------

The module ``snowflake.utility.os`` wraps system calls in a safe D interface.
This module is to be used in place of wrapped system calls in Phobos,
including the ``std.file`` module, for the following reasons:

- The ``os`` module uses the exact same behavior as described in the man pages,
  apart from D-isms like throwing exceptions on failure.
  This makes it easier to understand what precisely happens.

- Phobos does not expose many system calls that we like to use,
  such as the ``*at`` family of system calls that take directory handles.

- Phobos does not set the ``CLOEXEC`` flag on every new file descriptor.
  Setting this flag atomically is crucial in a multi-threaded program,
  to avoid a race condition when another thread calls ``fork``.

There is also a module ``snowflake.utility.command``.
Use this module in place of ``std.process``, for similar reasons.
