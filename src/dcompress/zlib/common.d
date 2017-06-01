/++
 + Contains common functionalities used by `dcompress.zlib` package.
 +/
module dcompress.zlib.common;

import c_zlib = etc.c.zlib;

package struct ZStreamWrapper
{
    c_zlib.z_stream zlibStream;
    ProcessingStatus status = ProcessingStatus.needsMoreInput;

    ~this()
    {
        c_zlib.deflateEnd(&zlibStream);
    }
}

package enum ProcessingStatus
{
    outputPending,
    needsMoreInput,
    finished
}

/++
 + Status codes returned by the zlib library.
 +/
package enum ZlibStatus
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

package string getErrorMessage(int status)
in
{
    // These are not errors.
    assert(status != ZlibStatus.ok);
    assert(status != ZlibStatus.streamEnd);
    assert(status != ZlibStatus.needDict);
}
body
{
     switch(status)
     {
        case ZlibStatus.bufferError:
            return "Buffer error";
        case ZlibStatus.streamError:
            return "Stream error";
        case ZlibStatus.dataError:
            return "Data error";
        case ZlibStatus.libVersionError:
            return "Incompatible zlib library version";
        case ZlibStatus.errno:
            return "Error outside the zlib library";
        default:
            return "Unknown error";
     }
}

/++
 + Exceptions thrown by this module on error.
 +/
class ZlibException : Exception
{
    this(int status)
    {
        super(getErrorMessage(status));
    }

    this(int status, const(char)* cause)
    {
        import std.conv : to;
        super(getErrorMessage(status) ~ ": " ~ to!string(cause));
    }
}

/++
 + Supported headers for the compressed data.
 +
 + The library supports only one compression method called `deflate`, which may
 + be wrapped around with `zlib` or `gzip` headers, including integrity check
 + values.
 +
 + The `zlib` format was designed to be compact and fast, for use in memory and
 + on communications channels, makes use of `Adler-32` for integrity check.
 + The `gzip` format was designed for a single file compression on file systems,
 + has a larger header than `zlib` to maintain file information, and uses
 + a slower `CRC-32` check method.
 +/
enum DataHeader
{
    /// zlib wrapper around a deflate stream. See the specification
    /// $(LINK2 https://tools.ietf.org/html/rfc1950, RFC 1950).
    zlib,
    /// Raw deflate stream, without any header or check value. See the
    /// specification $(LINK2 https://tools.ietf.org/html/rfc1951, RFC 1951).
    rawDeflate,
    /// gzip wrapper around a deflate stream. See the specification
    /// $(LINK2 https://tools.ietf.org/html/rfc1952, RFC 1952).
    gzip,
    /// Automatic header detection - only for decompressing.
    automatic
}

