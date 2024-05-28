FROM --platform=$TARGETPLATFORM golang:latest AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG GOPRIVATE
ARG GOSUMDB
ARG GOPROXY

ENV GOPRIVATE ${GOPRIVATE}
ENV GOSUMDB ${GOSUMDB}
ENV GOPROXY ${GOPROXY}
ENV CGO_ENABLED 0
ENV GO111MODULE on

RUN go install github.com/yandex-cloud/k8s-csi-s3/...@latest
RUN wget -P /go/bin/geesefs https://github.com/yandex-cloud/geesefs/releases/latest/download/geesefs-$(go env GOOS)-$(go env GOARCH) && chmod +x /go/bin/geesefs

FROM alpine:latest

COPY --from=builder /go/bin/s3driver /bin/
COPY --from=builder /go/bin/geesefs /bin/

ENTRYPOINT ["s3driver"]
