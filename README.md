# slack-service
A keptn service that forwards events on keptn channels to a Slack channel using a webhook URL. To get your Slack Webhook URL please follow the instructions here: https://api.slack.com/incoming-webhooks

# Install service

To install the service in your keptn installation checkout or copy the `slack-service.yaml` and provide your own Slack Webhook URL in this format: 

```
apiVersion: serving.knative.dev/v1alpha1
kind: Service
metadata:
  name: slack-service
  namespace: keptn
spec:
  runLatest:
    configuration:
      revisionTemplate:
        spec:
          container:
            image: keptn/slack-service:0.1.0
            imagePullPolicy: Always
            env:
            - name: SLACK_WEBHOOK_URL
              value: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
            - name: INCLUDE_ATTACHMENT
              value: "true"
...
```

The `INCLUDE_ATTACHMENT` environment variable controls if the payload of the event is attached to the slack message.

- `INCLUDE_ATTACHMENT=true`

  ![Slack Message with attachment](./assets/slackMessageWithAttachment.png)

- `INCLUDE_ATTACHMENT=false`

  ![Slack Message without attachment](./assets/slackMessageWithoutAttachment.png)

Then apply the `service.yaml` using `kubectl` to create the Slack service and the subscriptions to the keptn channels.

```
kubectl apply -f slack-service.yaml
```

Expected output:
```
service.serving.knative.dev/slack-service created
subscription.eventing.knative.dev/slack-subscription-new-artefact created
subscription.eventing.knative.dev/slack-subscription-configuration-changed created
subscription.eventing.knative.dev/slack-subscription-deployment-finished created
subscription.eventing.knative.dev/slack-subscription-tests-finished created
subscription.eventing.knative.dev/slack-subscription-evaluation-done created
subscription.eventing.knative.dev/slack-subscription-keptn created
```

## Verification of installation

```
$ kubectl get ksvc slack-service -n keptn
NAME            DOMAIN                               LATESTCREATED         LATESTREADY           READY     REASON
slack-service   slack-service.keptn.x.x.x.x.xip.io   slack-service-dd9km   slack-service-dd9km   True
$
```

```
$ kubectl get subscription -n keptn | grep slack-subscription
slack-subscription-configuration-changed        True
slack-subscription-deployment-finished          True
slack-subscription-evaluation-done              True
slack-subscription-keptn                        True
slack-subscription-new-artefact                 True
slack-subscription-tests-finished               True
$
```

When the next event is sent to any of the keptn channels you should see a Slack message in the channel you've configured.

# Uninstall service

To uninstall the Slack service and remove the subscriptions to keptn channels execute this command.

```
kubectl delete -f slack-service.yaml
```