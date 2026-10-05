# Generic image build entry point.
#
# A chart whose image is built here keeps its build context in
# charts/<chart>/image/ and is built with:
#
#   make images.<chart>             # tag defaults to the chart's appVersion
#   make images.<chart> TAG=<tag>   # override the tag
#
# The tag has to match the chart's Chart.yaml appVersion: image.tag is empty in
# values.yaml and common.imageRef falls back to appVersion, so the two cannot
# drift. Both platform variants are built because the cluster is amd64 + arm64
# mixed.
#
# Pushing over an existing tag does not roll anything: the deployed manifest
# does not change, so Argo CD sees no diff, and a node that already cached the
# old image under that tag will not pull again under IfNotPresent. Clear the
# node's image cache by hand after such a push (see the README).
#
# The Build Images workflow runs this same target in CI; see the README.

SHELL := bash

REPO      ?= docker.io/eslizn
TAG       ?=
PLATFORMS ?= linux/amd64,linux/arm64

# Per-chart platform override, for a chart whose upstream artifact only exists
# for one architecture. futuopend is the case: Futu publishes the OpenD binary
# for x86-64 only (there is no arm download at all), so a linux/arm64 variant
# would be an amd64 binary wearing an arm64 label - it would pull and then die
# with "exec format error" on an arm64 node, which is worse than not existing.
# Everything else follows the PLATFORMS default above.
PLATFORMS.futuopend := linux/amd64

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
		tag="$$(sed -n 's/^appVersion:[[:space:]]*//p' "$$chart/Chart.yaml" | tr -d '"')"; \
	fi; \
	if [ -z "$$tag" ]; then \
		echo "no tag: pass TAG=<tag>, or set appVersion in $$chart/Chart.yaml" >&2; exit 1; \
	fi; \
	echo "==> $$context -> $(REPO)/$*:$$tag [$(or $(PLATFORMS.$*),$(PLATFORMS))]"; \
	docker buildx build \
		--platform '$(or $(PLATFORMS.$*),$(PLATFORMS))' \
		-f "$$context/Dockerfile" \
		-t "$(REPO)/$*:$$tag" \
		--push \
		"$$context"
