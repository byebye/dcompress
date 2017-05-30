/++
 +
 +/
module dcompress.tar;

debug = tar;

debug(tar)
{
    import std.stdio;
}

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
        auto bytes = cast(ubyte[]) header.asBytes;
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

    //// This specifies a contiguous file, which is the same as a normal file
    //// except that, in operating systems which support it, all its space is
    //// allocated contiguously on the disk. Operating systems which do not allow
    //// contiguous allocation should silently treat this type as a normal file.
    //contiguous = '7',
    //// Extended header referring to the next file in the archive.
    //extendedHeaderNext = 'x',
    //// Global extended header
    //extendedHeaderGlobal = 'g',
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
    alias iuint = immutable(uint);
    import std.conv : octal;
    /// set user ID upon execution
    static iuint setUid  = octal!4000;
    /// set group ID upon execution
    static iuint setGid  = octal!2000;
    /// sticky bit
    static iuint restrictedDeletion = octal!1000;

    static iuint ownerRead  = octal!400;
    static iuint ownerWrite = octal!200;
    static iuint ownerExec  = octal!100;

    static iuint groupRead  = octal!40;
    static iuint groupWrite = octal!20;
    static iuint groupExec  = octal!10;

    static iuint otherRead  = octal!4;
    static iuint otherWrite = octal!2;
    static iuint otherExec  = octal!1;
}

unittest
{
    import core.sys.posix.sys.stat;
    //writefln("S: %o %o %o", S_ISUID, S_ISGID, S_ISVTX);
    //writefln("U: %o %o %o %o", S_IRWXU, S_IRUSR, S_IWUSR, S_IXUSR);
    //writefln("G: %o %o %o %o", S_IRWXG, S_IRGRP, S_IWGRP, S_IXGRP);
    //writefln("O: %o %o %o %o", S_IRWXO, S_IROTH, S_IWOTH, S_IXOTH);

    assert(FileMode.setUid == S_ISUID);
    assert(FileMode.setGid == S_ISGID);
    assert(FileMode.restrictedDeletion == S_ISVTX);

    assert(FileMode.ownerRead == S_IRUSR);
    assert(FileMode.ownerWrite == S_IWUSR);
    assert(FileMode.ownerExec == S_IXUSR);

    assert(FileMode.groupRead == S_IRGRP);
    assert(FileMode.groupWrite == S_IWGRP);
    assert(FileMode.groupExec == S_IXGRP);

    assert(FileMode.otherRead == S_IROTH);
    assert(FileMode.otherWrite == S_IWOTH);
    assert(FileMode.otherExec == S_IXOTH);
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

const(void)[] asBytes(T)(ref T value)
{
    return (cast(void*) &value)[0 .. T.sizeof];
}

import std.stdio;

struct TarMember
{
    import std.datetime : SysTime;

    string filename;
    string linkedToFilename;
    size_t size;
    FileType fileType;
    uint mode;
    uint userId;
    uint groupId;
    string userName;
    string groupName;
    uint deviceMajorNumber;
    uint deviceMinorNumber;
    SysTime modificationTime;

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
            if (path.length == 0 || path[$ - 1] == '/')
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

    static void[] asTarBytes(TarMember member, void[] content)
    in
    {
        assert(member.size == content.length);
    }
    body
    {
        immutable blockSize = TarHeader.sizeof;
        immutable size = (blockSize + member.size).roundUpToMultiple(blockSize);
        auto buf = new ubyte[size];
        auto header = member.toTarHeader();
        import std.algorithm.mutation : copy;
        auto bufRem = copy(cast(ubyte[]) header.asBytes, buf);
        copy(cast(ubyte[]) content, bufRem);
        return buf;
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

enum isPredicate(alias pred, T) = __traits(compiles, (T t) { if (pred(t)) {} });

static void enforceSuccess(int status)
{
    if (status == 0)
        return;

    import std.string : fromStringz;
    import core.stdc.string : strerror;
    import core.stdc.errno;

    string msg = fromStringz(strerror(errno)).idup;
    throw new TarException(msg);
}

struct FileStat
{
    import core.sys.posix.sys.stat;
    import std.string : fromStringz;

    stat_t _stat;

    @disable this();

    this(string filename)
    {
        import std.string : toStringz;
        this(filename.toStringz);
    }

    this(const(char)* filename)
    {
        lstat(filename, &_stat);
    }

    /// Type of the file.
    FileType fileType()
    {
        // TODO Hard links: https://unix.stackexchange.com/questions/43037/dereferencing-hard-links
        immutable(uint) attrs = _stat.st_mode;
        immutable fileTypeMask = (attrs & S_IFMT);
        switch (fileTypeMask)
        {
            case S_IFREG: return FileType.regular;
            case S_IFDIR: return FileType.directory;
            case S_IFLNK: return FileType.symbolicLink;
            case S_IFBLK: return FileType.blockSpecial;
            case S_IFCHR: return FileType.characterSpecial;
            case S_IFIFO: return FileType.fifoSpecial;
            default: assert(0, "Unsupported file type.");
        }
    }

    /// Number of hard links to the file.
    ulong hardLinksCount() const
    {
        return _stat.st_nlink;
    }

    /// User ID of file.
    uint userId() const
    {
        return _stat.st_uid;
    }

    /// User name of file.
    string userName() const
    {
        import core.sys.posix.pwd : passwd, getpwuid_r;
        //import core.sys.posix.unistd : sysconf, _SC_GETPW_R_SIZE_MAX;
        //immutable size = sysconf(_SC_GETPW_R_SIZE_MAX);
        //assert(size != -1);
        char[1024] buffer = void;
        passwd pwd;
        passwd* result;
        getpwuid_r(groupId(), &pwd, buffer.ptr, buffer.length, &result);
        assert(result != null);
        return fromStringz(result.pw_name).idup;
    }

    /// Group ID of file.
    uint groupId() const
    {
        return _stat.st_gid;
    }

    /// File mode - permissions, setgid, setuid and sticky bit.
    uint mode() const
    {
        static immutable mask =
            (S_ISUID | S_ISGID | S_ISVTX | S_IRWXU | S_IRWXG | S_IRWXO);
        return _stat.st_mode & mask;
    }

    /// Group name of file.
    string groupName() const
    {
        import core.sys.posix.grp : group, getgrgid_r;
        //import core.sys.posix.unistd : sysconf, _SC_GETGR_R_SIZE_MAX;
        //immutable size = sysconf(_SC_GETGR_R_SIZE_MAX);
        //assert(size != -1);
        char[1024] buffer = void;
        group grp;
        group* result;
        getgrgid_r(groupId(), &grp, buffer.ptr, buffer.length, &result);
        assert(result != null);
        return fromStringz(result.gr_name).idup;
    }

    /// For regular files, the file size in bytes. For symbolic links, the
    /// length in bytes of the pathname contained in the symbolic link.
    ulong size() const
    {
        return _stat.st_size;
    }

    private static immutable(uint) minorBits = 20;
    private static immutable(uint) minorMask = ((1U << minorBits) - 1);

    static uint makeDeviceNumber(uint major, uint minor)
    {
        return (major << minorBits) | minor;
    }

    static uint fileTypeMode(FileType fileType)
    {
        final switch (fileType)
        {
            case FileType.regular: return S_IFREG;
            case FileType.regularCompatibility: return S_IFREG;
            case FileType.hardLink: return S_IFREG;
            case FileType.directory: return S_IFDIR;
            case FileType.symbolicLink: return S_IFLNK;
            case FileType.blockSpecial: return S_IFBLK;
            case FileType.characterSpecial: return S_IFCHR;
            case FileType.fifoSpecial: return S_IFIFO;
        }
    }

    static uint posixFileMode(uint mode, FileType fileType)
    {
        return mode | FileStat.fileTypeMode(fileType);
    }

    /// Device ID major number (if file is character or block special).
    uint deviceMajorNumber() const
    {
        return cast(uint) ((_stat.st_rdev) >> minorBits);
    }

    /// Device ID minor number (if file is character or block special).
    uint deviceMinorNumber() const
    {
        return ((_stat.st_rdev) & minorMask);
    }

    /// Time of last access.
    long accessTime() const
    {
        return _stat.st_atime;
    }

    /// Time of last data modification.
    long modificationTime() const
    {
        return _stat.st_mtime;
    }

    /// Time of last status change.
    long statusChangeTime() const
    {
        return _stat.st_ctime;
    }

    /// A file system-specific preferred I/O block size for this object. In some
    /// file system types, this may vary from file to file.
    long blockSize() const
    {
        return _stat.st_blksize;
    }

    /// Number of blocks allocated for this object.
    long blockCount() const
    {
        return _stat.st_blocks;
    }
}

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

TarReader!TarInput tarReader(TarInput)(TarInput input)
{
    return TarReader!TarInput(input);
}

import dcompress.primitives : isCompressInput;

struct TarReader(TarInput)
if (isCompressInput!TarInput)
{
    import std.typecons : Tuple;
    import std.traits : isArray;
    alias TarMemberWithContent = Tuple!(TarMember, "member", void[], "content");

private:

    TarInput _input;
    TarMemberWithContent _member;
    bool _empty;
    static enum _blockSize = TarHeader.sizeof;

public:

    @disable this();

    this(TarInput input)
    {
        _input = input;
        popFront;
    }

    @property TarMemberWithContent front()
    {
        return _member;
    }

    @property bool empty()
    {
        return _empty;
    }

    @property void popFront()
    in
    {
        assert(!empty);
    }
    body
    {
        import std.range : take, refRange;
        import std.algorithm.mutation : copy;

        TarHeader tarHeader;
        auto headerBytes = cast(ubyte[]) (cast(void*) &tarHeader)[0 .. _blockSize];
        auto rem = refRange(&_input).take(_blockSize).copy(headerBytes);

        if (rem.length > 0)
            throw new TarException("Not enough bytes for tar header.");

        if (headerBytes[0] == '\0')
        {
            _empty = true;
            return;
        }

        static if (isArray!TarInput)
            _input = _input[_blockSize .. $];

        auto member = TarMember(tarHeader);

        assert(TarHeader.calculateChecksum(tarHeader) ==
            TarHeader.calculateChecksum(member.toTarHeader));

        ubyte[] content;
        if (member.size > 0)
        {
            content.length = member.size;
            rem = refRange(&_input).take(content.length).copy(content);

            if (rem.length > 0)
                throw new TarException("Not enough bytes for tar member content.");

            static if (isArray!TarInput)
                _input = _input[content.length .. $];

            auto mod = member.size % _blockSize;
            if (mod > 0)
            {
                import std.range.primitives : popFrontN;
                auto popped = _input.popFrontN(_blockSize - mod);
                assert(popped == _blockSize - mod);
            }
        }

        _member = TarMemberWithContent(member, content);
    }
}

struct TarFile
{
    import std.stdio : File;
    import std.typecons : Tuple;
    alias MemberWithPosition = Tuple!(TarMember, "member", size_t, "position");

private:

    MemberWithPosition[string] _members;

    File _file;
    size_t _endBlocksPos;
    static enum _blockSize = TarHeader.sizeof;
    size_t _blockingFactor = 20; // number of records per block

public:

    static TarFile open(string path, in char[] openMode = "rb")
    {
        TarFile tarFile;
        tarFile._file = File(path, openMode);

        auto file = &tarFile._file;

        while (!file.eof)
        {
            TarHeader tarHeader;
            auto buffer = cast(ubyte[]) (cast(void*) &tarHeader)[0 .. tarHeader.sizeof];
            auto headerBytes = file.rawRead(buffer);

            if (headerBytes[0] == '\0')
            {
                tarFile._endBlocksPos = file.tell() - TarHeader.sizeof;
                auto left = file.size() - tarFile._endBlocksPos;
                debug(tar)
                {
                    writeln("End of tar archive.");
                    writefln("Padding: %d bytes = %d blocks from total of %d",
                        left, left / _blockSize, file.size() / _blockSize);
                }
                assert(left % _blockSize == 0);
                file.rewind();
                break;
            }
            if (headerBytes.length < buffer.length)
                throw new TarException("Not enough bytes read for tar header.");

            auto member = TarMember(tarHeader);

            //writeln("### TarMember\n", member, "-----------------------");

            assert(TarHeader.calculateChecksum(tarHeader) ==
                TarHeader.calculateChecksum(member.toTarHeader));

            size_t position = file.tell();

            if (member.size > 0)
            {
                immutable pos = (file.tell() + member.size)
                    .roundUpToMultiple(_blockSize);
                file.seek(pos);
            }

            tarFile._members[member.filename] = MemberWithPosition(member, position);
        }

        return tarFile;
    }

    @property size_t size()
    {
        return _file.size();
    }

    private void[] readContentAt(size_t pos, size_t size)
    {
        void[] buf = new ubyte[size];

        immutable prevPos = _file.tell();
        _file.seek(pos);
        _file.rawRead(buf);
        _file.seek(prevPos);

        return buf;
    }

    void[] readMemberContent(string filename)
    {
        auto mp = (filename in _members);
        assert(mp !is null);

        if (mp.member.size == 0)
            return null;

        return readContentAt(mp.position, mp.member.size);
    }

    void add(alias memberFilter = (TarMember member) => true)(
        string filename, bool recursive = true)
    {
        static if (!isPredicate!(memberFilter, TarMember))
            assert(false, "'filter' should be a predicate taking TarMember as an argument.");

        import std.file : exists;
        if (!exists(filename))
            throw new TarException("File '" ~ filename ~ "' does not exist.");

        import std.file : dirEntries;
        import std.traits : ReturnType;

        ReturnType!dirEntries entries;

        import std.file : isDir;
        if (recursive && isDir(filename))
        {
            import std.file : SpanMode;
            entries = dirEntries(filename, SpanMode.breadth);
        }

        import std.algorithm.iteration : map, filter, each;
        import std.range : only, chain;

        only(filename).chain(entries)
            .map!(name => fileToTarMember(name))
            .filter!(member => memberFilter(member))
            .each!(member => addReadContent(member));
    }

    private TarMember fileToTarMember(string filename)
    {
        auto stat = FileStat(filename);

        TarMember member;
        member.filename = filename;
        member.fileType = stat.fileType();
        if (member.fileType == FileType.symbolicLink)
        {
            import std.file : readLink;
            member.linkedToFilename = readLink(filename);
        }
        member.userId = stat.userId();
        member.groupId = stat.groupId();
        member.userName = stat.userName();
        member.groupName = stat.groupName();
        member.mode = stat.mode();
        if (member.fileType == FileType.characterSpecial ||
            member.fileType == FileType.blockSpecial)
        {
            member.deviceMajorNumber = stat.deviceMajorNumber;
            member.deviceMinorNumber = stat.deviceMinorNumber;
        }
        import std.datetime : SysTime;
        member.modificationTime = SysTime.fromUnixTime(stat.modificationTime);

        return member;
    }

    void addReadContent(TarMember member)
    {
        if (member.fileType != FileType.directory && member.size > 0)
        {
           auto sourceFile = File(member.filename, "rb");
           assert(member.size == sourceFile.size);
           ubyte[4096] chunk;
           add(member, sourceFile.byChunk(chunk[]));
        }
        else
            add(member, new ubyte[0]);
    }

    import dcompress.primitives : isCompressInput;

    void add(InR)(TarMember member, InR content)
    if (isCompressInput!InR)
    {
        debug(tar) writeln("Adding file to tar: ", member.filename);

        _members[member.filename] = MemberWithPosition(member, _endBlocksPos);

        auto header = member.toTarHeader();
        _file.reopen(null, "rb+"); // Reopen for write
        _file.seek(_endBlocksPos);
        _file.rawWrite(header.asBytes);

        if (member.size > 0)
        {
            import std.traits : Unqual, isArray;
            import std.range.primitives : ElementType;

            static if (isArray!InR)
            {
                assert(member.size == content.length);
                _file.rawWrite(content);
            }
            else
            {
                static if (isArray!(ElementType!InR))
                    alias contentChunks = content;
                else // ubyte
                    auto contentChunks = chunks!4096(content);

                import std.algorithm.iteration : each;

                size_t bytesWritten = 0;
                contentChunks.each!((chunk) {
                    _file.rawWrite(chunk);
                    bytesWritten += chunk.length;
                });
                assert(member.size == bytesWritten);
            }
        }

        _endBlocksPos = _file.tell().roundUpToMultiple(_blockSize);
        version (Posix)
        {
            import core.sys.posix.unistd : ftruncate;
            alias resizeFile = ftruncate;
        }
        //else version (Windows)
        //{
        //    import core.sys.windows.
        //    extern (C) int _chsize_s(int fd, long size);
        //    alias resizeFile = _chsize_s;
        //}

        auto size = _file.size.roundUpToMultiple(_blockingFactor * _blockSize);
        auto status = resizeFile(_file.fileno, size);
        assert(status == 0);
    }

    void extract(string memberFilename, string destPath = ".")
    {
        if (destPath.length == 0)
            destPath = ".";

        import std.path : isValidPath, exists, isDir, buildPath;
        if (!isValidPath(destPath) || (exists(destPath) && !isDir(destPath)))
            throw new TarException("Invalid destination path: '" ~ destPath ~ "'");

        auto mp = (memberFilename in _members);
        assert(mp !is null);

        TarMember member = mp.member;

        import std.path : dirName, baseName;
        import std.file : write, mkdirRecurse;

        immutable fullPath = buildPath(destPath, member.filename);
        destPath = buildPath(destPath, dirName(member.filename));

        if (exists(fullPath))
            return;

        mkdirRecurse(destPath);

        debug(tar) writeln("Destination: ", fullPath);

        import std.string : toStringz;
        immutable fullPathC = fullPath.toStringz;

        if (member.fileType == FileType.directory)
        {
            import core.sys.posix.sys.stat : mkdir;
            mkdir(fullPathC, member.mode).enforceSuccess;
        }
        else if (member.fileType == FileType.symbolicLink)
        {
            import core.sys.posix.unistd : symlink;
            symlink(member.linkedToFilename.toStringz, fullPathC).enforceSuccess;
        }
        else
        {
            immutable mode = FileStat.posixFileMode(member.mode, member.fileType);
            immutable devNumber = FileStat.makeDeviceNumber(
                member.deviceMajorNumber, member.deviceMinorNumber);

            import core.sys.posix.sys.stat : mknod;
            mknod(fullPathC, mode, devNumber).enforceSuccess;
        }

        if (member.size > 0)
        {
            auto content = readContentAt(mp.position, mp.member.size);
            write(fullPath, content);
        }

        import core.sys.posix.unistd : lchown;
        lchown(fullPathC, member.userId, member.groupId).enforceSuccess;

        auto stat = FileStat(fullPath);

        import core.sys.posix.sys.time;
        import core.sys.posix.sys.stat : utimensat;

        timespec[2] newTime;
        newTime[0].tv_sec = stat.accessTime();
        newTime[1].tv_sec = member.modificationTime.toUnixTime();

        import core.sys.posix.fcntl : AT_FDCWD, AT_SYMLINK_NOFOLLOW;

        utimensat(AT_FDCWD, fullPathC, newTime, AT_SYMLINK_NOFOLLOW).enforceSuccess;
    }

    void extractAll(string destPath = ".")
    {
        import std.algorithm.iteration :  each;
        _members.byKey.each!(filename => extract(filename, destPath));
    }
}

