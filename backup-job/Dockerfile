FROM amazonlinux:2023

RUN dnf install -y mariadb105 tar gzip aws-cli && \
    dnf clean all

WORKDIR /scripts

COPY backup.sh .
COPY restore.sh .
COPY entrypoint.sh .

RUN chmod +x \
    /scripts/backup.sh \
    /scripts/restore.sh \
    /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
