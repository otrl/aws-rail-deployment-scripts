#!/usr/bin/perl

#Send an email to each person that's spun-up EC2 instances
#with a list of their instances that have been running for
#at least a certain number of days.  The number of days can
#be passed as an argument.  e.g.:
#
#./ec2_instances_email.pl 5

use strict;
use warnings;
use Date::Format;
use Time::Piece;
use MIME::Lite;
use VM::EC2;

my $days_until_warning = 2;
my $from_email = 'jenkins@otrl.io';
my $ignore_owner = 'dev@otrl.io';
my $instance_report_url = 'https://jenkins.otrl.io/job/Test%20Instances/ws/instances.html';
my %owners;
my $now = gmtime;
my $jenkins_host_ip = "10.0.251.36";
my $AWS_KEY = $ENV{'AWS_ACCESS_KEY_ID'};
my $AWS_SECRET = $ENV{'AWS_SECRET_ACCESS_KEY'};
my $AWS_REGION = "eu-west-1";

if ($ARGV[0] and $ARGV[0] =~ /^\d+?$/) { $days_until_warning = $ARGV[0] };


if (!$AWS_KEY or !$AWS_SECRET) {
 print "The environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY need to be set.\n";
 exit(1);
}

my $ec2 = VM::EC2->new( -access_key => $AWS_KEY,
                        -secret_key => $AWS_SECRET,
                        -region     => $AWS_REGION
                      );

my @ec2_instances = $ec2->describe_instances({'tag:role' => 'test'}) or die("Can't connect to AWS");

foreach my $i (@ec2_instances) {
 if ($i->tags->{build} and $i->current_status eq 'running' and $i->tags->{launched_by_email} ne $ignore_owner and $i->tags->{launched_by_email} ne "" and !$i->tags->{terminate_after}) {

  my $this_owner = $i->tags->{launched_by_email};
  my $this_name  = $i->tags->{build};
  
  #Time stuff
  my $this_tp = Time::Piece->strptime(substr($i->launchTime,0,-5), '%Y-%m-%dT%H:%M:%S');
  my $this_time_diff = $now - $this_tp;
  my $this_age = int($this_time_diff->days);
  
  if ($this_age >= $days_until_warning) { $owners{$this_owner}{$this_name}{'age'} = $this_age; }
  
 }
}

foreach my $owner (sort(keys %owners)) {

 my $owned_instances = keys %{$owners{$owner}};
 my $this_subject = "[Jenkins EC2 report] You have $owned_instances running instance";
 if ($owned_instances != 1) { $this_subject .=  "s"; }
 
 my $this_msg = "<h3>EC2 instance report</h3><p>Here's a list of your instances that have been running for $days_until_warning day";
 if ($days_until_warning != 1) { $this_msg .= "s"; }
 $this_msg .= " or more:<p>\n";

 foreach my $owned_instance (keys %{$owners{$owner}}) {
  $this_msg .= "<b>$owned_instance</b>, running for ${owners{$owner}{$owned_instance}{'age'}} day";
  if (${owners{$owner}{$owned_instance}{'age'}} != 1) { $this_msg .= "s"; }
  $this_msg .= "<br>\n";
 }
 
 $this_msg .= "<p><a href='$instance_report_url'>Manage your instances here</a>.";
 
 my $msg = MIME::Lite->new(
                 From     => $from_email,
                 To       => $owner,
                 Subject  => $this_subject,
                 Data     => $this_msg
                 );
                 
 $msg->attr("content-type" => "text/html");         
 print "Sending email to $owner\n";
 $msg->send('smtp',$jenkins_host_ip);

}


