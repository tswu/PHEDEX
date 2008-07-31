#!/usr/bin/env perl

use warnings;
use strict;

use Getopt::Long;
use Data::Dumper;
use Sys::Hostname;
use PHEDEX::Core::Help;
use PHEDEX::Core::Config;

##H
##H  This script is for monitoring CPU and memory use by agents. See the wiki
##H page at https://twiki.cern.ch/twiki/bin/view/CMS/PhedexProjAgentMonitoring
##H for details and instructions.
##H
##H  Comments, feedback, and bug-reports welcomed, via Savannah whenever
##H appropriate.
##H

my ($rss,$vsize,$cpu,%g,%cmds,%procs,@users);
my ($detail,%pids,$interval,$help,$verbose,$quiet,$log);
my (%thresh,$VSize,$RSS,$Utime,$Stime,$pagesize);

$interval = $detail = $quiet = $verbose = 0;

$VSize = 0;
$RSS   = 0;
$Utime = 0;
$Stime = 0;

GetOptions(	'interval=i'	=> \$interval,
		'detail'	=> \$detail,
		'help'		=> \&usage,
		'verbose'	=> \$verbose,
		'quiet'		=> \$quiet,
		'users=s@'	=> \@users,
		'VSize=i'	=> \$VSize,
		'RSS=i'		=> \$RSS,
		'Utime=i'	=> \$Utime,
		'Stime=i'	=> \$Stime,
		'log=s'		=> \$log,
	  );

die "Need one of VSize, RSS, Utime, Stime\n"
	unless ($VSize || $RSS || $Utime || $Stime);
#
# No user-serviceable parts below...
#

if ( $log )
{
  open STDOUT, ">$log" or die "open: $log: $!\n";
  chmod 0600, $log or die "chmod: $!\n";
}

%thresh = (
		VSize	=> $VSize,
		RSS	=> $RSS,
		Utime	=> $Utime,
		Stime	=> $Stime,
	  );

open CONF, "getconf PAGESIZE|" or die "getconf PAGESIZE: $!\n";
$pagesize = <CONF>;
close CONF;
chomp $pagesize;
$pagesize or die "Cannot determine memory pagesize!\n";

LOOP:
%procs = ();

if ( ! @users ) { push @users, (getpwuid($<))[0]; } 

open PS, "ps aux | egrep '^" . join('|^',@users) . "' |" or die "ps: $!\n";
my @ps = <PS>;
close PS;
foreach ( @ps )
{
  m%^(\S+)\s+(\d+)\s% or next;
  my ($user,$pid) = ($1,$2);
  -e "/proc/$pid" or next;
  $procs{$pid} = 1;
  if ( !$cmds{$pid} )
  {
    open CMD, "/proc/$pid/cmdline" or do
    {
      warn "/proc/$pid/cmdline: $!\n";
      $cmds{$pid}='unknown';
      next;
    };
    $_ = <CMD>;
    chomp $_;
    $_ = join(' ',split('\c@',$_));
    $cmds{$pid} = $_;
    close CMD;
    print "Adding user=$user pid=$pid, cmd=$_\n";
  }
}

foreach my $pid ( sort { $a <=> $b } keys %procs )
{
  open PROC, "</proc/$pid/statm" or do
  {
#   warn "/proc/$pid: $!\n";
    delete $procs{$pid};
    delete $cmds{$pid};
    next;
  };
  $_ = <PROC>;
  close PROC or die "Error closing /proc/$pid/statm: $!\n";
  my @a = split(' ',$_);
  my %h = ();
  $h{VSize} = $a[0] * $pagesize / 1024 / 1024; # in MB
  $h{RSS}   = $a[1] * $pagesize / 1024 / 1024;

  open PROC, "</proc/$pid/stat" or do { warn "/proc/$pid: $!\n"; next; };
  $_ = <PROC>;
  close PROC or die "Error closing /proc/$pid/stat: $!\n";
  my @b = split(' ',$_);
  $h{Utime} = $b[13] / 100; # normalise to seconds
  $h{Stime} = $b[14] / 100;
  my @l;
  foreach ( sort keys %thresh )
  {
    next unless $thresh{$_};
    if ( $h{$_} >= $thresh{$_} ) { push @l,$_; }
  }
  if ( @l )
  {
    print scalar localtime,": PID=$pid exceeded=>(",join(',',@l),') ',
	join(' ',map { "$_=$h{$_}" } sort keys %h),
	"\n";
  }
}

exit 0 unless $interval;
sleep $interval;

# A goto! Shame on me!
goto LOOP;
