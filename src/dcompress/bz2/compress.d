/++
 + Provides decompressing abstractions for zlib format.
 +/
module dcompress.bz2.compress;

import c_bz2 = dcompress.etc.c.bz2;
public import dcompress.bz2.common;

struct CompressionPolicy
{
private:

    import std.typecons : Nullable;

    Nullable!(void[]) _buffer;
    int _blockSize = 6;
    int _verbosity = 0;
    int _workFactor = 30;
    size_t _defaultBufferSize = 1024;
    size_t _maxInputChunkSize = 1024;

public:

    @property size_t defaultBufferSize() const
    {
        return _defaultBufferSize;
    }

    @property void defaultBufferSize(size_t newSize)
    in
    {
        assert(newSize > 0);
    }
    body
    {
         _defaultBufferSize = newSize;
    }

    @property size_t maxInputChunkSize() const
    {
        return _maxInputChunkSize;
    }

    @property void maxInputChunkSize(size_t newMaxChunkSize)
    in
    {
        assert(0 < newMaxChunkSize && newMaxChunkSize <= 4 * 1024UL ^^ 3);
    }
    body
    {
         _maxInputChunkSize = newMaxChunkSize;
    }

    @property int blockSize() const
    {
        return _blockSize;
    }

    @property void blockSize(int newSize)
    in
    {
        assert(1 <= newSize && newSize <= 9);
    }
    body
    {
        _blockSize = newSize;
    }

    @property int verbosityLevel() const
    {
        return _verbosity;
    }

    @property void verbosityLevel(int newVerbosity)
    in
    {
        assert(0 <= newVerbosity && newVerbosity <= 4);
    }
    body
    {
        _verbosity = newVerbosity;
    }

    @property int workFactor() const
    {
        return _workFactor;
    }

    @property void workFactor(int newWorkFactor)
    in
    {
        assert(0 <= newWorkFactor && newWorkFactor <= 250);
    }
    body
    {
        _workFactor = newWorkFactor;
    }

    @property inout(Nullable!(void[])) buffer() inout
    {
        return _buffer;
    }

    @property void buffer(Nullable!(void[]) newBuffer)
    in
    {
        assert(newBuffer.isNull || newBuffer.get.length > 0);
    }
    body
    {
        _buffer = newBuffer;
    }

    @property void buffer(void[] newBuffer)
    in
    {
        assert(newBuffer.length > 0);
    }
    body
    {
        _buffer = newBuffer;
    }
}

struct Compressor
{
private:

    c_bz2.bz_stream _bzStream;
    CompressionPolicy _policy;
    enum Status : ubyte
    {
        idle,
        running,
        finishing
    }
    Status _status = Status.idle;

    size_t totalBytesIn() const
    {
        return (size_t(_bzStream.total_in_hi32) << 32) + _bzStream.total_in_lo32;
    }

    size_t totalBytesOut() const
    {
        return (size_t(_bzStream.total_out_hi32) << 32) + _bzStream.total_out_lo32;
    }

public:

    @disable this();

    ~this()
    {
        c_bz2.BZ2_bzCompressEnd(&_bzStream);
    }

    Compressor create(CompressionPolicy policy = CompressionPolicy.init)
    {
        auto comp = Compressor.init;

        if (policy.buffer.isNull)
            policy.buffer = new ubyte[policy.defaultBufferSize];
        comp._policy = policy;

        return comp;
    }

    @property const(CompressionPolicy) policy() const
    {
        return _policy;
    }

    private @property void[] buffer()
    {
         return _policy.buffer.get;
    }

    @property bool outputPending() const
    {
        return _status == Status.finishing ||
            (_status == Status.running && !inputProcessed);
    }

    @property bool inputProcessed() const
    {
         return _bzStream.avail_in == 0;
    }

    @property void input(const(void)[] data)
    {
        if (_status == Status.idle)
            initStream();
        _bzStream.next_in = cast(ubyte*) data.ptr;
        _bzStream.avail_in = cast(uint) data.length; // TODO check for overflow
    }

    private void initStream()
    {
        auto status = c_bz2.BZ2_bzCompressInit(
            &_bzStream,
            policy.blockSize,
            policy.verbosityLevel,
            policy.workFactor);

        if (status != Bz2Status.ok)
            throw new Bz2Exception(status);

        _status = Status.running;
    }

    const(void)[] compress(const(void)[] data)
    in
    {
        // Ensure no leftovers from previous calls.
        assert(inputProcessed);
    }
    body
    {
        input = data;
        return compressPending();
    }

    const(void)[] compressPending()
    {
        return compress(Bz2Action.run);
    }

    const(void)[] flush()
    {
        return compress(Bz2Action.finish);
    }

    private const(void)[] compress(Bz2Action action)
    {
        _bzStream.next_out = cast(ubyte*) buffer.ptr;
        _bzStream.avail_out = cast(uint) buffer.length;

        auto status = c_bz2.BZ2_bzCompress(&_bzStream, action);

        if (status == Bz2Status.streamEnd)
        {
            _status = Status.idle;
            status = c_bz2.BZ2_bzCompressEnd(&_bzStream);
            assert(status == Bz2Status.ok);
        }
        else if (!isOk(action, status))
            throw new Bz2Exception(status);

        if (action == Bz2Action.finish)
            _status = Status.finishing;

        immutable writtenBytes = buffer.length - _bzStream.avail_out;
        return buffer[0 .. writtenBytes];
    }

    private bool isOk(Bz2Action action, int status)
    {
        final switch (action) with (Bz2Action)
        {
            case run: return (status == Bz2Status.runOk);
            case finish: return (status == Bz2Status.finishOk);
            case flush: return (status == Bz2Status.flushOk);
        }
    }
}
