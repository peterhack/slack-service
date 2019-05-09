import ballerina/http;
import ballerina/log;
import ballerina/io;
import ballerinax/docker;
import ballerina/config;

type KeptnData record {
    string githuborg?;
    string project;
    string teststrategy?;
    string deploymentstrategy?;
    string stage?;
    string ^"service";
    string image;
    string tag;
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
            KeptnEvent|error event = KeptnEvent.convert(payload);

            if (event is error) {
                log:printError("error converting JSON payload to keptn event", err = event);
            }
            else {
                json slackMessageJson = {};

                match event.^"type" {
                    "sh.keptn.events.new-artefact" => slackMessageJson = generateNewArtefactMessage(event);
                    "sh.keptn.events.configuration-changed" => slackMessageJson = generateConfigurationChangedMessage(event);
                    "sh.keptn.events.deployment-finished" => slackMessageJson = generateDeploymentFinishedMessage(event);
                    "sh.keptn.events.tests-finished" => slackMessageJson = generateTestsFinishedMessage(event);
                    "sh.keptn.events.evaluation-done" => slackMessageJson = generateEvaluationDoneMessage(event);
                    _ => slackMessageJson = generateUnknownEventTypeMessage(event);
                }

                http:Request req = new;
                req.setJsonPayload(slackMessageJson);

                var response = slackEndpoint->post(getSlackWebhookUrlPath(), req);
                _ = handleResponse(response);
            }
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

function generateUnknownEventTypeMessage(KeptnEvent event) returns @untainted json {
    string text = "unknown event type `" + event.^"type" + "`, don't know what to do (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateNewArtefactMessage(KeptnEvent event) returns @untainted json {
    string text = ":inbox_tray: new artefact `" + event.data.image + ":" + event.data.tag + "` in project `" + event.data.project + "` for service `" + event.data.^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateConfigurationChangedMessage(KeptnEvent event) returns @untainted json {
    string text = ":file_folder: configuration changed in project `" + event.data.project + "` for service `" + event.data.^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateDeploymentFinishedMessage(KeptnEvent event) returns @untainted json {
    string text = ":building_construction: deployment finished in project `" + event.data.project + "` for service `" + event.data.^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateTestsFinishedMessage(KeptnEvent event) returns @untainted json {
    string text = ":sports_medal: tests finished in project `" + event.data.project + "` for service `" + event.data.^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
    return generateNewMessageWithText(event, text);
}

function generateEvaluationDoneMessage(KeptnEvent event) returns @untainted json {
    string text = ":checkered_flag: evaluation done in project `" + event.data.project + "` for service `" + event.data.^"service" + "` (shkeptncontext: " + event.shkeptncontext + ")";
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