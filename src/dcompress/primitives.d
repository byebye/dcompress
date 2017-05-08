module dcompress.primitives;

import std.range.primitives : isInputRange, isOutputRange, ElementType;

public:

enum isCompressOutput(R) = (isOutputRange!(R, ubyte) || isOutputRange!(R, void[]));

enum isCompressInput(R) = (isInputRange!R && (is(ElementType!R == ubyte) || is(ElementType!R : void[])));

enum isCompressor(C) = __traits(compiles,
    (C c)
    { 
        C c2 = C.init;
        c2 = c; 
        auto data = "Data\n";
        c.compress(data);
        c.flush();
    });

enum isDecompressor(C) = __traits(compiles,
    (C c)
    { 
        C c2 = C.init;
        c2 = c; 
        auto data = "Data\n";
        c.decompress(data);
        c.flush();
    });

/+ Interfaces +/

interface Compressor
{
    const(void)[] compress(const(void)[] data);

    const(void)[] flush();
}

interface BufferredCompressor
{
    void compress(const(void)[] data);

    void flush();
}

interface Decompressor
{
    const(void)[] decompress(const(void)[] data);

    const(void)[] flush();
}

interface BufferredDecompressor
{
    void decompress(const(void)[] data);

    void flush();
}

