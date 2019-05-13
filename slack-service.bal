import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerina/config;
import ballerina/test;

type KeptnData record {
    string image?;
    string tag?;
    string project?;
    string ^"service"?;
    string stage?;
    string State?;
    string ProblemID?;
    string ProblemTitle?;
    string ImpactedEntity?;
    anydata...;
};

type KeptnEvent record {
    string specversion;
    string ^"type";
    string source?;
    string id?;
    string time?;
    string datacontenttype;
    string shkeptncontext;
    KeptnData data;
};

const NEW_ARTEFACT = "sh.keptn.events.new-artefact";
const CONFIGURATION_CHANGED = "sh.keptn.events.configuration-changed";
const DEPLOYMENT_FINISHED = "sh.keptn.events.deployment-finished";
const TESTS_FINISHED = "sh.keptn.events.tests-finished";
const EVALUATION_DONE = "sh.keptn.events.evaluation-done";
const PROBLEM = "sh.keptn.events.problem";
type KEPTN_EVENT NEW_ARTEFACT|CONFIGURATION_CHANGED|DEPLOYMENT_FINISHED|TESTS_FINISHED|EVALUATION_DONE|PROBLEM;
type KEPTN_CD_EVENT NEW_ARTEFACT|CONFIGURATION_CHANGED|DEPLOYMENT_FINISHED|TESTS_FINISHED|EVALUATION_DONE;

listener http:Listener slackSubscriberEP = new(8080);

@http:ServiceConfig {
    basePath: "/"
}
service slackservice on slackSubscriberEP {
    @http:ResourceConfig {
        methods: ["POST"],
        path: "/"
    }
    resource function handleEvent(http:Caller caller, http:Request request) {
        http:Client slackEndpoint = new(getSlackWebhookUrlHost());

        json|error payload = request.getJsonPayload();

        if (payload is error) {
            log:printError("error reading JSON payload", err = payload);
        }
        else {
            http:Request req = new;
            json slackMessageJson = generateMessage(payload);
            req.setJsonPayload(slackMessageJson);

            var response = slackEndpoint->post(getSlackWebhookUrlPath(), req);
            _ = handleResponse(response);
        }   

        http:Response res = new;
        checkpanic caller->respond(res);
    }
}

function getSlackWebhookUrlHost() returns string {
    string slackWebhookUrl = config:getAsString("SLACK_WEBHOOK_URL");
    int indexOfServices = slackWebhookUrl.indexOf("/services");

    if (indexOfServices == -1) {
        error err = error("Environment variable SLACK_WEBHOOK_URL is either missing or doesn't have the format 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX' (see https://api.slack.com/incoming-webhooks for more information)");
        panic err;
    }

    return slackWebhookUrl.substring(0, indexOfServices);
}

function getSlackWebhookUrlPath() returns string {
    string slackWebhookUrl = config:getAsString("SLACK_WEBHOOK_URL");
    int indexOfServices = slackWebhookUrl.indexOf("/services");
    return slackWebhookUrl.substring(indexOfServices, slackWebhookUrl.length());
}

function generateMessage(json payload) returns @untainted json {
    KeptnEvent|error event = KeptnEvent.convert(payload);

    if (event is error) {
        log:printError("error converting JSON payload '" + payload.toString() + "' to keptn event", err = event);
    }
    else {
        string text = "";
        string eventType = event.^"type";

        if (eventType is KEPTN_EVENT) {
            // new-artefact, configuration-changed, deployment-finished, tests-finished, evaluation-done
            if (eventType is KEPTN_CD_EVENT) {
                string knownEventType = getUpperCaseEventTypeFromEvent(event);
                text += "*" + knownEventType + "*\n";
                text += "Project:\t`" + event.data.project + "`\n";
                text += "Service:\t`" + event.data.^"service" + "`\n";
                text += "Image:  \t`" + event.data.image + ":" + event.data.tag + "`\n";
                // configuration-changed, deployment-finished, tests-finished, evaluation-done
                if (!(eventType is NEW_ARTEFACT)) {
                    text += "Stage:  \t`" + event.data.stage + "`\n";
                }
            }
            // problem
            else {
                text += "Problem:\t`" + event.data.ProblemID + ": " + event.data.ProblemTitle + "`\n";
                text += "Impact: \t`" + event.data.ImpactedEntity + "`\n";
            }  
        }
        else {
            text += "*" + event.^"type".toUpper() + "*\n";
            text += "keptn can't process this event, the event type is unknown";
        }

        return generateSlackMessageJSON(text, event);
    }
}

function getUpperCaseEventTypeFromEvent(KeptnEvent event) returns string {
    string eventType = event.^"type";
    int indexOfLastDot = eventType.lastIndexOf(".") + 1;
    eventType = eventType.substring(indexOfLastDot, eventType.length());
    eventType = eventType.replace("-", " ");
    return eventType.toUpper();
}

function generateSlackMessageJSON(string text, KeptnEvent event) returns json {
    json message = {
        text: text,
        blocks: [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": text
                },
                "accessory": {
                    "type": "image",
                    "image_url": getImageLink(event),
                    "alt_text": "alt"
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": getKeptnContext(event)
                    }
                ]
            },
            {
                "type": "divider"
            }
        ]
    };
    return message;
}

function getImageLink(KeptnEvent event) returns string {
    return "https://via.placeholder.com/150";
}

function getKeptnContext(KeptnEvent event) returns string {
    string template = "keptn-context: %s";
    string templateWithLink = "keptn-context: <%s|%s>";
    string url = config:getAsString("BRIDGE_URL", defaultValue = "");
    string keptnContext = "";

    if (url == "") {
        keptnContext = io:sprintf(template, event.shkeptncontext);
    }
    else {
        url += "/view-context/%s";
        string formattedURL = io:sprintf(url, event.shkeptncontext);
        keptnContext = io:sprintf(templateWithLink, formattedURL, event.shkeptncontext);
    }

    return keptnContext;
}

function handleResponse(http:Response|error response) {
    if (response is http:Response) {
        string|error res = response.getTextPayload();
        if (res is error) {
            io:println(res);
        }
        else {
            log:printInfo("event successfully sent to Slack - response: " + res);
        }
    } else {
        io:println("Error when calling the backend: ", response.reason());
    }
}

// tests
@test:Config
function testSlackWebhookUrlHostParsing() {
    string url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX";
    config:setConfig("SLACK_WEBHOOK_URL", url);

    string host = getSlackWebhookUrlHost();
    test:assertEquals(host, "https://hooks.slack.com");
}

@test:Config
function testSlackWebhookUrlPathParsing() {
    string url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX";
    config:setConfig("SLACK_WEBHOOK_URL", url);

    string path = getSlackWebhookUrlPath();
    test:assertEquals(path, "/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX");
}

@test:Config
function testGetUpperCaseEventTypeFromEvent() {
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "",
        data: {},
        ^"type": "something.bla.bla.new-artefact"
    };

    string eventType = getUpperCaseEventTypeFromEvent(event);
    test:assertEquals(eventType, "NEW ARTEFACT");
}

@test:Config
function testGenerateSlackMessageJSON() {
    json expected = {
        text: "hello world",
        blocks: [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "hello world"
                },
                "accessory": {
                    "type": "image",
                    "image_url": "https://via.placeholder.com/150",
                    "alt_text": "alt"
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "keptn-context: 12345"
                    }
                ]
            },
            {
                "type": "divider"
            }
        ]
    };
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "12345",
        data: {},
        ^"type": "test-message"
    };
    json actual = generateSlackMessageJSON("hello world", event);
    test:assertEquals(actual, expected);
}

@test:Config
function testGenerateMessageWithUnknownEventType() {
    json expected = {
        text: "*COM.SOMETHING.EVENT*\nkeptn can't process this event, the event type is unknown",
        blocks: [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "*COM.SOMETHING.EVENT*\nkeptn can't process this event, the event type is unknown"
                },
                "accessory": {
                    "type": "image",
                    "image_url": "https://via.placeholder.com/150",
                    "alt_text": "alt"
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "keptn-context: 123"
                    }
                ]
            },
            {
                "type": "divider"
            }
        ]
    };
    json payload = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "123",
        data: {},
        ^"type": "com.something.event"
    };
    json actual = generateMessage(payload);
    test:assertEquals(actual, expected);
}

@test:Config
function testGetKeptnContextDefault() {
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "a9b94cff-1b10-4018-9b78-28898f78800d",
        data: {},
        ^"type": ""
    };
    string expected = "keptn-context: a9b94cff-1b10-4018-9b78-28898f78800d";
    string actual = getKeptnContext(event);
    test:assertEquals(actual, expected);
}

@test:Config{
    dependsOn: ["testGetKeptnContextDefault",
        "testGenerateMessageWithUnknownEventType",
        "testGenerateSlackMessageJSON",
        "testGetUpperCaseEventTypeFromEvent",
        "testSlackWebhookUrlPathParsing",
        "testSlackWebhookUrlHostParsing"
    ]
}
function testGetKeptnContext() {
    config:setConfig("BRIDGE_URL", "https://www.google.at");
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "12345",
        data: {},
        ^"type": ""
    };
    string expected = "keptn-context: <https://www.google.at/view-context/12345|12345>";
    string actual = getKeptnContext(event);
    test:assertEquals(actual, expected);
}
