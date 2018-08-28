#!/usr/bin/perl

#Shutdown or terminate test instances each night.
#A second script will launch stopped instances each morning

use strict;
use warnings;
use Date::Format;
use Time::Piece;
use VM::EC2;

my $now = gmtime;
my $AWS_KEY = $ENV{'AWS_ACCESS_KEY_ID'};
my $AWS_SECRET = $ENV{'AWS_SECRET_ACCESS_KEY'};
my $AWS_REGION = "eu-west-1";

####

if (!$AWS_KEY or !$AWS_SECRET) {
  print "The environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY need to be set.\n";
  exit(1);
}

my $ec2 = VM::EC2->new( -access_key => $AWS_KEY,
                        -secret_key => $AWS_SECRET,
                        -region     => $AWS_REGION
                      );

my @ec2_instances = $ec2->describe_instances({'tag:role' => 'test', 'tag:terminate_after' => '*', 'instance-state-name'=>'running'}) or die("Can't connect to AWS");
my $terminate;

foreach my $i (@ec2_instances) {
  
  $terminate = 0;
  print $i->tags->{Name};
  
  if ($i->tags->{terminate_after}) {
    my $expires = Time::Piece->strptime(substr($i->tags->{terminate_after},0,-5), '%Y-%m-%dT%H:%M:%S');
    my $expires_diff = $expires - $now;
    my $expires_in = int($expires_diff->days);
    print " expires in $expires_in days ";
    if ($expires < $now) { $terminate = 1; }
  }

  if ($terminate eq 1) {
    print " - terminate\n";
    #$i->terminate;
  }
  else {
    print " - shut down.\n";
    $i->stop;
  }

}
