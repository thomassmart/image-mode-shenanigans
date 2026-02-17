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
RUN useradd -m -d /var/home/kiosk -s /bin/bash kiosk

# Copy website, quadlet config, and embedded bootc-image-builder defaults
RUN mkdir -p /usr/share/kiosk-site /etc/containers/systemd /usr/lib/bootc-image-builder /etc/sddm.conf.d /etc/xdg/autostart /usr/local/bin /etc/tmpfiles.d
COPY bootc/config.toml /usr/lib/bootc-image-builder/config.toml
COPY index.html /usr/share/kiosk-site/index.html
COPY config-files/kiosk-nginx.container /etc/containers/systemd/kiosk-nginx.container
COPY config-files/sddm-autologin.conf /etc/sddm.conf.d/kiosk-autologin.conf
COPY config-files/kiosk-home.conf /etc/tmpfiles.d/kiosk-home.conf

# Copy kiosk session startup files
COPY config-files/firefox-kiosk.desktop /etc/xdg/autostart/firefox-kiosk.desktop
COPY config-files/kiosk-firefox.sh /usr/local/bin/kiosk-firefox.sh

# Set proper permissions
RUN chmod +x /usr/local/bin/kiosk-firefox.sh

EXPOSE 8080
