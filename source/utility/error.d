// SPDX-License-Identifier: AGPL-3.0-only

module snowflake.utility.error;

/**
 * Subclass of `Exception` that wraps `UserError`.
 */
final
class UserException
    : Exception
{
    const(UserError) error;

    pure @safe
    this(
        const(UserError) error,
        string file = __FILE__,
        size_t line = __LINE__,
    )
    {
        super(error.message, file, line);
        this.error = error;
    }
}

/**
 * Base class for errors that might be caused by the user.
 * These errors can be formatted in a nice way
 * and are somewhat more structured than `Exception`
 * (which contains little more than a string message).
 */
interface UserError
{
pure @safe:

    /**
     * Short message explaining what went wrong.
     */
    string message() const;

    /**
     * More elaborate explanation of what went wrong.
     */
    void elaborate(scope UserErrorElaborator elaborator) const;
}

/**
 * Convenient template for defining user errors.
 *
 * The `Fields` parameter must be a sequence of alternating types and strings,
 * where the types are the field types and the strings are the field names.
 * For example, `Foo, "foo", Bar, "bar"` to create two fields foo and bar.
 */
template QuickUserError(
    string Message,
    Fields...,
)
{
    import std.typecons : Tuple, tuple;

    private
    alias FieldsTuple = Tuple!Fields;

    class QuickUserError
        : UserError
    {
    private:
        FieldsTuple fields;

    public:
        this(FieldsTuple.Types fields)
        {
            this.fields = FieldsTuple(fields);
        }

        string message() const scope =>
            Message;

        void elaborate(scope UserErrorElaborator elaborator) const
        {
            foreach (fieldName; FieldsTuple.fieldNames) {
                auto value = mixin("fields." ~ fieldName);
                elaborator.field(fieldName, value);
            }
        }
    }
}

/**
 * Used by `UserError.elaborate` to construct
 * a nicely formatted description of the error.
 */
abstract
class UserErrorElaborator
{
    import core.time : Duration;
    import std.conv : to;

pure @safe:

    /// Output the value of some field of the error.
    abstract
    void field(string name, string value) scope;

    /// ditto
    void field(string name, scope const(Exception) value) scope =>
        field(name, value.msg);

    /// ditto
    void field(string name, int value) scope =>
        field(name, value.to!string);

    /// ditto
    void field(string name, Duration value) scope =>
        field(name, value.toString);
}

/**
 * Format a user error for display in a terminal.
 */
pure @safe
string formatTerminal(const(UserError) error)
{
    import std.array : Appender;

    Appender!string result;

    final
    class TerminalElaborator
        : UserErrorElaborator
    {
        override pure @safe
        void field(string name, string value) scope
        {
            result ~= " -> ";
            result ~= name;
            result ~= " = ";
            result ~= value;
            result ~= "\n";
        }
    }

    result ~= error.message();
    result ~= "\n";
    error.elaborate(new TerminalElaborator());

    return result[];
}
