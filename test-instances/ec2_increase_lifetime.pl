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
my $instance_name;
my $add_hours;

####

if (!$AWS_KEY or !$AWS_SECRET) {
  print "The environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY need to be set.\n";
  exit(1);
}

if (!$ARGV[1]) {
  print "\nUsage: $0 instance_name hours_to_add\n\nYou must provide the instance name (as set in the instance's 'build' tag)\nand the number of hours to add to the termination time of the instance.\n\n";
  exit(1);
}
else {
  $instance_name = $ARGV[0];
  $add_hours = $ARGV[1];
}


my $ec2 = VM::EC2->new( -access_key => $AWS_KEY,
                        -secret_key => $AWS_SECRET,
                        -region     => $AWS_REGION
                      );

print "Searching for $instance_name\n";

my @ec2_instances = $ec2->describe_instances({'tag:role' => 'test', 'tag:terminate_after' => '*', 'tag:build' => $instance_name}) or die("Can't connect to AWS or no instances found.");
my $i = $ec2_instances[0];
$expires = Time::Piece->strptime(substr($i->tags->{terminate_after},0,-5), '%Y-%m-%dT%H:%M:%S');

print "\n\nUpdating the termination date for " . $i->tags->{Name} . " from $expires to ";
$expires = $expires + (60 * 60 * $add_hours);
print "$expires\n\n";
$i->add_tags( terminate_after => $expires->datetime . "Z") or die("Can't update the terminate_after tag value.");
