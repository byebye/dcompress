import std.stdio : File;


interface Archive {
    
    void compress(void[] data, int compressionLevel = 9);

    void decompress(void[] data);

}

/+ File +/
struct CompressedFile(Compressor, Decompressor)
if (isCompressor!Compressor && isDecompressor!Decompressor)
{
private:
    import std.stdio : File;
    File _file;
    Compressor _compressor;
    Decompressor _decompressor;

public:
    this(string filename, in char[] openMode = "rb") @safe
    {
        _file = File(filename, openMode);
    }

    /+
    this(R1, R2)(R1 name)
    if (isInputRange!R1 && isSomeChar!(ElementEncodingType!R1))
    {
        _file = File(name);
    }

    this(R1, R2)(R1 name, R2 openMode)
    if (isInputRange!R1 && isSomeChar!(ElementEncodingType!R1)
        && isInputRange!R2 && isSomeChar!(ElementEncodingType!R2))
    {
        _file = File(name, openMode);
    }
    +/

    void opAssign(CompressedFile rhs) @safe
    {
        _file = rhs.file;
        _compressor = rhs._compressor;
        _decompressor = rhs._decompressor;
    }

    void open(string filename, in char[] openMode = "rb") @safe
    {
        _file.open(filename, openMode);
    }
}

