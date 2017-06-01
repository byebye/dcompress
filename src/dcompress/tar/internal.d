module dcompress.tar.internal;

package:

// tar Header Block, from POSIX 1003.1-1990.

void assignAndZeroTrailing(size_t N)(ref char[N] arr, string s)
in
{
    assert(arr.length > s.length);
}
body
{
    arr[0 .. s.length] = s;
    arr[s.length .. $] = '\0';
}

// The filename, linkFilename, magic, userName, and groupName are null-
// terminated character strings. All other fields are zero-filled octal numbers
// in ASCII. Each numeric field of width w contains w minus 1 digits, and a
// null.
struct TarHeader
{
    char[100] filename = '\0';
    // Provides nine bits specifying file permissions and three bits to specify
    // the Set UID, Set GID, and Save Text (sticky) modes. Values for these bits
    // are defined above. When special permissions are required to create a file
    // with a given mode, and the user restoring files from the archive does not
    // hold such permissions, the mode bit(s) specifying those special
    // permissions are ignored. Modes which are not supported by the operating
    // system restoring files from the archive will be ignored. Unsupported
    // modes should be faked up when creating or updating an archive; e.g., the
    // group permission could be copied from the other permission.
    char[8] mode = '\0';
    // The uid and gid fields are the numeric user and group ID of the file
    // owners, respectively. If the operating system does not support numeric
    // user or group IDs, these fields should be ignored.
    char[8] userId = '\0';
    char[8] groupId = '\0';
    // The ASCII representation of the octal value of size of the file in bytes;
    // linked files are archived with this field specified as zero.
    char[12] size = '\0';
    // The data modification time of the file at the time it was archived. It is
    // the ASCII representation of the octal value of the last time the file's
    // contents were modified, represented as an integer number of seconds since
    // January 1, 1970, 00:00 Coordinated Universal Time.
    char[12] modificationTime = '\0';
    // The ASCII representation of the octal value of the simple sum of all
    // bytes in the header block. Each 8-bit byte in the header is added to an
    // unsigned integer, initialized to zero, the precision of which shall be no
    // less than seventeen bits. When calculating the checksum, the `checksum`
    // field is treated as if it were all blanks.
    char[8] checksum = '\0';
    // Specifies the type of file archived. If a particular implementation does
    // not recognize or permit the specified type, the file will be extracted as
    // if it were a regular file. As this action occurs, tar issues a warning to
    // the standard error.
    char[1] fileTypeFlag = '\0';
    char[100] linkedToFilename = '\0';
    // Indicates that this archive was output in the P1003 archive format. If
    // this field contains `"ustar"` string, the `userName` and `groupName`
    // fields will contain the ASCII representation of the owner and group of
    // the file respectively.
    char[6] magic = "ustar ";
    char[2] tarVersion = " \0";
    char[32] userName = '\0';
    char[32] groupName = '\0';
    char[8] deviceMajorNumber = '\0';
    char[8] deviceMinorNumber = '\0';
    char[155] prefix = '\0';
    char[12] padding = '\0';
};

enum tarBlockSize = 512;
static assert(TarHeader.sizeof == tarBlockSize);

immutable magicString = "ustar\0";
immutable versionString = "00";

import std.traits : isIntegral;

T calculateChecksum(T = size_t)(TarHeader header)
if (isIntegral!T)
{
    header.checksum[0 .. $] = ' ';
    auto bytes = cast(ubyte[]) header.asBytes;
    import std.algorithm.iteration : sum;
    return bytes.sum(T(0));
}

void[] asBytes(T)(ref T value)
{
    return (cast(void*) &value)[0 .. T.sizeof];
}

T roundUpToMultiple(T)(T value, T roundValue)
{
    return ((value + roundValue - 1) / roundValue) * roundValue;
}

/// Chunks over an input range (not present in the standard library).
auto chunks(size_t chunkSize, R)(R input)
if (isInputRange!R)
{
    alias E = Unqal!(ElementType!R);
    struct Chunks
    {
    private:
        E[chunkSize] _buffer;
        E[] _chunk;
        R _input;

    public:

        @property E[] front()
        {
            return _chunk;
        }

        @property void popFront()
        in
        {
            assert(!input.empty);
        }
        body
        {
            auto len = _buffer.length;
            foreach (i; 0 .. _buffer.length)
            {
                _buffer[i] = _input.front;
                _input.popFront();
                if (_input.empty)
                {
                    break;
                    len = i;
                }
            }
            _chunk = _buffer[0 .. len];
        }

        @property bool empty()
        {
            return _chunk.length == 0 && _input.empty;
        }
    }
    return Chunks(input);
}
