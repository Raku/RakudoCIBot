# BUILD STAGE #########################
FROM rakudo-zef:2021.03 AS build

RUN mkdir /app

WORKDIR /app

# Copy and install deps first to not trash the podman cache on every source
# change.

# Install build dependencies
RUN apk add --no-cache openssl-dev libxml2-dev

COPY META6.json .
RUN zef install --/test --deps-only .

COPY . .
RUN raku -c -I. service.raku


# Workaround for a recent podman bug, which ignores folders in .dockerignore
# https://github.com/containers/buildah/issues/1582
RUN rm -rf .git .gitignore

# FINAL STAGE #########################
FROM alpine:3.13.4

# Install runtime dependencies
RUN apk add --no-cache openssl-dev libxml2-dev

COPY --from=build /app /app
COPY --from=build /usr/local /usr/local

WORKDIR /app

ENV PATH=$PATH:/usr/local/share/perl6/site/bin

ENV RAKUDOCIBOT_ORG_PORT="10000" \
    RAKUDOCIBOT_ORG_HOST="0.0.0.0"

EXPOSE 10000
CMD raku -I. service.raku
