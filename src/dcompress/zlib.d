module dcompress.zlib;

import c_zlib = etc.c.zlib;

enum FlushMode
{
    noFlush = c_zlib.Z_NO_FLUSH,
    partial = c_zlib.Z_PARTIAL_FLUSH,
    sync    = c_zlib.Z_SYNC_FLUSH,
    full    = c_zlib.Z_FULL_FLUSH,
    finish  = c_zlib.Z_FINISH,
    block   = c_zlib.Z_BLOCK,
    trees   = c_zlib.Z_TREES,
}

enum ZlibStatus
{
    ok = c_zlib.Z_OK,
    streamEnd = c_zlib.Z_STREAM_END,
    needDict = c_zlib.Z_NEED_DICT,
    errno = c_zlib.Z_ERRNO,
    streamError = c_zlib.Z_STREAM_ERROR,
    dataError = c_zlib.Z_DATA_ERROR,
    memoryError = c_zlib.Z_MEM_ERROR,
    bufferError = c_zlib.Z_BUF_ERROR,
    libVersionError = c_zlib.Z_VERSION_ERROR,
}

enum CompressionMethod
{
    deflate = c_zlib.Z_DEFLATED,
}

enum CompressionLevel
{
    noCompression = c_zlib.Z_NO_COMPRESSION,
    bestSpeed = c_zlib.Z_BEST_SPEED,
    bestCompression = c_zlib.Z_BEST_COMPRESSION,
    default_ = c_zlib.Z_DEFAULT_COMPRESSION,
}

enum CompressionStrategy
{
    filtered = c_zlib.Z_FILTERED,
    huffman = c_zlib.Z_HUFFMAN_ONLY,
    rle = c_zlib.Z_RLE,
    fixed = c_zlib.Z_FIXED,
    default_ = c_zlib.Z_DEFAULT_STRATEGY,
}

enum CompressionEncoding
{
    deflate,
    rawDeflate,
    gzip,
}

struct Compressor
{
private:

    c_zlib.z_stream _zlibStream;
    ubyte[] _buffer;

    int getWindowBits(CompressionEncoding encoding)
    {
        switch (encoding)
        {
            case CompressionEncoding.deflate: return 15;
            case CompressionEncoding.rawDeflate: return -15;
            case CompressionEncoding.gzip: return 31;
            default: return 15;
        }
    }

    void throwException(ZlibStatus status)
    {
        // TODO status description
        throw new Exception("Error");
    }

    void checkForError(int status)
    {
        if (status != ZlibStatus.ok)
        {
            // c_zlib.deflateEnd(&_zlibStream); // TODO think about it.
            import std.conv : to;
            throwException(to!ZlibStatus(status));
        }
    }

    void initZlibStream(CompressionEncoding encoding, int compressionLevel)
    {
        // int deflateInit2(z_streamp strm, int level, int method, int windowBits, int memLevel, int strategy);
        // * windowsBits:
        //     default = 15
        //     8 - not supported
        //     9..15 - base 2 log of the window size
        //     -8..-15 - raw deflate, without zlib header or trailer and no crc
        //     27..31 = 16 + (9..15) - low 4 bits of the value is the window size log,
        //                             while including a basic gzip header and trailing checksum
        // * memLevel:
        //     default = 8
        //     1..9 - minimum memory + slow .. maximum memory + best speed
        // The memory requirements for deflate are (in bytes):
        //     (1 << (windowBits+2)) + (1 << (memLevel+9)) + 'a few'KB
        // The memory requirements for inflate are (in bytes):
        //     1 << windowBits + ~7KB
        immutable windowBits = getWindowBits(encoding);
        immutable memoryLevel = 8;
        immutable status = c_zlib.deflateInit2(&_zlibStream, compressionLevel, 
            CompressionMethod.deflate,
            windowBits, memoryLevel, CompressionStrategy.default_);
        checkForError(status);
    }

public:

    this(uint bufferSize,
        CompressionEncoding encoding = CompressionEncoding.deflate,
        int compressionLevel = CompressionLevel.default_)
    in
    {
        assert (-1 <= compressionLevel && compressionLevel <= 9);
    }
    body
    {
        _buffer = new ubyte[bufferSize];
        initZlibStream(encoding, compressionLevel);
    }

    ~this()
    {
        c_zlib.deflateEnd(&_zlibStream);
        // import core.memory : GC;
        // GC.free(_buffer.ptr);
    }

    @property bool outputAvailableCompress() const
    {
        uint bytes;
        // Casting away const here is safe as deflatePending does not modify the stream.
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*)&_zlibStream, &bytes, null);
        // This structure ensures a consistent state of the stream.
        assert (status == ZlibStatus.ok);
        return bytes > 0;
    }

    @property bool outputAvailableFlush() const
    {
        uint bytes;
        int bits;
        // Casting away const here is safe as deflatePending does not modify the stream.
        immutable status = c_zlib.deflatePending(cast(c_zlib.z_stream*)&_zlibStream, &bytes, &bits);
        // This structure ensures a consistent state of the stream.
        assert (status == ZlibStatus.ok);
        //import std.stdio : writefln;
        //writefln("bytes = %d, bits: %d",bytes, bits);
        return (bytes > 0 || bits > 0);
    }

    @property bool needsInput() const
    {
        //import std.stdio : writefln;
        //writefln("avail_in = %d, output available: %s",_zlibStream.avail_in, outputAvailableCompress);
        return _zlibStream.avail_in == 0 && !outputAvailableCompress;
    }

    const(void)[] compress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert (needsInput);
    }
    body
    {
        _zlibStream.next_in = cast(const(ubyte)*) data.ptr;
        _zlibStream.avail_in = cast(uint) data.length; // TODO check for overflow
        return continueCompress();
    }

    const(void)[] continueCompress(FlushMode mode = FlushMode.noFlush)
    {
        _zlibStream.next_out = _buffer.ptr;
        _zlibStream.avail_out = cast(uint) _buffer.length;

        // * ZlibStatus.ok -- progress has been made
        // * ZlibStatus.bufferError -- no progress possible
        // * ZlibStatus.streamEnd -- all input has been consumed and all output has been produced (only when mode == FlushMode.finish)
        import std.stdio : writefln;
        import std.conv :to;
        //writefln("--> avail_in = %d, avail_out: %d",_zlibStream.avail_in, _zlibStream.avail_out);
        immutable status = c_zlib.deflate(&_zlibStream, mode);

        //writefln("<-- avail_in = %d, avail_out: %d, status: %s",_zlibStream.avail_in, _zlibStream.avail_out, to!ZlibStatus(status));

        if (status != ZlibStatus.ok)
        {
            // TODO Think whether output buffer can be corrupted.
            if (mode == FlushMode.noFlush && status != ZlibStatus.bufferError
                || mode == FlushMode.finish && status != ZlibStatus.streamEnd)
            {
                import std.conv : to;
                throwException(to!ZlibStatus(status));
            }
        }

        immutable writtenBytes = _buffer.length - _zlibStream.avail_out;
        //import std.stdio : writefln;
        //writefln("Returning: %s", _buffer[0 .. writtenBytes]);
        return _buffer[0 .. writtenBytes];
    }

    const(void)[] flush(FlushMode mode = FlushMode.finish)
    {
        return continueCompress(mode);
    }
}
