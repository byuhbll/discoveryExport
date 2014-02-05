#!/usr/bin/env perl

use strict;
use warnings;
use lib "ostinato";
use Ostinato::Export;
use Data::Dumper;
use Getopt::Long;
use File::HomeDir;
use File::Basename;
use Pod::Usage qw(pod2usage);
use Scalar::Util qw(looks_like_number);

our $VERSION = "3.0.0";

## pushInput(\@arrayRef, $input)
# $input is split on pipe (|) characters and the first element is
# tested as a number.  If it passes, it is pushed to the array
# referenced by \@arrayRef.  Otherwise, a non-fatal error is sent
# to STDERR.
##
sub pushInput {
	my $arrayRef = shift;
	my $input = shift;

	chomp($input);
	my @elements = split(/\|/, $input);
	if(defined($elements[0])) {
		my $catkey = $elements[0];
		chomp($catkey);
		if(length($catkey) && looks_like_number($catkey)) {
			push(@$arrayRef, $catkey);
		}
		else {
			print STDERR "Malformed catkey \"$catkey\" from \"$input\"\n";
		}
	}
}

#Get Flags from command line
my $optParser = new Getopt::Long::Parser;
my %optFlags = ();
$optParser->configure("bundling");
$optParser->getoptions(\%optFlags,
	"help|?",
	"version",
	"library|l|=s",
	"destination|d=s",
	"prefix|p=s",
	"chunk-size|n=i",
	"format|f=s",
	"compress|c",
);

#Default options per GNU Coding Standards
if( defined $optFlags{'help'} ) {
	pod2usage({
		-exitval => 1,
		-verbose => 2,
	});
}
if ( defined $optFlags{'version'} ) {
	pod2usage({
		-message => "BYU HBLL Catalog Exporter, version $VERSION",
		-verbose => 0,
		-exitval => 1,
	});
}

my $ostinato = new Ostinato();
my $tempFilePrefix = $ostinato->getPath("temp") . "/" . $ostinato->getEnvId();
my $partialFilename = defined $optFlags{'prefix'}  ?  $optFlags{'prefix'}  :  "discoveryExport";
my $envId    = $ostinato->getEnvId();

#Calculate chunk size
my $chunkSize = defined $optFlags{'chunk-size'}  ?  $optFlags{'chunk-size'}  :  0;

#Validate format
my $format = defined $optFlags{'format'}  ?  lc($optFlags{'format'})  :  Ostinato::Export::FORMAT_FLAT;
if($format ne Ostinato::Export::FORMAT_FLAT && $format ne Ostinato::Export::FORMAT_MARC && $format ne Ostinato::Export::FORMAT_XML) {
	pod2usage({
		-message => "ERROR: Unknown format requested.  Valid options are \"flat\", \"marc\" and \"marcxml\".\n",
		-verbose => 1,
	});
}

#Prepare destination, replacing the ~ (home dir) as needed.
my $home = File::HomeDir->my_home;
my $destination = defined $optFlags{'destination'}  ?  $optFlags{'destination'}  :  '.';
$destination =~ s/~/$home/g;
$destination =~ s/\/\//\//g;
$destination =~ s/\/$//g;
if(!(-d $destination)) {
	pod2usage({
		-message => "ERROR: Requested destination does not exist or is not a directory.\n",
		-verbose => 1,
	});
}

#Prepare the necessary Ostinato filters to test each key for visibility
$ostinato->{class}->{filter} = new Ostinato::Filter($ostinato);
$ostinato->{class}->{policy}->importPolicies();
$ostinato->{class}->{filter}->autofilter_excludeShadowedLocations();
if(defined $optFlags{'library'}) {
	$ostinato->{class}->{filter}->setFilter(Ostinato::Policy::LIBRARY, $optFlags{'library'});
}
my $exporter = new Ostinato::Export($ostinato);

#Save the incoming keys to an array
my @keyArray;
if(-t STDIN and not @ARGV) {
	pod2usage({
		-message => "ERROR: Provide input as arguments or through standard input.\n",
		-verbose => 0,
	});
}
else {
	while(my $line = <@ARGV>) {
		pushInput(\@keyArray, $line);
	}
	if(not -t STDIN) {
		while(my $line = <STDIN>) {
			pushInput(\@keyArray, $line);
		}
	}
}

#Convert the keyArray to the keyHash containing visibility booleans and de-allocate the original array.
my $keyHash = $exporter->calculateVisibility(\@keyArray);
undef @keyArray;

#Prepare the necessary data structure to export the keys
my @files;
my $visibleKeysFile = $tempFilePrefix . ".$partialFilename.visiblekeys";
my $hiddenKeysFile  = $tempFilePrefix . ".$partialFilename.hiddenkeys";
my $visibleCount = 0;
my $hiddenCount = 0;
my $visibleChunk = 0;
my $hiddenChunk = 0;
open VISIBLE_KEYS_FILE, ">", $visibleKeysFile;
open HIDDEN_KEYS_FILE, ">", $hiddenKeysFile;

#Iterate through the keys and send them to the visible and hidden keys files for exporting
while( my($key, $visible) = each %$keyHash) {
	if($visible) {
		print VISIBLE_KEYS_FILE "$key|\n";
		$visibleCount++;
		#If we have a maximum chunk size and we reach it, dump the records and reset the visible keys file
		if($chunkSize > 0 && $visibleCount >= $chunkSize) {
			close(VISIBLE_KEYS_FILE);
			push(@files, $exporter->catalogdump({source=>$visibleKeysFile, format=>$format, destination=>"$destination/$partialFilename.visible.$visibleChunk"}));
			$visibleChunk++;
			$visibleCount = 0;
			open VISIBLE_KEYS_FILE, ">", $visibleKeysFile;
		}
	}
	else {
		print HIDDEN_KEYS_FILE "$key|\n";
		$hiddenCount++;
		#If we have a maximum chunk size and we reach it, convert the keys to empty records and reset the hidden keys file
		if($chunkSize > 0 && $hiddenCount > $chunkSize) {
			close(HIDDEN_KEYS_FILE);
			push(@files, $exporter->createEmptyRecord({source=>$hiddenKeysFile, format=>$format, destination=>"$destination/$partialFilename.hidden.$hiddenChunk"}));
			$hiddenChunk++;
			$hiddenCount = 0;
			open HIDDEN_KEYS_FILE, ">", $hiddenKeysFile;
		}
	}
}
close(VISIBLE_KEYS_FILE);
close(HIDDEN_KEYS_FILE);

#Free up some memory (in case we're dealing with an extremely large dataset
undef %$keyHash;

#This is the last chunk.  Dump the records (for visible keys) and convert the keys to empty records (for hidden keys)
if($visibleChunk > 0 || $hiddenChunk > 0) {
	if($visibleCount > 0) {
		push(@files, $exporter->catalogdump({source=>$visibleKeysFile, format=>$format, destination=>"$destination/$partialFilename.visible.$visibleChunk"}));
	}
	if($hiddenCount > 0) {
		push(@files, $exporter->createEmptyRecord({source=>$hiddenKeysFile, format=>$format, destination=>"$destination/$partialFilename.hidden.$hiddenChunk"}));
	}
}
#This is the ONLY chunk.  Dump the records (for visible keys) and convert the keys to empty records (for hidden keys)
else {
	#Export visible keys, if any exist
	if($visibleCount > 0) {
		push(@files, $exporter->catalogdump({source=>$visibleKeysFile, format=>$format, destination=>"$destination/$partialFilename.visible"}));
	}
	#Export hidden keys, if any exist
	if($hiddenCount > 0) {
		push(@files, $exporter->createEmptyRecord({source=>$hiddenKeysFile, format=>$format, destination=>"$destination/$partialFilename.hidden"}));
	}
}

#If the --compress flag is set, send the resulting data files to a tar.gz archive.
if(defined $optFlags{'compress'} && $optFlags{'compress'}) {
	#Strip the directory off each created file's path 
	foreach my $filename (@files) {
		$filename = fileparse($filename);
	}

	#Prepare a command to move all the created files into a .tar.gz file and delete the originals
	my $createdFiles = join("\n", @files);
	my $archiveName = "$partialFilename.tar.gz";
	my $cmd = "cd $destination; echo \"$createdFiles\" | tar -czf $archiveName -T- --remove-files;";
	system($cmd);
	print "$destination/$archiveName\n";
}
#If the --compress flag is not set, simply list the resulting data files
else {
	my $createdFiles = join("\n", @files);
	print "$createdFiles\n";
}

__END__

=pod

=head1 NAME

B<export.pl> - Exports publicly viewable bibliograhic records

=head1 SYNOPSIS

=over 4

=item B<export.pl> --help

=item B<export.pl> [I<options>] [I<CATKEY>...]

=back

=head1 DESCRIPTION

B<export.pl> accepts a list of I<CATKEY> (catalog keys) and exports the corresponding bibliographic records from SirsiDynix's Symphony ILS.  The corresponding records are designed to be used with search engines, discovery layers or other public tools, and are therefore filtered for public consumption.

=head2 Input

This script accepts a list of keys as command line variables.  If no keys are provided, standard input will be used instead.  To allow for compatability with Symphony APIs, input may consist of pipe-delimited data.  Only the characters before the first pipe (|) will be tested as a potential catalog key.

=head2 Output

This script will write one or more files to the destination directory (the current directory by default, can be overridden using the B<--destination> flag).  The files will be suffixed with "visible" or "hidden" according to the following logic:

Keys which do not exist in the ILS, or for which the record is shadowed (or contains no unshadowed call numbers or items) will be sent to the "hidden" file(s).  Otherwise, a catalog record will be exported to the "visible" file(s).

The path(s) to all created files will be send to standard output.  Any unprocessable input and other error messages will be sent to standard error.

=head2 Dependencies

B<export.pl> is dependent on the Ostinato Perl Library, v.2.1 (I<https://github.com/byuhbll/ostinato>) and inherits that library's dependencies.  The script will import Ostinato from a resource called "ostinato" located in the same directory as B<export.pl>.  You may either place a copy of Ostinato in that location or use a symbolic link.

Additionally, the following modules are used directly by this script: Getopt::Long, File::HomeDir, File::Basename, and Pod::Usage qw(pod2usage).

This script uses several GNU utilities and has only been tested for use on *nix systems.


=head1 OPTIONS

=over 4

=item B<-?>, B<--help>

If set, the full documentation for the script will be shown, and the script will exit.

=item B<-c>, B<--compress>

If used, the resulting output files will be moved into a .tar.gz archive.  The original output files will be removed, and only the name of the archive will be written to standard output.

=item B<-d> I<DIRECTORY>, B<--destination>=I<DIRECTORY>

If used, this script will write the resulting output files to the provided I<DIRECTORY> (by default, the current directory is used).  If the directory does not exist or is not writable, an error will be thrown.

=item B<-f> I<FORMAT>, B<--format>=I<FORMAT>

Specifies the format of the records written to the resulting output files.  Valid options include "flat" (the proprietary Sirsi FLAT format), "marc" (the Sirsi version of the MARC Transmission format),  and "marcxml" (the Library of Congress MARCXML format).  By default, "flat" is used.

=item B<-l> I<LIBRARY>, B<--library>=I<LIBRARY>

If used, this script will only consider titles, call numbers, and/or items belonging to the Symphony I<LIBRARY> string in its determination of visibility.  For example, if the only items in the ILS for catalog key "123456" belong to the "MAIN" library, and "B<--library>=BRANCH" is set, "123456" would be sent to the "hidden" file.  To exclude libraries instead, prepend the library name(s) with a tilde (~).

=item B<-n> I<NUMBER>, B<--chunk-size>=I<NUMBER>

If used, the resulting output files will be split into separate files, each containing a maximum I<NUMBER> of records.  If this option is used, the resulting output files may have an additional numeric suffix (.0, .1, etc...) added.

=item B<-p> I<PREFIX>, B<--prefix>=I<PREFIX>

Resulting output files will be named: I<PREFIX>.visible, I<PREFIX>.hidden, etc.  By default, "discoveryExport" is used as the I<PREFIX>; it can be overridden using this option.

=item B<--version>

If set, the current version of this script will be shown, and the script will exit.

=back
