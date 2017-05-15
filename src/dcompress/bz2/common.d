/++
 + Contains common functionalities used by `dcompress.bz2` package.
 +/
module dcompress.bz2.common;

import c_bz2 = dcompress.etc.c.bz2;

package enum Bz2Action
{
    run = c_bz2.BZ_RUN,
    flush = c_bz2.BZ_FLUSH,
    finish = c_bz2.BZ_FINISH,
}

/++
 + Status codes returned by the libbzip2 library.
 +/
package enum Bz2Status
{
    ok = c_bz2.BZ_OK,
    runOk = c_bz2.BZ_RUN_OK,
    flushOk = c_bz2.BZ_FLUSH_OK,
    finishOk = c_bz2.BZ_FINISH_OK,
    streamEnd = c_bz2.BZ_STREAM_END,
    // Errors
    sequenceError = c_bz2.BZ_SEQUENCE_ERROR,
    paramError = c_bz2.BZ_PARAM_ERROR,
    memoryError = c_bz2.BZ_MEM_ERROR,
    dataError = c_bz2.BZ_DATA_ERROR,
    dataErrorMagic = c_bz2.BZ_DATA_ERROR_MAGIC,
    ioError = c_bz2.BZ_IO_ERROR,
    unexpectedEof = c_bz2.BZ_UNEXPECTED_EOF,
    outputBufferFull = c_bz2.BZ_OUTBUFF_FULL,
    configError = c_bz2.BZ_CONFIG_ERROR,
}

package string getErrorMessage(int status)
in
{
    // These are not errors.
    assert(status != Bz2Status.ok);
    assert(status != Bz2Status.runOk);
    assert(status != Bz2Status.flushOk);
    assert(status != Bz2Status.finishOk);
    assert(status != Bz2Status.streamEnd);
}
body
{
     switch(status)
     {
        case Bz2Status.sequenceError:
            return "Invalid sequence of function invocations";
        case Bz2Status.paramError:
            return "Invalid parameter passed to the function";
        case Bz2Status.memoryError:
            return "Not enough memory";
        case Bz2Status.dataError:
            return "Data integrity error";
        case Bz2Status.dataErrorMagic:
            return "Data does not start with bzip2 magic bytes";
        case Bz2Status.ioError:
            return "I/O error";
        case Bz2Status.unexpectedEof:
            return "Unexpected end of file";
        case Bz2Status.outputBufferFull:
            return "Not enough space in the output buffer";
        case Bz2Status.configError:
            return "Config error - library improperly compiled";
        default:
            return "Unknown error";
     }
}

/++
 + Exceptions thrown by this module on error.
 +/
class Bz2Exception : Exception
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
