/++
 +
 +/
module dcompress.tar;

// tar Header Block, from POSIX 1003.1-1990.

// The filename, linkFilename, magic, userName, and groupName are null-
// terminated character strings. All other fields are zero-filled octal numbers
// in ASCII. Each numeric field of width w contains w minus 1 digits, and a
// null.
struct TarHeader
{                              /* byte offset */
    char[100] filename;        /*   0 */
    // Provides nine bits specifying file permissions and three bits to specify
    // the Set UID, Set GID, and Save Text (sticky) modes. Values for these bits
    // are defined above. When special permissions are required to create a file
    // with a given mode, and the user restoring files from the archive does not
    // hold such permissions, the mode bit(s) specifying those special
    // permissions are ignored. Modes which are not supported by the operating
    // system restoring files from the archive will be ignored. Unsupported
    // modes should be faked up when creating or updating an archive; e.g., the
    // group permission could be copied from the other permission.
    char[8] mode;                 /* 100 */
    // The uid and gid fields are the numeric user and group ID of the file
    // owners, respectively. If the operating system does not support numeric
    // user or group IDs, these fields should be ignored.
    char[8] userId;                  /* 108 */
    char[8] groupId;                  /* 116 */
    // The size of the file in bytes; linked files are archived with this field
    // specified as zero.
    char[12] size;                /* 124 */
    // The data modification time of the file at the time it was archived. It is
    // the ASCII representation of the octal value of the last time the file's
    // contents were modified, represented as an integer number of seconds since
    // January 1, 1970, 00:00 Coordinated Universal Time.
    char[12] modificationTime;               /* 136 */
    // The ASCII representation of the octal value of the simple sum of all
    // bytes in the header block. Each 8-bit byte in the header is added to an
    // unsigned integer, initialized to zero, the precision of which shall be no
    // less than seventeen bits. When calculating the checksum, the chksum field
    // is treated as if it were all blanks.
    char[8] checksum;               /* 148 */
    // Specifies the type of file archived. If a particular implementation does
    // not recognize or permit the specified type, the file will be extracted as
    // if it were a regular file. As this action occurs, tar issues a warning to
    // the standard error.
    char fileTypeFlag;                /* 156 */
    char[100] linkedToFilename;           /* 157 */
    // Indicates that this archive was output in the P1003 archive format. If
    // this field contains `magicString`, the `userName` and `groupName` fields
    // will contain the ASCII representation of the owner and group of the file
    // respectively. If found, the user and group IDs are used rather than the
    // values in the `userId` and `groupId` fields.
    char[6] magic;                /* 257 */
    char[2] tarVersion;              /* 263 */
    char[32] userName;               /* 265 */
    char[32] groupName;               /* 297 */
    char[8] deviceMajorNumber;             /* 329 */
    char[8] deviceMinorNumber;             /* 337 */
    char[155] prefix;             /* 345 */
                                  /* 500 */
};

const(char)[] magicString = "ustar\0";
const(char)[] versionString = "00";

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

/// Bits used in the `TarHeader.mode` field, values in octal.
enum FileMode : ubyte
{
    // set UID on execution
    setUid  = 04000,
    // set GID on execution
    setGid  = 02000,

    ownerRead  = 00400,
    ownerWrite = 00200,
    ownerExec  = 00100,

    groupRead  = 00040,
    groupWrite = 00020,
    groupExec  = 00010,

    otherRead  = 00004,
    otherWrite = 00002,
    otherExec  = 00001,
}

