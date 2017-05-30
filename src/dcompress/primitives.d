module dcompress.primitives;

import std.range.primitives : isInputRange, isOutputRange, ElementType;

public:

enum isCompressOutput(R) = (isOutputRange!(R, ubyte) || isOutputRange!(R, const(void)[]));

template isCompressInput(R)
{
    import std.traits : Unqual, isArray;
    alias UR = Unqual!R;

    enum isCompressInput =
        isArray!R ||
        isInputRange!UR &&
            (is(Unqual!(ElementType!R) == ubyte) || isArray!(ElementType!UR));
}


struct FileOutputRange
{
private:
    import std.stdio : File;

    File _file;

public:

    this(File file)
    {
        _file = file;
        _file.reopen(null, "a");
    }

    this(File file, size_t pos = 0)
    {
        _file = file;
        _file.seek(pos);
    }

    void put(const(void)[] data)
    {
        _file.rawWrite(data);
    }
}

