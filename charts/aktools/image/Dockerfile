# AKTools. akfamily publishes to PyPI only, so the image is built here.
#
# This is the Dockerfile from the upstream repository with one deliberate
# difference: the dependencies come from requirements.txt, fully pinned, where
# upstream installs them with `--upgrade` and no constraints. That missing
# constraint is what broke the homepage - fastapi declares only
# `starlette>=0.46.0`, so pip took starlette 1.x, and 1.x dropped the
# TemplateResponse(name, context) signature aktools 0.0.91 still calls.
#
# Build and push with `make images.aktools` from the repository root (the tag
# is Chart.yaml appVersion); the Build Images workflow runs the same target on
# every push that touches this directory. Any change here still has to bump
# version in Chart.yaml in the same commit - chart-releaser truncates image/...
# back to the chart directory when deciding what changed. See the README.

FROM python:3.13-slim-bullseye

# Upstream installs from this mirror; kept configurable so the build still
# works from a network where it is unreachable.
ARG PIP_INDEX_URL=http://mirrors.aliyun.com/pypi/simple/
ARG PIP_TRUSTED_HOST=mirrors.aliyun.com

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r /tmp/requirements.txt \
 && rm /tmp/requirements.txt

ENV APP_HOME=/usr/local/lib/python3.13/site-packages/aktools
WORKDIR $APP_HOME

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app", "-k", "uvicorn.workers.UvicornWorker"]
