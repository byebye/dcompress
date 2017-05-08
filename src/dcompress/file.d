module dcompress.file;

import std.stdio : File;


interface Archive {

    void compress(void[] data, int compressionLevel = 9);

    void decompress(void[] data);

}

/+ File +/
struct CompressedFile(CompressAlgorithm)
// if (isCompressAlgorithm!CompressAlgorithm)
{
private:
    import std.stdio : File;
    File _file;
    CompressAlgorithm _compress;
    // byte[] buffer;

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
        _compress = rhs._compress;
    }
/+
    void open(string filename, in char[] openMode = "rb") @safe
    {
        _file.open(filename, openMode);
    }

    void reopen(string name, in char[] stdioOpenmode = "rb") @trusted;

    @safe void popen(string command, in char[] stdioOpenmode = "r");

    @safe void fdopen(int fd, in char[] stdioOpenmode = "rb");

    void windowsHandleOpen(HANDLE handle, in char[] stdioOpenmode);
+/
    const pure nothrow @property @safe bool isOpen();

    const pure @property @trusted bool eof();

    const pure nothrow @property @safe string name();

//    const pure nothrow @property @trusted bool error();

    @safe void detach();

    @trusted void close();

//    pure nothrow @safe void clearerr();

    @trusted void flush();

    @trusted void sync();
/+
    T[] rawRead(T)(T[] buffer);

    void rawWrite(T)(in T[] buffer);

    @trusted void seek(long offset, int origin = SEEK_SET);

    const @property @trusted ulong tell();

    @safe void rewind();

    @trusted void setvbuf(size_t size, int mode = _IOFBF);

    @trusted void setvbuf(void[] buf, int mode = _IOFBF);

    void lock(LockType lockType = LockType.readWrite, ulong start = 0, ulong length = 0);

    bool tryLock(LockType lockType = LockType.readWrite, ulong start = 0, ulong length = 0);

    void unlock(ulong start = 0, ulong length = 0);

    void write(S...)(S args);

    void writeln(S...)(S args);

    void writef(alias fmt, A...)(A args)
    if (isSomeString!(typeof(fmt)));

    void writef(Char, A...)(in Char[] fmt, A args);

    void writefln(alias fmt, A...)(A args)
    if (isSomeString!(typeof(fmt)));

    void writefln(Char, A...)(in Char[] fmt, A args);

    S readln(S = string)(dchar terminator = '\x0a')
    if (isSomeString!S);

    size_t readln(C)(ref C[] buf, dchar terminator = '\x0a')
    if (isSomeChar!C && is(Unqual!C == C) && !is(C == enum));

    size_t readln(C, R)(ref C[] buf, R terminator)
    if (isSomeChar!C && is(Unqual!C == C) && !is(C == enum) && isBidirectionalRange!R && is(typeof(terminator.front == (dchar).init)));

    uint readf(alias format, Data...)(auto ref Data data)
    if (isSomeString!(typeof(format)));

    uint readf(Data...)(in char[] format, auto ref Data data);

    static @safe File tmpfile();

    static @safe File wrapFile(FILE* f);

    pure @safe FILE* getFP();

    const @property @trusted int fileno();

    @property HANDLE windowsHandle();
+/
    @property @safe ulong size();
/+
    auto byLine(Terminator = char, Char = char)(KeepTerminator keepTerminator = No.keepTerminator, Terminator terminator = '\x0a')
    if (isScalarType!Terminator);

    auto byLine(Terminator, Char = char)(KeepTerminator keepTerminator, Terminator terminator)
    if (is(Unqual!(ElementEncodingType!Terminator) == Char));

    auto byLineCopy(Terminator = char, Char = immutable(char))(KeepTerminator keepTerminator = No.keepTerminator, Terminator terminator = '\x0a')
    if (isScalarType!Terminator);

    auto byLineCopy(Terminator, Char = immutable(char))(KeepTerminator keepTerminator, Terminator terminator)
    if (is(Unqual!(ElementEncodingType!Terminator) == Unqual!Char));

    ByRecord!Fields byRecord(Fields...)(string format);

    ByChunk byChunk(size_t chunkSize);

    ByChunk byChunk(ubyte[] buffer);

    @safe auto lockingTextWriter();

    auto lockingBinaryWriter();
+/
}

