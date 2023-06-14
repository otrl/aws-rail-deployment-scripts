#!/usr/bin/env python
#
# Usage:
#       export AWS_ACCESS_KEY_ID="your key id"
#       export AWS_SECRET_ACCESS_KEY="your secret"
#       python ec2_instances.py
#

import os
import boto3
import datetime

## The boto3 client expects the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
## to be environment variables.  Make sure they are set before running
## the script

### Quickly test it by setting your aws creds here
# os.environ['AWS_ACCESS_KEY_ID'] = ""
# os.environ['AWS_SECRET_ACCESS_KEY'] = ""

AWS_KEY = os.environ['AWS_ACCESS_KEY_ID']
AWS_SECRET = os.environ['AWS_SECRET_ACCESS_KEY']
AWS_REGION = "eu-west-1"

output_file = "instances.html"
default_domain = "otrldev.uk"
default_site = "southern"
jenkins_terminate_job = "https://jenkins.otrl.io/job/SID-Box-Terminate"

now = datetime.datetime.now()
days_until_warning = 7
days_until_danger = 14
days_until_stupid = 30


def main():

    ## Get all running EC2 Instances so we can build the sidbox list
    ec2 = boto3.client('ec2', region_name=AWS_REGION)
    ec2instances = ec2.describe_instances(
        Filters=[
            {
                'Name': 'tag:role',
                'Values': [
                    'test',
                ]
            },
        ]
    ).get("Reservations")

    instances = {}
    for reservation in ec2instances:
        for instance in reservation["Instances"]:
            tags = instance["Tags"]
            build_tags = {}

            for tag in tags:
                build_tags[tag["Key"]] = tag["Value"]

            if build_tags["build"] != "buildandscan":
                instances[build_tags["build"]] = {}
                instances[build_tags["build"]]['name'] = build_tags["build"]
                instances[build_tags["build"]]['owner'] = build_tags["launched_by_name"] if build_tags["launched_by_name"] != "" else 'Unknown'
                instances[build_tags["build"]]['website'] = 'https://southern.' + build_tags['hostname']
                instances[build_tags["build"]]['hostname'] = build_tags['hostname']
                instances[build_tags["build"]]['portainer'] = 'http://' + build_tags['hostname'] + ":9000"
                instances[build_tags["build"]]['rabbit'] = ""
                instances[build_tags["build"]]['launched_at'] = build_tags['launched_at']



    ## Get a list of Rabbit MQ instances in and build the console link
    mq = boto3.client('mq', region_name=AWS_REGION)
    mqinstances = mq.list_brokers(MaxResults=50).get("BrokerSummaries")

    for res in mqinstances:
        build = res["BrokerName"].split("-rabbit-dev")[0]
        if build in instances:
            instances[build]['rabbit'] ="https://" + res["BrokerId"] + ".mq." + AWS_REGION + ".amazonaws.com"


    for res in instances:
        instances[res]['launched'] = (now.date() - datetime.datetime.strptime(instances[res]['launched_at'], "%Y-%m-%dT%H:%M:%Sz").date()).days
        instances[res]['tr_class'] = "danger" if instances[res]['launched'] > days_until_danger else "warning" if instances[res]['launched'] > days_until_warning else ""
        instances[res]['launched'] = build_launch_date(instances[res]['launched'])


    make_html(sorted(instances.items()))


def build_launch_date(days_ago):

    if days_ago == 0:
        return_val = "Today"
    elif days_ago == 1:
        return_val = "{0} day ago".format(days_ago)
    else:
        return_val = "{0} days ago".format(days_ago)

    return return_val

def make_html(instances):
    table_rows = ""
    for res in instances:
        table_rows += make_row(res[1])

    with open(output_file, 'w') as f:
        f.write(base_document(now, table_rows, "", len(instances)))
        f.close()


def make_row(instance):
    return """
    <!-- desktop -->
    <tr class="hidden-xs hidden-sm {tr_class}">
        <td class="text-center">
            <a href="https://southeastern.{hostname}" style="font-size:10px;" title="southeastern" target="_blank">
                <img height="20px" width="20px" src="data:image/png;base64,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" />
            </a> |           
            <a href="https://thameslink.{hostname}" style="font-size:10px;" title="thameslink" target="_blank">
                <img height="20px" width="20px" src="data:image/png;base64,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" />
            </a> |
            <a href="https://greatnorthern.{hostname}" style="font-size:10px;" title="greatnorthern" target="_blank">
                <img height="20px" width="20px" src="data:image/png;base64,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" />
            </a> |
            <a href="https://gatwick.{hostname}" style="font-size:10px;" title="gatwick" target="_blank">
                <img height="20px" width="20px" src="data:image/png;base64,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" />
            </a> |
             <a href="https://southern.{hostname}" style="font-size:10px;" title="southern" target="_blank">
                <img height="20px" width="20px" src="data:image/png;base64,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" />
            </a>      
        </td>
        <td><a href="{website}" class="text-uppercase">{name}</a> 
            <a title="Portainer" style="float:right;margin-left:5px" href="{portainer}" target="_blank"><i class="glyphicon glyphicon-cog"></i></a>
            <a title="RabbitMq" style="float:right" href="{rabbit}" target="_blank"><i class="glyphicon glyphicon-registration-mark"></i></a>
        </td>
        <td>{hostname}</td>
            
        <td class="text-center">{launched}</td>
        <td class="text-center text-capitalize">{owner}</td>        
        <td>
            <form method="get" target="jenkins" action="{jenkins_terminate_job}/parambuild/">
                 <input type="hidden" name="BUILD_NAME" value="{name}">
                 <button type="submit"
                         class="btn btn-sm btn-block btn-warning"
                         onclick="return confirm('Are you sure you want to destroy the **{name}** environment?')">
                  Terminate&nbsp;<i class="glyphicon glyphicon-trash"></i>
                 </button>
             </form>
        </td>
    </tr>

    <!-- mobile -->
    <tr class="visible-xs visible-sm {tr_class}">
        <td>
            <ul class="visible-xs visible-sm list-unstyled">
                <li class="text-uppercase">
                    <i class="glyphicon glyphicon-home"/></i>&nbsp;
                    <a href="{website}">{name}</a>
                </li>                
                <li><i class="glyphicon glyphicon-console"></i>{hostname}</li>
                <li><i class="glyphicon glyphicon-settings"></i><a href="{portainer}">Portainer</a></li>
                <li><i class="glyphicon glyphicon-time"></i> {launched} </li>
                <li><i class="glyphicon glyphicon-user"></i> {owner}</li>                
            </ul>
             <form method="get" target="jenkins" action="{jenkins_terminate_job}/parambuild/">
                 <input type="hidden" name="BUILD_NAME" value="{name}">
                 <button type="submit"
                         class="btn btn-sm btn-block btn-warning"
                         onclick="return confirm('Are you sure you want to destroy the **{name}** environment?')">
                  Terminate&nbsp;<i class="glyphicon glyphicon-trash"></i>
                 </button>
             </form>
        </td>
    </tr>
    """.format(name=instance["name"],
               tr_class=instance["tr_class"],
               jenkins_terminate_job=jenkins_terminate_job,
               hostname=instance["hostname"],
               owner=instance["owner"],
               website=instance["website"],
               portainer=instance["portainer"],
               rabbit=instance["rabbit"],
               launched=instance["launched"]
               )



def base_document(script_run, table_rows, jenkins_terminate_job, total_instances):
    return """
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
               {total} test instances running
               </small>
             </h1>
             <p>Generated:
               <time class="timeago initialism text-info" datetime="{datetime}">
                   {datetime}
               </time>
             </p>
           </div>
           <div class="alert alert-info">
               Note: Clicking a <b>Terminate instance</b>
               button will redirect you to the sidbox terminate job in jenkins with the box prefilled.
               Once there, you must trigger the job!
           </div>
    
           <table class="table table-bordered table-hover table-condensed">
               <tr class="hidden-xs hidden-sm">
                   <th class="text-center">Brands</th>
                   <th class="text-center">Instance name</th>
                   <th class="text-center">Hostname</th>                                      
                   <th class="text-center">Launched</th>
                   <th class="text-center">Created by</th>
                   <!-- <th class="text-center">Expires in..</th> -->
                   <th></th>
               </tr>
               {rows}
           </table>
       </div>
       <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
       <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery-timeago/1.5.4/jquery.timeago.min.js"></script>
       <script>
           if (typeof jQuery != 'undefined') {{
             jQuery(document).ready(function() {{
               jQuery("time.timeago").timeago();
             }});
           }}
   </script>       
     </body>
    </html>
    """.format(rows=table_rows, datetime=script_run, jenkins_terminate_job=jenkins_terminate_job, total=total_instances)

if __name__ == "__main__":
    main()
