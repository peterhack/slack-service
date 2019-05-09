import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerinax/docker;
import ballerina/config;

type KeptnEvent record {
    string specversion;
    string ^"type";
    string source?;
    string id?;
    string time?;
    string datacontenttype;
    string shkeptncontext;
    json data;
};

@docker:Expose {}
listener http:Listener slackSubscriberEP = new(8080);

@docker:Config {
    name: "keptn/slack-service"
}
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
            json slackMessageJson = {};

            KeptnEvent|error event = KeptnEvent.convert(payload);

            if (event is error) {
                log:printError("error converting JSON payload to keptn event", err = event);
            }
            else {
                match event.^"type" { 
                    "sh.keptn.events.new-artefact" => slackMessageJson = generateMessage("new artefact", "inbox_tray", event);
                    "sh.keptn.events.configuration-changed" => slackMessageJson = generateMessage("configuration changed", "file_folder", event);
                    "sh.keptn.events.deployment-finished" => slackMessageJson = generateMessage("deployment finished", "building_construction", event);
                    "sh.keptn.events.tests-finished" => slackMessageJson = generateMessage("tests finished", "sports_medal", event);
                    "sh.keptn.events.evaluation-done" => slackMessageJson = generateMessage("evaluation done", "checkered_flag", event);
                    "sh.keptn.events.problem" => slackMessageJson = generateMessage("problem", "fire", event);
                    _ => slackMessageJson = generateUnknownKeptnEventTypeMessage(event);
                }
            }

            http:Request req = new;
            req.setJsonPayload(slackMessageJson);

            var response = slackEndpoint->post(getSlackWebhookUrlPath(), req);
            _ = handleResponse(response);
        }   

        http:Response res = new;
        _ = caller -> respond(res);
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

function generateUnknownKeptnEventTypeMessage(KeptnEvent event) returns @untainted json {
    string text = "unknown event type `" + event.^"type" + "`, don't know what to do (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateMessage(string kind, string icon, KeptnEvent event) returns @untainted json {
    string text = "";
    // default event
    if (event.data.ProblemID == ()) {
        string image = io:sprintf("%s", event.data.image);
        string tag = io:sprintf("%s", event.data.tag);
        string project = io:sprintf("%s", event.data.project);
        string ^"service" = io:sprintf("%s", event.data.^"service");
        text = ":" + icon + ": " + kind + " `" + image + ":" + tag + "` in project `" + project + "` for service `" + ^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
    }
    // problem event
    else {
        string problemID = io:sprintf("%s", event.data.ProblemID);
        string problemTitle = io:sprintf("%s", event.data.ProblemTitle);
        string impactedEntity = io:sprintf("%s", event.data.ImpactedEntity);
        text = ":fire: received problem `" + problemID + ": " + problemTitle + "`, impacted service is `" + impactedEntity + "`";
    }
    
    return generateNewMessageWithText(event, text);
}

function generateNewMessageWithText(KeptnEvent event, string text) returns json {
    boolean includeAttachment = config:getAsBoolean("INCLUDE_ATTACHMENT", default = false);
    
    json slackMessageJson = {
        text: text
    };

    if (includeAttachment) {
        string eventString = io:sprintf("```%s```", event);
        slackMessageJson["attachments"] = [
            {
                title: "JSON",
                text: eventString
            }
        ];
    }
    
    return slackMessageJson;
}

function handleResponse(http:Response|error response) {
    if (response is http:Response) {
        string|error res = response.getTextPayload();
        if (res is error) {
            io:println(res);
        }
        else {
            log:printInfo(res);
        }
    } else {
        io:println("Error when calling the backend: ", response.reason());
    }
}