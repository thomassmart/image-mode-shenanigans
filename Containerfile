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
    && systemctl enable sddm \
    && systemctl set-default graphical.target

# Create a dedicated kiosk user
RUN useradd -m -s /bin/bash kiosk

# Copy website, quadlet config, and embedded bootc-image-builder defaults
RUN mkdir -p /usr/share/kiosk-site /etc/containers/systemd /usr/lib/bootc-image-builder /etc/sddm.conf.d /home/kiosk/.config/autostart /home/kiosk/.local/bin
COPY bootc/config.toml /usr/lib/bootc-image-builder/config.toml
COPY index.html /usr/share/kiosk-site/index.html
COPY config-files/kiosk-nginx.container /etc/containers/systemd/kiosk-nginx.container
COPY config-files/sddm-autologin.conf /etc/sddm.conf.d/kiosk-autologin.conf

# Copy kiosk session startup files
COPY config-files/firefox-kiosk.desktop /home/kiosk/.config/autostart/firefox-kiosk.desktop
COPY config-files/kiosk-firefox.sh /home/kiosk/.local/bin/kiosk-firefox.sh

# Set proper permissions
RUN chmod +x /home/kiosk/.local/bin/kiosk-firefox.sh && \
    chown -R kiosk:kiosk /home/kiosk

EXPOSE 8080
