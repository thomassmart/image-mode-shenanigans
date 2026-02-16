# Bootable Fedora base image
FROM quay.io/fedora/fedora-bootc:latest

# Install kiosk runtime packages and GUI group (dnf5 syntax)
RUN dnf -y group install base-x \
    && dnf -y install \
      nginx \
      chromium \
      dbus-x11 \
      curl \
      matchbox-window-manager \
      pciutils \
    && dnf clean all

# Create a dedicated kiosk user
RUN useradd -m -s /bin/bash kiosk

# Copy website content
COPY index.html /usr/share/nginx/html/index.html

# Enable nginx to start on boot
RUN systemctl enable nginx

# Autologin on tty1 for kiosk user (no manual login required)
RUN mkdir -p /etc/systemd/system/getty@tty1.service.d
COPY config-files/autologin.conf /etc/systemd/system/getty@tty1.service.d/autologin.conf

# Copy kiosk user configuration files
COPY config-files/bash_profile /home/kiosk/.bash_profile
COPY config-files/xinitrc /home/kiosk/.xinitrc

# Set proper permissions
RUN chmod +x /home/kiosk/.xinitrc && \
    chown -R kiosk:kiosk /home/kiosk

EXPOSE 80
