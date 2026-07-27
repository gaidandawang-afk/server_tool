ARG BASE_IMAGE=lmsysorg/sglang:v0.5.16
FROM ${BASE_IMAGE}

COPY sshd_config /etc/ssh/sshd_config.d/99-server-tool.conf
COPY entrypoint.sh /usr/local/bin/server-tool-sshd-entrypoint

RUN test -x /usr/sbin/sshd \
    && chmod 0755 /usr/local/bin/server-tool-sshd-entrypoint

EXPOSE 22
WORKDIR /workspace

ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]
CMD ["/usr/local/bin/server-tool-sshd-entrypoint"]
