# Bootable Fedora base image
FROM quay.io/fedora/fedora-bootc:latest

# Install QEMU guest agent for better integration with the host (optional but recommended)
RUN dnf -y install qemu-guest-agent && \
    dnf clean all && \
    systemctl enable qemu-guest-agent

# Install kiosk runtime packages and KDE desktop (dnf5 syntax)
RUN dnf -y install @kde-desktop-environment \
    && dnf -y install \
      podman \
      firefox \
      dbus-x11 \
      curl \
    && dnf clean all \
    && systemctl set-default graphical.target

# Create a dedicated kiosk user
RUN useradd -m -s /bin/bash kiosk

# Copy website and quadlet config for podman-managed container
RUN mkdir -p /usr/share/kiosk-site /etc/containers/systemd
COPY index.html /usr/share/kiosk-site/index.html
COPY config-files/kiosk-nginx.container /etc/containers/systemd/kiosk-nginx.container

# Autologin on tty1 for kiosk user (no manual login required)
RUN mkdir -p /etc/systemd/system/getty@tty1.service.d
COPY config-files/autologin.conf /etc/systemd/system/getty@tty1.service.d/autologin.conf

# Copy kiosk user configuration files
COPY config-files/bash_profile /home/kiosk/.bash_profile
COPY config-files/xinitrc /home/kiosk/.xinitrc

# Set proper permissions
RUN chmod +x /home/kiosk/.xinitrc && \
    chown -R kiosk:kiosk /home/kiosk

EXPOSE 8080
