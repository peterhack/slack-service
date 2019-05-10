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
        
        string callerEndpoint = io:sprintf("%s://%s:%s", caller.protocol, caller.remoteAddress.host, caller.remoteAddress.port);
        log:printInfo("received event from " + callerEndpoint);

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
        string eventType = extractEventTypeFromEvent(event);
        string text = "*" + eventType.toUpper() + "*\n";
        boolean eventTypeKnown = isEventTypeKnown(event.^"type");

        if (eventTypeKnown) {
            if (payload.data.project != ()) {
                text += "Project:\t`" + event.data.project + "`\n";
            }

            if (payload.data.^"service" != ()) {
                text += "Service:\t`" + event.data.^"service" + "`\n";
            }

            if (payload.data.image != ()) {
                text += "Image:  \t`" + event.data.image + ":" + event.data.tag + "`\n";
            }

            if (payload.data.stage != ()) {
                text += "Stage:  \t`" + event.data.stage + "`\n";
            }

            if (payload.data.ProblemID != () && payload.data.ProblemTitle != ()) {
                text += "Problem:\t`" + event.data.ProblemID + ": " + event.data.ProblemTitle + "`\n";
            }

            if (payload.data.ImpactedEntity != ()) {
                text += "Impacted:\t`" + event.data.ImpactedEntity + "`\n";
            }
        }
        else {
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
    boolean eventTypeKnown = false;
    
    match eventType {
        "sh.keptn.events.new-artefact" => eventTypeKnown = true;
        "sh.keptn.events.configuration-changed" => eventTypeKnown = true;
        "sh.keptn.events.deployment-finished" => eventTypeKnown = true;
        "sh.keptn.events.tests-finished" => eventTypeKnown = true;
        "sh.keptn.events.evaluation-done" => eventTypeKnown = true;
        "sh.keptn.events.problem" => eventTypeKnown = true;
    }

    return eventTypeKnown;
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