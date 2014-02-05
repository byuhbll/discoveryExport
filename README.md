discoveryExport
===============

Export publicly viewable catalog records from SirsiDynix Symphony.  

#Installation

This application is dependent on the Ostinato Perl Library, v.2.1 (https://github.com/byuhbll/ostinato) and inherits that library's dependencies.

After cloning this repository, the only other required installation step is to add or link to Ostinato.  **export.pl** will import Ostinato from a resource called **ostinato** located in the same directory as **export.pl**.  You can either download Ostinato directly into that location, or use a symbolic link (recommended).

Please note that this script uses several GNU utilities and has only been tested for use on \*nix systems.

#Usage

To export records, simply provide a list of catalog keys (either as command-line arguments or through standard input) to **export.pl**.  The script will automatically identify which catalog keys keys represent publicly visible bibliographic records and exports them accordingly.

Examples:

```bash
./export.pl [*options*] 123456 789011
cat listOfKeys.txt | ./export.pl [*options]
```

##Input

This script accepts a list of keys as command line variables.  If no keys are provided, standard input will be used instead.  To allow for compatability with Symphony APIs, input may consist of pipe-delimited data.  Only the characters before the first pipe (|) will be tested as a potential catalog key.

##Output

This script will write one or more files to the destination directory (the current directory by default, can be overridden).  The files will be suffixed with "visible" or "hidden" according to the following logic:

Keys which do not exist in the ILS, or for which the record is shadowed (or contains no unshadowed call numbers or items) will be sent to the "hidden" file(s).  Otherwise, a catalog record will be exported to the "visible" file(s).

Resulting output files may be written in SirsiDynix's proprietary FLAT format, MARC transmission format, or MARCXML.  Other options are available to change the destination directory and filenames, to split the output into multiple "chunks", or to compress all the output files into a single .tar.gz.

The path(s) to all created files will be send to standard output.  Any unprocessable input and other error messages will be sent to standard error.
