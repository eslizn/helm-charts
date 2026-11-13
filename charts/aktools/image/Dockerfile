# AKTools. akfamily publishes to PyPI only, so the image is built here.
#
# This is the Dockerfile from the upstream repository with one deliberate
# difference: the dependencies come from requirements.txt, fully pinned, where
# upstream installs them with `--upgrade` and no constraints. That missing
# constraint is what broke the homepage for 0.0.91 - fastapi declares only
# `starlette>=0.46.0`, so pip took starlette 1.x, and 1.x dropped the
# TemplateResponse signature aktools 0.0.91 still called. aktools 0.1.x uses
# the 1.x signature; the pin now exists for reproducibility, not to hold
# starlette back.
#
# Build and push with `make images.aktools` from the repository root (the tag
# is Chart.yaml appVersion); the Build Images workflow runs the same target on
# every push that touches this directory. Any change here still has to bump
# version in Chart.yaml in the same commit - chart-releaser truncates image/...
# back to the chart directory when deciding what changed. See the README.

FROM python:3.14-slim-trixie

# Default to PyPI; override for a network where it is slow or unreachable.
# requirements.txt is fully pinned, so a mirror only has to carry those exact
# versions.
ARG PIP_INDEX_URL=https://pypi.org/simple

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir --index-url "$PIP_INDEX_URL" -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt

# aktools writes aktools_log.log into the working directory, and AKTOOLS_HOST
# tells the MCP endpoint that requests may arrive through a Service/Ingress
# rather than from loopback only. Run from a writable home as a non-root user.
RUN useradd --create-home --uid 1000 aktools
USER aktools
WORKDIR /home/aktools
ENV AKTOOLS_HOST=0.0.0.0

EXPOSE 8080

CMD ["gunicorn", "aktools.main:app", "--bind", "0.0.0.0:8080", "--worker-class", "uvicorn_worker.UvicornWorker"]
