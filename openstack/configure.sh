#!/bin/sh

_step_counter=0
step() {
    _step_counter=$(( _step_counter + 1 ))
    printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}

step 'Set up timezone'
setup-timezone -z America/Los_Angeles

step 'Set up keymap'
setup-keymap us us

step 'Set up networking'
cat > /etc/network/interfaces <<-EOF
    auto lo
    iface lo inet loopback

    auto eth0
    iface eth0 inet dhcp
        udhcpc_opts -i eth0 -p /var/run/udhcpc.eth0.pid -R -b -O 121
EOF


# FIXME: remove root and alpine password
step 'Set cloud configuration'
sed -e '/disable_root:/ s/true/false/' \
    -e '/name: alpine/a \     passwd: "*"' \
 	-e '/ssh_pwauth:/ s/0/no/' \
    -e '/lock_passwd:/ s/True/False/' \
    -e '/shell:/ s#/bin/ash#/bin/zsh#' \
    -i /etc/cloud/cloud.cfg

step 'Echo cloud config'
cat /etc/cloud/cloud.cfg

# To have oh-my-zsh working on first boot
cat >> /etc/cloud/cloud.cfg <<EOF
runcmd:
    - su alpine -l -c 'cp -f /usr/share/oh-my-zsh/templates/zshrc.zsh-template /home/alpine/.zshrc'
EOF

step 'Allow only key based ssh login'
sed -e '/PermitRootLogin yes/d' \
    -e 's/^#PasswordAuthentication yes/PasswordAuthentication no/' \
    -e 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' \
    -i /etc/ssh/sshd_config

# Terraform and github actions need ssh-rsa as accepted algorithm
# The ssh client needs to be updated (see https://www.openssh.com/txt/release-8.8)

echo "PubkeyAcceptedKeyTypes=+ssh-rsa" >> /etc/ssh/sshd_config

step 'Remove password for users'
usermod -p '*' root

step 'Add user'
useradd -m -s /bin/zsh -G wheel dan

step 'Adjust rc.conf'
sed -Ei \
    -e 's/^[# ](rc_depend_strict)=.*/\1=NO/' \
    -e 's/^[# ](rc_logger)=.*/\1=YES/' \
    -e 's/^[# ](unicode)=.*/\1=YES/' \
    /etc/rc.conf

step 'Enabling zsh'
cp -f /usr/share/oh-my-zsh/templates/zshrc.zsh-template /root/.zshrc
chmod +x /root/.zshrc
sed -ie '/^root:/ s#:/bin/.*$#:/bin/zsh#' /etc/passwd

step 'Enable services'
rc-update add acpid default
rc-update add chronyd default
rc-update add crond default
rc-update add networking boot
rc-update add staticroute boot
rc-update add termencoding boot
rc-update add sshd default
rc-update add cloud-init default
rc-update add cloud-config default
rc-update add cloud-final default
