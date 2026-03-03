# Bootable Fedora base image
FROM quay.io/fedora/fedora-bootc:latest

# Install kiosk runtime packages (Fedora 43+ friendly, no group dependency)
RUN dnf -y install \
      dnf-plugins-core \
      gdm \
      gnome-kiosk \
      gnome-kiosk-script-session \
      podman \
      chromium \
      curl \
      python3 \
      python3-libs \
      systemd-libs \
      systemd-udev \
      cups \
      cups-client \
      usbutils \
    && dnf config-manager addrepo --from-repofile=https://rpm.flightctl.io/flightctl-epel.repo \
    && dnf -y install flightctl-agent \
    && dnf clean all \
    && systemctl enable gdm \
    && systemctl set-default graphical.target

# Create a dedicated kiosk user
RUN useradd -m -d /var/home/kiosk -s /bin/bash kiosk

# Copy website, quadlet config, and embedded bootc-image-builder defaults
RUN mkdir -p /usr/share/kiosk-site /etc/containers/systemd /usr/lib/bootc-image-builder /etc/gdm /usr/local/bin /etc/tmpfiles.d /etc/dconf/profile /etc/dconf/db/local.d/locks /etc/xdg/autostart /var/lib/AccountsService/users /etc/systemd/system /etc/systemd/system/flightctl-agent.service.d /etc/flightctl /etc/kiosk-pos.conf.d /var/lib/kiosk-pos /usr/local/share/zebra
COPY bootc/config.toml /usr/lib/bootc-image-builder/config.toml
COPY config-files/kiosk-nginx.container /etc/containers/systemd/kiosk-nginx.container
COPY config-files/environment /etc/environment
COPY config-files/flightctl/config.yaml /etc/flightctl/config.yaml
COPY config-files/flightctl/10-config-path.conf /etc/systemd/system/flightctl-agent.service.d/10-config-path.conf
COPY config-files/gdm-custom.conf /etc/gdm/custom.conf
COPY config-files/accountsservice-kiosk /var/lib/AccountsService/users/kiosk
COPY config-files/kiosk-home.conf config-files/kiosk-script-home-link.conf /etc/tmpfiles.d/
COPY config-files/dconf-profile-user /etc/dconf/profile/user
COPY config-files/dconf-00-kiosk /etc/dconf/db/local.d/00-kiosk
COPY config-files/dconf-locks-kiosk /etc/dconf/db/local.d/locks/kiosk
COPY config-files/*.desktop /etc/xdg/autostart/

# Copy kiosk session startup files
COPY config-files/kiosk-chromium.sh config-files/gnome-kiosk-script config-files/kiosk-install-zebra.sh config-files/kiosk-pos-agent.py /usr/local/bin/
COPY config-files/kiosk-pos-agent.service /etc/systemd/system/kiosk-pos-agent.service
COPY config-files/kiosk-zebra.conf config-files/kiosk-pos.conf /etc/
COPY Zebra/ /usr/local/share/zebra/

# Set proper permissions
RUN chmod +x /usr/local/bin/kiosk-chromium.sh \
    && chmod +x /usr/local/bin/kiosk-install-zebra.sh \
    && chmod +x /usr/local/bin/kiosk-pos-agent.py \
    && chmod +x /usr/local/bin/gnome-kiosk-script \
    && chmod 600 /etc/flightctl/config.yaml \
    && if [ ! -e /usr/lib64/libudev.so.0 ] && [ -e /usr/lib64/libudev.so.1 ]; then ln -s /usr/lib64/libudev.so.1 /usr/lib64/libudev.so.0; fi \
    && BUILD_TIME=1 /usr/local/bin/kiosk-install-zebra.sh \
    && (systemctl enable cscored.service || systemctl enable cscore.service || systemctl enable corescanner.service || true) \
    && systemctl enable kiosk-pos-agent.service \
    && systemctl enable flightctl-agent.service \
    && if command -v dconf >/dev/null 2>&1; then dconf update; fi

# Copy Index.html
COPY index.html /usr/share/kiosk-site/index.html
COPY screensaver.mp4 /usr/share/kiosk-site/screensaver.mp4
