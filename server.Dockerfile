FROM vsiri/recipe:tini AS tini
FROM vsiri/recipe:gosu AS gosu
FROM vsiri/recipe:amanda AS amanda

FROM debian:8
LABEL maintainer="Andrew Neff <andrew.neff@visionsystemsinc.com>"

SHELL ["bash", "-euxvc"]

# Install amanda and amanda compatible mailer
COPY --from=amanda /amanda-backup-server*.deb /
RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates mt-st mutt openssh-client gnuplot-nox libjson-perl \
        libencode-locale-perl gettext openssh-server bsd-mailx libcurl3 aespipe; \
    mkdir -p /root/.gnupg/private-keys-v1.d; \
    chmod 700 /root/.gnupg/private-keys-v1.d /root/.gnupg; \
    dpkg -i /amanda-backup-server*.deb || :; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends -f; \
    rm /amanda-backup*.deb; \
    rm /etc/ssh/ssh_host*

# Install gosu
COPY --from=gosu /usr/local/bin/gosu /usr/local/bin/gosu
COPY --from=tini /usr/local/bin/tini /usr/local/bin/tini

# Setup Amanda
ADD htmlmutt /usr/local/bin/
ADD server_entrypoint.bsh /
ADD vsidata /etc/amanda/vsidata
ENV BACKUP_USERNAME=amandabackup \
    BACKUP_GROUP=disk \
    BACKUP_CLIENTS=amanda-client \
    SMTP_SERVER="smtp://smarthost.example.com" \
    FROM_EMAIL="backup@example.com"
RUN chown -R ${BACKUP_USERNAME}:${BACKUP_GROUP} /etc/amanda ;\
    chown ${BACKUP_USERNAME}:${BACKUP_GROUP} /var/lib/amanda/.gnupg/secring.gpg ;\
    chmod 755 /etc/amanda/vsidata; \
    chmod 600 /etc/amanda/vsidata/*; \
    gosu ${BACKUP_USERNAME} mkdir /etc/amanda/template.d; \
    gosu ${BACKUP_USERNAME} cp /var/lib/amanda/template.d/*types /etc/amanda/template.d; \
    chmod 755 /usr/local/bin/htmlmutt; \
    chmod 755 /server_entrypoint.bsh; \
    ln -sf /etc/keys/.am_passphrase /var/lib/amanda/.am_passphrase; \
    ln -sf /etc/amanda/persist/vsidata/am_key.gpg /var/lib/amanda/.gnupg/am_key.gpg; \
    sed -i 's|uuencode -m -|openssl base64|' /usr/sbin/amaespipe

# Customize sshd
RUN sed -i 's|HostKey /etc/ssh|HostKey /etc/keys|' /etc/ssh/sshd_config; \
    echo AuthorizedKeysFile /etc/keys/authorized_keys >> /etc/ssh/sshd_config; \
    echo PasswordAuthentication no >> /etc/ssh/sshd_config; \
    echo StrictHostKeyChecking no >> /etc/ssh/ssh_config; \
    mkdir /var/run/sshd; \
    rm /etc/motd

# Setup timezone
ENV TZ="US/Eastern"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#sshd
EXPOSE 22

# Create internal volumes
VOLUME /etc/amanda

ENTRYPOINT ["/usr/local/bin/tini", "--", "/server_entrypoint.bsh"]

CMD ["sshd"]