# Bootable Fedora base image
FROM quay.io/fedora/fedora-bootc:latest

# Install QEMU guest agent for better integration with the host (optional but recommended)
RUN dnf -y install qemu-guest-agent && \
    dnf clean all && \
    systemctl enable qemu-guest-agent

# Install kiosk runtime packages (Fedora 43+ friendly, no group dependency)
RUN dnf -y install \
      gdm \
      gnome-kiosk \
      gnome-kiosk-script-session \
      podman \
      chromium \
      curl \
    && dnf clean all \
    && systemctl enable gdm \
    && systemctl set-default graphical.target

# Create a dedicated kiosk user
RUN useradd -m -d /var/home/kiosk -s /bin/bash kiosk

# Copy website, quadlet config, and embedded bootc-image-builder defaults
RUN mkdir -p /usr/share/kiosk-site /etc/containers/systemd /usr/lib/bootc-image-builder /etc/gdm /usr/local/bin /etc/tmpfiles.d /etc/dconf/profile /etc/dconf/db/local.d/locks /etc/xdg/autostart /var/lib/AccountsService/users
COPY bootc/config.toml /usr/lib/bootc-image-builder/config.toml
COPY index.html /usr/share/kiosk-site/index.html
COPY config-files/kiosk-nginx.container /etc/containers/systemd/kiosk-nginx.container
COPY config-files/gdm-custom.conf /etc/gdm/custom.conf
COPY config-files/accountsservice-kiosk /var/lib/AccountsService/users/kiosk
COPY config-files/kiosk-home.conf /etc/tmpfiles.d/kiosk-home.conf
COPY config-files/kiosk-script-home-link.conf /etc/tmpfiles.d/kiosk-script-home-link.conf
COPY config-files/dconf-profile-user /etc/dconf/profile/user
COPY config-files/dconf-00-kiosk /etc/dconf/db/local.d/00-kiosk
COPY config-files/dconf-locks-kiosk /etc/dconf/db/local.d/locks/kiosk
COPY config-files/gnome-initial-setup-first-login.desktop /etc/xdg/autostart/gnome-initial-setup-first-login.desktop
COPY config-files/org.gnome.Tour.desktop /etc/xdg/autostart/org.gnome.Tour.desktop
COPY config-files/gnome-keyring-pkcs11.desktop /etc/xdg/autostart/gnome-keyring-pkcs11.desktop
COPY config-files/gnome-keyring-secrets.desktop /etc/xdg/autostart/gnome-keyring-secrets.desktop
COPY config-files/gnome-keyring-ssh.desktop /etc/xdg/autostart/gnome-keyring-ssh.desktop
COPY config-files/gnome-keyring-gpg.desktop /etc/xdg/autostart/gnome-keyring-gpg.desktop

# Copy kiosk session startup files
COPY config-files/kiosk-chromium.sh /usr/local/bin/kiosk-chromium.sh
COPY config-files/gnome-kiosk-script /usr/local/bin/gnome-kiosk-script

# Set proper permissions
RUN chmod +x /usr/local/bin/kiosk-chromium.sh \
    && chmod +x /usr/local/bin/gnome-kiosk-script \
    && if command -v dconf >/dev/null 2>&1; then dconf update; fi

EXPOSE 8080
