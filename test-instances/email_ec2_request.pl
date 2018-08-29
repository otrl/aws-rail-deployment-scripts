#!/usr/bin/perl

#Send an email to each person to remind them of instances that will be automatically
#terminated in the near future.
#The default is eight days - this can be overridden by passing the number of days
#as an argument to the script:
#
#./email_ec2_request.pl 5

use strict;
use warnings;
use Date::Format;
use Time::Piece;
use MIME::Lite;
use VM::EC2;

my $warn_days_before_termination = 8;
my $from_email = 'jenkins@otrl.io';
my $ignore_owner = 'dev@otrl.io';
my $reprieve_url = 'https://jenkins.otrl.io/job/extend_instance_life/parambuild?instance_name=';
my %owners;
my $now = gmtime;
my $jenkins_host_ip = "10.0.251.36";
my $AWS_KEY = $ENV{'AWS_ACCESS_KEY_ID'};
my $AWS_SECRET = $ENV{'AWS_SECRET_ACCESS_KEY'};
my $AWS_REGION = "eu-west-1";

######

sub ordinal ($) {
    $_[0] =~ /(1?\d)$/ or return;
    return $_[0] . ((qw'th st nd rd')[$1] || 'th');
}

######

if ($ARGV[0] and $ARGV[0] =~ /^\d+?$/) { $warn_days_before_termination = $ARGV[0] };


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
 if ($i->tags->{terminate_after} and $i->tags->{build} and $i->current_status eq 'running' and $i->tags->{launched_by_email} ne $ignore_owner and $i->tags->{launched_by_email} ne "") {

  my $this_owner = $i->tags->{launched_by_email};
  my $this_name  = $i->tags->{build};
  
  #Time stuff
  
  my $running_since = Time::Piece->strptime(substr($i->tags->{launched_at},0,-5), '%Y-%m-%dT%H:%M:%S');
  my $running_since_diff = $running_since - $now;
  my $running_days = int($running_since_diff->days);
  if ($running_days eq 0) { $running_days="less than a"; }
  
  my $expires = Time::Piece->strptime(substr($i->tags->{terminate_after},0,-5), '%Y-%m-%dT%H:%M:%S');
  my $expires_diff = $expires - $now;
  my $expires_days = int($expires_diff->days);

  if ($expires_days <= $warn_days_before_termination) { 
   $owners{$this_owner}{$this_name}{'age'} = $running_days;
   $owners{$this_owner}{$this_name}{'expires_days'} = $expires_days;
   $owners{$this_owner}{$this_name}{'expires_after'} = $expires->fullday . " " . ordinal($expires->mday) . " of " . $expires->fullmonth;
  }

 }
}

foreach my $owner (sort(keys %owners)) {

 my $owned_instances = keys %{$owners{$owner}};
 my $this_subject = "[Jenkins EC2 report] You have $owned_instances running instance";
 if ($owned_instances != 1) { $this_subject .=  "s"; }
 
 my $this_msg = "<h3>EC2 instance termination warnings:</h3><p>Here's a list of instances you launched that will be terminated soon:<br><p>\n";
 $this_msg = "<ul>\n";
 
 foreach my $owned_instance (keys %{$owners{$owner}}) {
  $this_msg .= "<li> <b>$owned_instance</b>, created ${owners{$owner}{$owned_instance}{'age'}} days";
  if (${owners{$owner}{$owned_instance}{'age'}} eq "1") { chop($this_msg) }
  $this_msg .= " ago will be terminated on the evening of ${owners{$owner}{$owned_instance}{'expires_after'}}.";
  $this_msg .= " <a href='${reprieve_url}$owned_instance'>Extend instance life</a>";
  $this_msg .= "</li>\n";
 }


 my $msg = MIME::Lite->new(
                 From     => $from_email,
                 To       => $owner,
                 Subject  => $this_subject,
                 Data     => $this_msg
                 );
                 
 $msg->attr("content-type" => "text/html");
 print "Emailed to $owner\n";
 $msg->send('smtp',$jenkins_host_ip);

}

################


