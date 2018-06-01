#!/usr/bin/env node
/**
 * Script to send a message on slack showing which EC2 test instances are running
 *
 * Usage: ./notify_slack.js
 */
const _ = require('lodash');
const fp = require('lodash/fp');
const moment = require('moment');
const getStdin = require('get-stdin');
const heredoc = require('heredocument');
const axios = require('axios');
const ec2 = require('aws-sdk/clients/ec2');

const AWS_REGION = 'eu-west-1'
const { AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY } = process.env;
if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
    console.error("The environmental variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY need to be set.");
    process.exit(1);
}

const instanceDayPrice = 700;
const slackConfig = {
    url: 'https://hooks.slack.com/services/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',
    channel: '#dev',
    username: 'Tiddles',
    icon_emoji: ':cat2:'
};
const catApiUrl = 'http://thecatapi.com/api/images/get?format=src&type=gif';

const getDaysSince = (dateStr) => moment().diff(moment(dateStr), 'days');

const getEc2Instances = () => {
    const ec2Client = new ec2({ region: AWS_REGION });
    const params = {
        Filters: [
            { Name: 'tag:role', Values: ['test'] }
        ]
    };
    return new Promise((resolve, reject) => {
        ec2Client.describeInstances(
            params,
            (err, instances) => err ? reject(err) : resolve(instances)
        );
    });
}


const getSidBoxData = (instance) => {
    const tags = getTagsObject(instance.Tags);
    const sidName = tags.hostname.replace(/\..*/, '');
    const owner = tags.launched_by_name;
    const created = instance.LaunchTime;
    const age = getDaysSince(created);
    const price = age * instanceDayPrice;
    const ip = instance.PrivateIpAddress;
    return {
        sidName,
        created,
        ip,
        owner,
        age,
        price
    };
};

const getTagsObject = fp.reduce(
    (res, { Key, Value }) => Object.assign(res, { [Key]: Value }), {}
);

const instancesToSidBoxes = fp.pipe(
    fp.get('Reservations'),
    fp.flatMap(({ Instances }) => Instances),
    fp.map(getSidBoxData)
);

const boxesToUsers = (boxes) => {
    return _.chain(boxes)
            .groupBy('owner')
            .entries()
            .map(([owner, devBoxes]) => ({
                name: owner,
                instanceCount: devBoxes.length,
                instanceDays: _.sumBy(devBoxes, 'age'),
            }))
            .sortBy(['name'])
            .value();
}

const extractBoxMetadata = (boxes) => ({
    totalDays: _.sumBy(boxes, 'age'),
    totalPrice: _.sumBy(boxes, 'price'),
    totalInstances: boxes.length,
    todaysPrice: boxes.length * instanceDayPrice,
    sortedByName: _.sortBy(boxes, ['sidName']),
    sortedByAge: _.sortBy(boxes, ['age', 'sidName']),
    users: boxesToUsers(boxes)
});

const toPounds = (pence) => _.round(pence / 100);

const formatBox = ({ sidName, age, price }) =>
    `_*${sidName}*_: ${age}d, £${toPounds(price)}`;

const formatUser = ({ name, instanceCount, instanceDays }) =>
    `_*${name}*_: x${instanceCount}, ${instanceDays}d`;

const formatLink = ([ url, linkText ]) => `<${url}|${linkText}>`;

const formatList = (items, renderer) => items.map(renderer).join(' | ');

const getCatGif = () => axios.head(catApiUrl, { maxRedirects: 0 })
    .catch(({ response }) => {
        return _.result(response, 'headers.location') || catApiUrl;
    });

const formatMessage = (meta) => {
    const links = [
        ['https://jenkins.otrl.io/job/sniffles-deploy/build?delay=0sec', 'create'],
        ['https://jenkins.otrl.io/job/sniffles-destroy/build?delay=0sec', 'terminate'],
        ['https://jenkins.otrl.io/job/Test%20Instances/ws/instances.html', 'full listing']
    ];
    return getCatGif()
        .then(gifUrl => ({
            text: 'Running Test instances :hadouken1: :hadouken2:',
            attachments: [
                {
                    text: heredoc`
                        *${meta.totalInstances}* instances (*£${toPounds(meta.todaysPrice)}/day*)
                        *${meta.totalDays}* cumulative days (*£${toPounds(meta.totalPrice)}*)
                        ${ formatList(links, formatLink) }
                    `,
                    mrkdwn_in: ['text'],
                    color: '0000ff'
                },
                {
                    title: '= By age (oldest first) =',
                    mrkdwn_in: ['text'],
                    text: formatList(meta.sortedByAge.reverse(), formatBox)
                },
                {
                    title: '= By dev =',
                    mrkdwn_in: ['text'],
                    text: formatList(meta.users, formatUser)
                },
                {
                    title: '= Finally... =',
                    image_url: gifUrl,
                    text: 'Remember to clean up unwanted instances.',
                    mrkdwn_in: ['text']
                }
            ]
        })
    );
};

const postMessage = (message = {}) => {
    const payload = Object.assign({}, slackConfig, message);
    return axios.post(payload.url, payload)
};

const main = () =>
    getEc2Instances()
        .then(instancesToSidBoxes)
        .then(extractBoxMetadata)
        .then(formatMessage)
        .then(postMessage);

main()
    .then(() => console.log('done!'))
    .catch(error => {
        console.error(error);
        throw error;
    });
