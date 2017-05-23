/++
 +
 +/
module dcompress.tar;

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


    static size_t calculateChecksum(TarHeader header)
    {
        header.checksum[0 .. $] = ' ';
        auto bytes = cast(ubyte[]) (cast(void*) &header)[0 .. TarHeader.sizeof];
        import std.algorithm.iteration : sum;
        return bytes.sum;
    }
};

static assert(TarHeader.sizeof == 512);

immutable magicString = "ustar\0";
immutable versionString = "00";

/// Values used in `TarHeader.fileTypeFlag` field.
enum FileType : char
{
    regular = '0',
    regularCompatibility = '\0',
    // This flag represents a file linked to another file, of any type,
    // previously archived. Such files are identified in Unix by each file
    // having the same device and inode number. The linked-to name is specified
    // in the `TarHeader.linkedToFilename`.
    hardLink = '1',
    // This represents a symbolic link to another file. The linked-to name is
    // specified in the `TarHeader.linkedToFilename`.
    symbolicLink = '2',
    // These represent character special files and block special files
    // respectively. In this case the `TarHeader.deviceMajorNumber` and
    // `TarHeader.deviceMinorNumber` fields will contain the major and minor
    // device numbers respectively. Operating systems may map the device
    // specifications to their own local specification, or may ignore the entry.
    characterSpecial = '3',
    blockSpecial = '4',
    // This flag specifies a directory or sub-directory. The directory name in
    // the `TarHeader.filename` field should end with a slash. On systems where
    // disk allocation is performed on a directory basis, the `TarHeader.size`
    // field will contain the maximum number of bytes (which may be rounded to
    // the nearest disk block allocation unit) which the directory may hold. A
    // size field of zero indicates no such limiting. Systems which do not
    // support limiting in this manner should ignore the size field.
    directory = '5',
    // This specifies a FIFO special file. Note that the archiving of a FIFO
    // file archives the existence of this file and not its contents.
    fifoSpecial = '6',
    // This specifies a contiguous file, which is the same as a normal file
    // except that, in operating systems which support it, all its space is
    // allocated contiguously on the disk. Operating systems which do not allow
    // contiguous allocation should silently treat this type as a normal file.
    contiguous = '7',
    // Extended header referring to the next file in the archive.
    extendedHeaderNext = 'x',
    // Global extended header
    extendedHeaderGlobal = 'g',
}

string toString(T)(auto ref T value)
{
    import std.format : formattedWrite;
    import std.array : appender;
    auto writer = appender!string();
    foreach (i, ref field; value.tupleof)
    {
        formattedWrite(writer, "%s: '%s'\n", __traits(identifier, value.tupleof[i]), field);
    }
    return writer.data;
}

/// Bits used in the `TarHeader.mode` field, values in octal.
struct FileMode
{
    alias siUint = static immutable(uint);
    import std.conv : octal;
    /// set user ID upon execution
    siUint setUid  = octal!4000;
    /// set group ID upon execution
    siUint setGid  = octal!2000;
    /// sticky bit
    siUint restrictedDeletion = octal!1000;

    siUint ownerRead  = octal!400;
    siUint ownerWrite = octal!200;
    siUint ownerExec  = octal!100;

    siUint groupRead  = octal!40;
    siUint groupWrite = octal!20;
    siUint groupExec  = octal!10;

    siUint otherRead  = octal!4;
    siUint otherWrite = octal!2;
    siUint otherExec  = octal!1;
}


class TarException : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

T octalParse(T)(char[] slice)
{
    import std.conv : parse;
    return parse!T(slice, 8);
}

import std.stdio;

struct TarMember
{
    import std.datetime : SysTime;

    string filename;
    string linkedToFilename;
    FileType fileType;
    size_t size;
    uint mode;
    uint userId;
    uint groupId;
    string userName;
    string groupName;
    uint deviceMajorNumber;
    uint deviceMinorNumber;
    SysTime modificationTime;
    ubyte[] content;

    this(TarHeader header)
    {
        import std.string : fromStringz;
        import std.path : buildNormalizedPath, isValidPath;

        filename = buildNormalizedPath(
            fromStringz(header.prefix.ptr), fromStringz(header.filename.ptr));

        assert(filename.isValidPath);

        linkedToFilename = fromStringz(header.linkedToFilename.ptr).idup;

        import std.conv : to;
        fileType = to!FileType(header.fileTypeFlag[0]);

        size = octalParse!size_t(header.size[]);
        mode = octalParse!uint(header.mode[]);
        userId = octalParse!uint(header.userId[]);
        groupId = octalParse!uint(header.groupId[]);

        userName = fromStringz(header.userName.ptr).idup;
        groupName = fromStringz(header.groupName.ptr).idup;

        deviceMajorNumber = octalParse!uint(header.deviceMajorNumber[]);
        deviceMinorNumber = octalParse!uint(header.deviceMinorNumber[]);

        auto unixTime = octalParse!long(header.modificationTime[]);
        modificationTime = SysTime.fromUnixTime(unixTime);
    }

    TarHeader toTarHeader() const
    {
        TarHeader header;

        assert (filename.length < header.filename.sizeof + header.prefix.sizeof);

        string withTrailingSlash(string path)
        {
            if (path.length == 0 || path == "/")
                return path;
            return path ~= "/";
        }

        if (filename.length >= header.filename.sizeof)
        {
            import std.path : dirName, baseName;
            auto dir = withTrailingSlash(filename.dirName);
            auto base = filename.baseName;
            if (fileType == FileType.directory)
                base = withTrailingSlash(base);

            assert (dir.length < header.prefix.sizeof && base.length < header.filename.sizeof);

            header.prefix.assignAndZeroTrailing(dir);
            header.filename.assignAndZeroTrailing(base);
        }
        else
        {
            auto f = (fileType == FileType.directory) ? withTrailingSlash(filename) : filename;
            header.filename.assignAndZeroTrailing(f);
        }

        header.linkedToFilename.assignAndZeroTrailing(linkedToFilename);

        header.fileTypeFlag[0] = fileType;

        void octalFormat(T)(char[] dest, T n)
        {
            import std.format : sformat;
            // Size == 5 is sufficient - 1 or 2 digits only
            char[5] fmt;
            sformat(fmt, "%%0%02do", dest.length - 1);
            sformat(dest, fmt, n);
        }

        octalFormat(header.size[], size);
        octalFormat(header.mode[], mode);
        octalFormat(header.userId[], userId);
        octalFormat(header.groupId[], groupId);

        header.userName.assignAndZeroTrailing(userName);
        header.groupName.assignAndZeroTrailing(groupName);

        if (fileType == FileType.characterSpecial || fileType == FileType.blockSpecial)
        {
            octalFormat(header.deviceMajorNumber[], deviceMajorNumber);
            octalFormat(header.deviceMinorNumber[], deviceMinorNumber);
        }

        auto unixTime = modificationTime.toUnixTime();
        octalFormat(header.modificationTime[], unixTime);

        octalFormat(header.checksum[0 .. $ - 1], TarHeader.calculateChecksum(header));
        header.checksum[$ - 1] = ' ';

        return header;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.conv : to;
        foreach (i, ref field; this.tupleof)
        {
            sink(__traits(identifier, this.tupleof[i]));
            sink(": ");
            sink(to!string(field));
            sink("\n");
        }
    }
}

T roundUpToMultiple(T)(T value, T roundValue)
{
    return ((value + roundValue - 1) / roundValue) * roundValue;
}

enum isPredicate(T) = __traits(compiles, () { if (filter(T.init)) {} });


struct TarFile
{
    import std.stdio : File, writeln;

private:

    TarMember[string] _members;
    File _file;
    size_t _endBlocksPos;
    size_t _blockingFactor = 20; // number of records per block

public:

    static TarFile open(string path, in char[] openMode = "rb")
    {
        TarFile tarFile;
        tarFile._file = File(path, openMode);

        auto file = &tarFile._file;

        char[TarHeader.sizeof] buffer;

        while (!file.eof)
        {
            auto headerBytes = file.rawRead(buffer[]);
            if (headerBytes[0] == '\0')
            {
                tarFile._endBlocksPos = file.tell() - TarHeader.sizeof;
                writeln("End of tar archive.");
                auto left = file.size() - tarFile._endBlocksPos;
                writeln("Padding left: ", left, " bytes, ", left / 512, " blocks from total of ", file.size() / 512);
                assert(left % 512 == 0);
                file.seek(0);
                break;
            }
            if (headerBytes.length < buffer.length)
                throw new TarException("Not enough bytes read for tar header.");

            TarHeader tarHeader;
            foreach (i, ref field; tarHeader.tupleof[0 .. $ - 1])
            {
                field = headerBytes[0 .. field.sizeof];
                headerBytes = headerBytes[field.sizeof .. $];
                //writeln(__traits(identifier, tarHeader.tupleof[i]), ": '", field, "'");
            }


            writeln(cast(void[]) tarHeader.checksum[]);
            writeln("checksum: ", octalParse!uint(tarHeader.checksum),
                " vs calculated: ", TarHeader.calculateChecksum(tarHeader));

            auto member = TarMember(tarHeader);


             writeln("************************************");
            writeln(toString(tarHeader));
             writeln("**");
            writeln(toString(member.toTarHeader));
            writeln("************************************");
            writeln("### TarMember\n", member, "-----------------------");
            //assert(tarHeader == member.toTarHeader);
            assert(TarHeader.calculateChecksum(tarHeader) == TarHeader.calculateChecksum(member.toTarHeader));

            if (member.size > 0)
            {
                member.content = new ubyte[member.size];
                file.rawRead(member.content);

                immutable pos = file.tell().roundUpToMultiple(512);
                file.seek(pos);
            }

            tarFile._members[member.filename] = member;
        }

        return tarFile;
    }

    void add(bool recursive = true, alias filter = (TarMember member) => true)(string filePath)
    {
        static if (!isPredicate!TarMember)
            assert(false, "'filter' should be a predicate taking TarMember as an argument.");


    }

    void add(TarMember member)
    {
        _members[member.filename] = member;


    }
}

