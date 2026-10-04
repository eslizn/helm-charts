# Generic image build entry point.
#
# A chart whose image is built here keeps its build context in
# charts/<chart>/image/ and is built with:
#
#   make images.<chart>             # tag from values.yaml image.tag
#   make images.<chart> TAG=<tag>   # override the tag
#
# The tag is resolved in this order: TAG=<tag>, then the chart's values.yaml
# image.tag, then Chart.yaml appVersion. values.yaml wins over appVersion
# because that is what the chart renders - common.imageRef prefers image.tag
# and falls back to appVersion - so the pushed image and the deployed
# reference are the same string. Both platform variants are built because the
# cluster is amd64 + arm64 mixed.
#
# A self-built image is tagged <appVersion>-<rev> (for example 0.0.91-1) and
# image.tag is bumped in the same commit as any change under image/. The tag
# therefore changes whenever the image does, which is what makes the rollout
# happen: tags are never overwritten in place, so no node image cache has to
# be cleared by hand. The Build Images workflow runs this same target in CI
# (see the README).

SHELL := bash

REPO      ?= docker.io/eslizn
TAG       ?=
PLATFORMS ?= linux/amd64,linux/arm64

# FORCE keeps the pattern rule from being shadowed: without a prerequisite, a
# file or directory that happens to be named images.<chart> makes this target
# look up to date, and make exits 0 having built nothing.
.PHONY: FORCE
images.%: FORCE
	@set -euo pipefail; \
	chart="charts/$*"; \
	context="$$chart/image"; \
	if [ ! -f "$$context/Dockerfile" ]; then \
		echo "no build context: $$context/Dockerfile" >&2; exit 1; \
	fi; \
	tag='$(TAG)'; \
	if [ -z "$$tag" ]; then \
		tag="$$(awk '/^image:/{in_image=1;next} in_image&&/^[^[:space:]#]/{in_image=0} in_image&&sub(/^[[:space:]]+tag:[[:space:]]*/,""){sub(/[[:space:]]*#.*/,"");gsub(/"/,"");print;exit}' "$$chart/values.yaml")"; \
	fi; \
	if [ -z "$$tag" ]; then \
		tag="$$(sed -n 's/^appVersion:[[:space:]]*//p' "$$chart/Chart.yaml" | tr -d '"')"; \
	fi; \
	if [ -z "$$tag" ]; then \
		echo "no tag: pass TAG=<tag>, or set image.tag in $$chart/values.yaml or appVersion in $$chart/Chart.yaml" >&2; exit 1; \
	fi; \
	echo "==> $$context -> $(REPO)/$*:$$tag [$(PLATFORMS)]"; \
	docker buildx build \
		--platform '$(PLATFORMS)' \
		-f "$$context/Dockerfile" \
		-t "$(REPO)/$*:$$tag" \
		--push \
		"$$context"
