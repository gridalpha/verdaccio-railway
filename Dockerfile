# Verdaccio on Railway — a private npm proxy registry.
#
# One derived layer on top of the published image. Everything below exists because
# a Railway deployment differs from `docker run` in three ways: the volume arrives
# root-owned, the registry config is a file rather than a set of env vars, and the
# first account has to exist before anyone can log in.
FROM verdaccio/verdaccio:6

USER root

# htpasswd (apache2-utils) seeds the operator account with a bcrypt hash; su-exec
# drops back to the image's own unprivileged uid after the volume is prepared.
RUN apk add --no-cache apache2-utils su-exec

COPY config.template.yaml /verdaccio/conf/config.template.yaml
COPY entrypoint.sh /tmp/uid_entrypoint

# The image's ENTRYPOINT is ["uid_entrypoint"], resolved from $VERDACCIO_APPDIR/docker-bin
# on PATH. Shim that name rather than declaring an ENTRYPOINT of our own, which would
# empty the inherited CMD and force us to restate a start line that then rots against
# the floating tag.
RUN mv "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint" "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint.real" \
    && mv /tmp/uid_entrypoint "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint" \
    && chmod 0755 "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint" "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint.real" \
    && sh -n "$VERDACCIO_APPDIR/docker-bin/uid_entrypoint" \
    && su-exec 10001:0 true

# Railway runs the container as the image's USER; stay root so the entrypoint can
# chown the mounted volume, then drop to 10001 itself.
USER root
