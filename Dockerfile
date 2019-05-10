FROM ballerina/ballerina-runtime:0.991.0

COPY ./MANIFEST /
COPY ./slack-service.balx /home/ballerina

RUN ls -la /

EXPOSE 8080

CMD ["sh", "-c", "cat /MANIFEST && ballerina run slack-service.balx"]
