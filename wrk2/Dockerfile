FROM alpine as builder
MAINTAINER Kinvolk

WORKDIR /usr/src
RUN apk add --update alpine-sdk zlib-dev openssl-dev wget
RUN wget https://github.com/kinvolk/wrk2/archive/master.zip && \
    unzip master.zip && \
    cd wrk2-master && \
    make -j && \
    strip wrk

FROM alpine
MAINTAINER Kinvolk

RUN apk add --update --no-cache curl bash\
                        so:libcrypto.so.1.1 so:libssl.so.1.1 so:libgcc_s.so.1

COPY --from=builder /usr/src/wrk2-master/wrk /usr/local/bin/
COPY ./wrk2-wait-until-ready /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/wrk2-wait-until-ready"]
