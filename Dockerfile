FROM ballerina/ballerina:0.991.0

WORKDIR /
COPY ./MANIFEST /
COPY ./slack-service.bal /

RUN ls -la /

EXPOSE 8080

CMD ["sh", "-c", "cat /MANIFEST && ballerina run slack-service.bal"]
