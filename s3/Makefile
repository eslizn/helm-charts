GOPRIVATE := $(shell go env GOPRIVATE)
GOSUMDB := $(shell go env GOSUMDB)
GOPROXY := $(shell go env GOPROXY)

build:
	docker buildx build --platform linux/amd64,linux/arm64 \
    		--build-arg GOPRIVATE=${GOPRIVATE} \
    		--build-arg GOSUMDB=${GOSUMDB} \
    		--build-arg GOPROXY=${GOPROXY} \
    		-f ./Dockerfile \
    		-t eslizn/csi-s3-provisioner:latest \
    		--push \
    		.
