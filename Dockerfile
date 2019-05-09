FROM ballerina/ballerina:0.990.3

COPY ./MANIFEST /
COPY ./slack-service.bal /

EXPOSE 8080

CMD ["sh", "-c", "cat MANIFEST && ballerina run slack-service.bal"]
