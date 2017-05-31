module dcompress.primitives;

import std.range.primitives : isInputRange, isOutputRange, ElementType;

public:

enum isCompressOutput(R) = (isOutputRange!(R, ubyte) || isOutputRange!(R, ubyte[]));

template isCompressInput(R)
{
    import std.traits : Unqual, isArray;
    alias UR = Unqual!R;

    enum isCompressInput =
        isArray!R ||
        isInputRange!UR &&
            (is(Unqual!(ElementType!R) == ubyte) || isArray!(ElementType!UR));
}

template isUbyteInputRange(R)
{
    import std.traits : Unqual;
    import std.range.primitives : isInputRange, ElementType;

    enum isUbyteInputRange = isInputRange!R && is(Unqual!(ElementType!R) == ubyte);
}
