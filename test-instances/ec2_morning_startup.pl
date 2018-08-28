#!/usr/bin/perl

#Start any stopped test instances each morning.

use strict;
use warnings;
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

my @ec2_instances = $ec2->describe_instances({'tag:role' => 'test', 'tag:terminate_after' => '*', 'instance-state-name'=>'stopped'}) or die("Can't connect to AWS");
my $terminate;

foreach my $i (@ec2_instances) {

  print "Starting " . $i->tags->{Name} . "...\n";
  $i->start;

}
