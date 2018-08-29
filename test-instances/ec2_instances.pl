#!/usr/bin/perl
#
use strict;
use warnings;
use Date::Format;
use Time::Piece;
use File::Basename;
use VM::EC2;

my $AWS_KEY = $ENV{'AWS_ACCESS_KEY_ID'};
my $AWS_SECRET = $ENV{'AWS_SECRET_ACCESS_KEY'};
my $AWS_REGION = "eu-west-1";
my $reprieve_url = 'https://jenkins.otrl.io/job/extend_instance_life/parambuild?instance_name=';

if (!$AWS_KEY or !$AWS_SECRET) {
 print "The environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY need to be set.\n";
 exit(1);
}

my $default_domain = "otrldev.uk";
my $default_site = "southern";
my $jenkins_terminate_job = "https://jenkins.otrl.io/job/sniffles-destroy";

my $now = gmtime;
my $days_until_warning = 2;
my $days_until_danger  = 5;

my $ec2 = VM::EC2->new( -access_key => $AWS_KEY,
                        -secret_key => $AWS_SECRET,
                        -region     => $AWS_REGION
                      ) or die("Can't connect to AWS");

my @ec2_instances = $ec2->describe_instances({'tag:role' => 'test'});
my %instances;

foreach my $i (@ec2_instances) {
 if ($i->tags->{build} and $i->current_status eq 'running') {
  
  my $this_name = $i->tags->{build};
  
  $instances{$this_name}{'ip'} = $i->privateIpAddress;
  $instances{$this_name}{'owner'} = $i->tags->{launched_by_name} || 'Unknown';

  #Fetch the hostname tag from the instance.  If there isn't one,
  #then make a decent guess at what it'll be based on the build
  #name & default domain & default site prefix.
  if ($i->tags->{hostname}) {
   $instances{$this_name}{'hostname'} = $default_site . "." . $i->tags->{hostname};
  }
  else {
   my $this_hostname = $this_name;
   $this_hostname =~ s/_/-/g;
   $instances{$this_name}{'hostname'} = $default_site . "." . $this_hostname . "." . $default_domain;
  };

  if ($i->tags->{terminate_after}) {
   my $expires = Time::Piece->strptime(substr($i->tags->{terminate_after},0,-5), '%Y-%m-%dT%H:%M:%S');
   my $expires_diff = $expires - $now;
   my $expires_days = int($expires_diff->days);
   my $expires_text = "$expires_days day";
   if ($expires_days ne 1) { $expires_text .= "s"; }
   $expires_text .= " left.<br>(<a href='${reprieve_url}$this_name'>extend instance life</a>)";
   $instances{$this_name}{'expires'} = $expires_text;
  }
  else {
   $instances{$this_name}{'expires'} = "n/a";
  }

  #Time stuff
  my $this_tp;
  if ($i->tags->{launched_at}) {
   $this_tp = Time::Piece->strptime(substr($i->tags->{launched_at},0,-5), '%Y-%m-%dT%H:%M:%S');
  }
  else {
   $this_tp = Time::Piece->strptime(substr($i->launchTime,0,-5), '%Y-%m-%dT%H:%M:%S');
  }
  $instances{$this_name}{'created'} = $this_tp->strftime('%a %e %b, %H:%M %P');
  my $days = $now - $this_tp;
  my $age = int($days->days);

  $instances{$this_name}{'age'} = $age == 1 ? "$age day" : "$age days";

  if ( !defined $i->tags->{no_age_alert} ) {
   $instances{$this_name}{'tr_class'} = "";
   if (int($days->days) >= $days_until_warning ) { $instances{$this_name}{'tr_class'} = 'warning'; }
   if (int($days->days) >= $days_until_danger  ) { $instances{$this_name}{'tr_class'} = 'danger';  }
  }
 }
}

print make_html(\%instances);

sub get_repos {
    my $repos = shift;
    if ($repos) {
        return join ', ', split /,/, $repos;
    } else {
        return 'n/a';
    }
}

sub make_html {
    my $instances = shift;
    my $rows = join "",
        map { make_row($_, $instances->{$_}) }
        sort(keys %$instances);

    my $template = do { local $/; <DATA> };
    my @now = localtime();
    return template($template, {
        datetime => strftime('%Y-%m-%dT%H:%M:%S%z', @now, 'GMT'),
        num_instances => scalar keys %$instances,
        jenkins_terminate_job => $jenkins_terminate_job,
        table_rows => $rows
    });
}

sub make_row {
    my ($name, $vars) = @_;

    my $terminate_button = terminate_button_html($name, %$vars{'owner'});
    my %data = ((name => $name, terminate_button => $terminate_button), %$vars);
    my $template = <<'ROW';
    <!-- desktop -->
    <tr class="hidden-xs hidden-sm {{ tr_class }}">
        <td class="text-uppercase"><a href="https://{{ hostname }}">{{ name }}</a></td>
        <td class="text-center">{{ age }}</td>
        <td class="text-center">{{ owner }}</td>
        <td class="text-center">{{ created }}</td>
        <td class="text-center">{{ ip }}</td>
        <td class="text-center">{{ expires }}</td>
        <td>
            {{{ terminate_button }}}
        </td>
    </tr>

    <!-- mobile -->
    <tr class="visible-xs visible-sm {{ tr_class }}">
        <td>
            <ul class="visible-xs visible-sm list-unstyled">
                <li class="text-uppercase">
                    <i class="glyphicon glyphicon-home"/></i>&nbsp;
                    <a href="https://{{ hostname }}">{{ name }}</a>
                </li>
                <li><i class="glyphicon glyphicon-globe"></i> {{ ip }}</li>
                <li><i class="glyphicon glyphicon-user"></i> {{ owner }}</li>
                <li><i class="glyphicon glyphicon-time"></i> {{ age }} </li>
                <li><i class="glyphicon glyphicon-calendar"></i> {{ created }}</li>
                <li><i class="glyphicon glyphicon-fire"></i> {{ expires }}</li>
            </ul>
            {{{ terminate_button }}}
        </td>
    </tr>
ROW
    return template($template, \%data);
}

sub terminate_button_html {
    my $name = shift;
    my $job = shift;
    my $template = <<'TERMINATE_BUTTON';
    <form method="post" target="jenkins" action="{{ job }}/buildWithParameters">
     <input type="hidden" name="token" value="zWZS0cMc27QuDbcAboQltuOOBvOPoPuq">
     <input type="hidden" name="BUILD_NAME" value="{{ name }}">
     <button type="submit"
             class="btn btn-sm btn-block btn-warning"
             onclick="return confirm('Are you sure you want to destroy the **{{ name }}** envirionment?')">
      Terminate&nbsp;<i class="glyphicon glyphicon-trash"></i>
     </button>
    </form>
TERMINATE_BUTTON
    return template($template, {
        name => $name,
        job => $jenkins_terminate_job
    });
}

sub template { # crude templating ;p
    my ($template, $vars) = @_;
    $template =~ s/\{\{\{\s*(\w+)\s*\}\}\}/defined $vars->{$1} ? $vars->{$1} : ''/ge;
    $template =~ s/\{\{\s*(\w+)\s*\}\}/$vars->{$1}/g; # this should be escaped really
    return $template;
}


__DATA__
<!DOCTYPE html>
<html lang="en">
 <head>
  <title>Running EC2 instances</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/3.3.7/css/bootstrap.min.css">
 </head>
 <body>
   <div class="container">
       <div class="page-header">
         <h1>
           <img height="50px" width="50px" src="data:image/png;base64,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"/>
           Test instance report
           <small>
               <span class="badge">{{ num_instances }}</span>
           </small>
         </h1>
         <p>Generated:
           <time class="timeago initialism text-info" datetime="{{ datetime }}">
               {{ datetime }}
           </time>
         </p>
       </div>
       <div class="alert alert-info">
           Note: Clicking a <b>Terminate instance</b>
           button will run the terminate job and then redirect you to the job page
           within a few seconds. Please only press the button once - the job <i>is</i> running.
       </div>

       <table class="table table-bordered table-hover table-condensed">
           <tr class="hidden-xs hidden-sm">
               <th class="text-center">Instance name</th>
               <th class="text-center">Age (days)</th>
               <th class="text-center">Created by</th>
               <th class="text-center">Created</th>
               <th class="text-center">IP</th>
               <th class="text-center">Expires in..</th>
               <th></th>
           </tr>
           {{{ table_rows }}}
       </table>
   </div>
   <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
   <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery-timeago/1.5.4/jquery.timeago.min.js"></script>
   <script>
       if (typeof jQuery != 'undefined') {
         jQuery(document).ready(function() {
           jQuery("time.timeago").timeago();
         });
       }

       (function initialiseIframe () {
           var iframe = document.createElement('iframe');
           iframe.setAttribute('src', 'about:blank');
           iframe.setAttribute('name', 'jenkins');
           iframe.setAttribute('class', 'hide');
           iframe.addEventListener('load', function () {
               try {
                   hasLoadedIframe = !!iframe.contentWindow.location.hostname;
               } catch (e) { // failed when run locally because cross origin
                   hasLoadedIframe = false;
               }
               if (hasLoadedIframe) {
                   location.href="{{ jenkins_terminate_job }}";
               }
           });
           document.body.append(iframe);
       })();
   </script>
 </body>
</html>
