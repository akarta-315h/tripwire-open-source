
use twtools;

package dbupdate;


######################################################################
# One time module initialization goes in here...
#
BEGIN 
{

	# This is the root directory we will be integrity checking
	#
	$root = "$twtools::twcwd/$twtools::twrootdir/dbupdate-test";

	# Here are the names of the report files this test will create
	#
	$report1 = "$twtools::twcwd/$twtools::twrootdir/report/dbupdate-1.twr";
	$report2 = "$twtools::twcwd/$twtools::twrootdir/report/dbupdate-2.twr";
	$report3 = "$twtools::twcwd/$twtools::twrootdir/report/dbupdate-3.twr";
	$report4 = "$twtools::twcwd/$twtools::twrootdir/report/dbupdate-4.twr";
}

######################################################################
# PolicyFileString -- return the policy text as a string
#
sub PolicyFileString
{
	return <<POLICY_END;	
	# Policy file generated by dbupdate test
	#
	$root -> \$(ReadOnly)+M; #read only plus MD5
	
POLICY_END

}

######################################################################
# CreateFile -- create a file with the specified contents
#   
# input:  path     -- path to the file; relative to $root
#         contents -- string to put in the file
#
sub CreateFile
{
	my ($path, $contents) = @_;
	
	system( "echo $contents > $root/$path" );

	$? && die "Create file failed for $root/$path\n";
}

######################################################################
# RemoveFile -- removes the named file
#   
sub RemoveFile
{
	my ($path) = @_;
	
	if( -e "$root/$path" )
	{
		system( "rm -f $root/$path" );
	}
	
	$? && die "Remove file failed for $root/$path\n";
}


######################################################################
# CreateDir -- create a directory
#
sub CreateDir
{
	my($dir) = @_;

	# NOTE: mkdir fails if it is already a directory!
	#
	if( ! -d "$root/$dir" )
	{
		system( "rm -f $root/$dir" );
		system( "mkdir -p $root/$dir" );
	
		$? && die "Mkdir failed for $root/$dir\n";
	}
}

######################################################################
# MoveFile -- move a file from one place to another
#             NOTE: file names are relative to $root
#   
# input:  old_name -- name of file to move
#         new_name -- where it should be moved to
#
sub MoveFile
{
	my($old, $new) = @_;
	
	system( "mv $root/$old $root/$new" );
	$? && die "mv $root/$old $root/$new failed!\n";
}

######################################################################
# PrintDatabase
#
sub PrintDatabase
{
	system( "$twtools::twrootdir/bin/twprint -m d -c $twtools::twrootdir/tw.cfg" );
}

######################################################################
# PrintReport
#
sub PrintReport
{
	my ($report) = @_;
	system( "$twtools::twrootdir/bin/twprint -m r -c $twtools::twrootdir/tw.cfg -r $report" );
}

######################################################################
# PrepareForTest -- creates the files that each test will be 
#                   integrity checking and initializes the database.
#
sub PrepareForTest
{
	# make sure we are cleaned up...
	#
	cleanup();

	# Make the files we will be using...
	#
	CreateDir ( "dog" );
	CreateFile( "dog/bark.txt", "bark bark" );
	CreateFile( "meow.txt",     "meow" );

	# Initialize the database
	#
	twtools::initializeDatabase();
}

######################################################################
# RunBasicTest -- performs a rudimentary UpdateDatabase test
# 
sub RunBasicTest
{
	PrepareForTest();
	
	printf("%-30s", "-- dbupdate.basic test");

	# make some violations...
	#
	MoveFile  ( "meow.txt", "cat.txt" );
	CreateFile( "dog/bark.txt", "bark bark bark" );
	
	# run the integrity check...
	#
	twtools::runIntegrityCheck();

	# Make sure we got 4 violations: 2 mod, 1 add, 1 rm.
	#
    my ($n, $a, $r, $c) = 
    	twtools::analyzeReport( twtools::runReport() );
	
	if( ($n != 4) || ($a != 1) || ($r != 1) || ($c != 2) )
	{
		print "FAILED -- initial integrity check was wack!";
		return 0;	
	}

	# do the database update...
	#
	twtools::updateDatabase();

	# do another IC and make sure there are no violations
	#
	twtools::runIntegrityCheck();

	($n, $a, $r, $c) = 
		twtools::analyzeReport( twtools::runReport() );
	
	if( $n != 0 )
	{
		print "FAILED -- violations after update!";
		return 0;	
	}
	
	print "PASSED!!!\n";
	return 1;
}

######################################################################
# RunSecureModeTest -- test that secure-mode high and low are working
#
sub RunSecureModeTest
{
	PrepareForTest();
	
	printf("%-30s", "-- dbupdate.secure-mode test");

	# make a violation and generate a report
	#
	CreateFile( "dog/bark.txt", "bark bark bark" );
	twtools::runIntegrityCheck( { report => $report1 } );

	# change the same file in a slightly different way and generate
	# another report
	#
	CreateFile( "dog/bark.txt", "bark bark bark woof" );
	twtools::runIntegrityCheck( { report => $report2 } );

	# Remove a file and generate a third report
	#
	RemoveFile( "dog/bark.txt" );
	twtools::runIntegrityCheck( { report => $report3 } );
	
	# Add a file and generate the fourth report
	#
	CreateFile( "dog/cow.txt", "moo moo" );
	twtools::runIntegrityCheck( { report => $report4 } );
	

	# Update the database with report 1.
	#
	twtools::updateDatabase( { report => $report1 } );

	# Try to update the database with report 2 ... this should fail
	# in secure-mode == high because the "old" values don't match.
	#
	if( twtools::updateDatabase( 
		{ report => $report2, secure-mode => "high" } ) )
	{
		print "FAILED ... Secure-mode high didn't catch a bad update!";
		return 0;	
	}

	# do a high severity update with report3 -- this should 
	# succeed 
	#
	if( ! twtools::updateDatabase( 
		{ report => $report3, secure-mode => "high" } ) )
	{
		print "FAILED ... Update with report 3 failed!";
		return 0;	
	}
	
	# Try 2 again ... now we are trying to update an object that
	# doesn't exist in the database at all. This should
	# succeed in low but fail in high.
	#
	if( twtools::updateDatabase( 
		{ report => $report2, secure-mode => "high" } ) )
	{
		print "FAILED ... Update with report 2 after 3 succeeded in high mode!";
		return 0;	
	}

	if( ! twtools::updateDatabase( 
		{ report => $report2, secure-mode => "low" } ) )
	{
		print "FAILED ... Update with report 2 after 3 failed in low mode!";
		return 0;	
	}
	
	
	
	print "PASSED!!!\n";
	return 1;
}


######################################################################
#
# Initialize the test
#

sub initialize 
{
	# Make the policy file
	#
	twtools::generatePolicyFile( PolicyFileString() );
}


######################################################################
#
# Run the test.
#
sub run 
{
	RunBasicTest()      || return;
	RunSecureModeTest() || return;
}

sub cleanup
{
	# remove all of the files we were integrity checking...
	#
	system( "rm -rf $root/*" );
	$? && print "WARNING: dbupdate cleanup failed.\n";

	# remove the report files we created...
	#
	system( "rm -f $report1" ) if (-e $report1);
	system( "rm -r $report2" ) if (-e $report2);
	system( "rm -r $report3" ) if (-e $report3);
	system( "rm -r $report4" ) if (-e $report4);

}


######################################################################
# One time module cleanup goes in here...
#
END 
{
}

1;

