==============
For developers
==============

This chapter describes, at a high level, the internals of Snowflake.
Lower level help can be found in the form of comments in the source code.


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
