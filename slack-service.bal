import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerinax/docker;
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

final string NEW_ARTEFACT = "sh.keptn.events.new-artefact";
final string CONFIGURATION_CHANGED = "sh.keptn.events.configuration-changed";
final string DEPLOYMENT_FINISHED = "sh.keptn.events.deployment-finished";
final string TESTS_FINISHED = "sh.keptn.events.tests-finished";
final string EVALUATION_DONE = "sh.keptn.events.evaluation-done";
final string PROBLEM = "sh.keptn.events.problem";

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

        if (isEventTypeKnown(event.^"type")) {
            if (event.^"type".equalsIgnoreCase(NEW_ARTEFACT) ||
                event.^"type".equalsIgnoreCase(CONFIGURATION_CHANGED) ||
                event.^"type".equalsIgnoreCase(DEPLOYMENT_FINISHED) ||
                event.^"type".equalsIgnoreCase(TESTS_FINISHED) ||
                event.^"type".equalsIgnoreCase(EVALUATION_DONE)) {
                string eventType = extractEventTypeFromEvent(event);
                text += "*" + eventType.toUpper() + "*\n";
                text += "Project:\t`" + event.data.project + "`\n";
                text += "Service:\t`" + event.data.^"service" + "`\n";
                text += "Image:  \t`" + event.data.image + ":" + event.data.tag + "`\n";
                if payload.data.stage != () {
                    text += "Stage:  \t`" + event.data.stage + "`\n";
                }
            }
            if (event.^"type".equalsIgnoreCase(PROBLEM)) {
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

function extractEventTypeFromEvent(KeptnEvent event) returns string {
    string eventType = event.^"type";
    int indexOfLastDot = eventType.lastIndexOf(".") + 1;
    eventType = eventType.substring(indexOfLastDot, eventType.length());
    return eventType;
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
                        "text": "keptn-context: " + event.shkeptncontext
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

function isEventTypeKnown(string eventType) returns boolean {
    return eventType.equalsIgnoreCase(NEW_ARTEFACT) ||
        eventType.equalsIgnoreCase(CONFIGURATION_CHANGED) ||
        eventType.equalsIgnoreCase(DEPLOYMENT_FINISHED) ||
        eventType.equalsIgnoreCase(TESTS_FINISHED) ||
        eventType.equalsIgnoreCase(EVALUATION_DONE) ||
        eventType.equalsIgnoreCase(PROBLEM);
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
function testExtractEventTypeFromEvent() {
    KeptnEvent event = {
        specversion: "",
        datacontenttype: "",
        shkeptncontext: "",
        data: {},
        ^"type": "something.bla.bla.new-artefact"
    };

    string eventType = extractEventTypeFromEvent(event);
    test:assertEquals(eventType, "new-artefact");
}

@test:Config {
    dataProvider: "eventTypeDataProvider"
}
function testIsEventTypeKnown(string eventType, string expectedResult) {
    boolean eventTypeKnown = isEventTypeKnown(eventType);
    test:assertEquals(string.convert(eventTypeKnown), expectedResult);
}

function eventTypeDataProvider() returns (string[][]) {
    return [
        ["sh.keptn.events.new-artefact", "true"],
        ["sh.keptn.events.configuration-changed", "true"],
        ["sh.keptn.events.deployment-finished", "true"],
        ["sh.keptn.events.tests-finished", "true"],
        ["sh.keptn.events.evaluation-done", "true"],
        ["sh.keptn.events.problem", "true"],
        ["something", "false"]
    ];
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
        ^"type": ""
    };
    json actual = generateSlackMessageJSON("hello world", event);
    test:assertEquals(actual, expected);
}

@test:Config
function testGenerateMessageWithUnkownEventType() {
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
