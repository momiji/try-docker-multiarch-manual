#FROM amazoncorretto:21.0.0
#FROM alpine:3.18.3
FROM ubuntu:22.04
COPY test.sh /
CMD /test.sh
