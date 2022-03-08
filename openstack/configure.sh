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
EOF

step 'Configure dhclient'
cat > /etc/dhcp/dhclient.conf <<-EOF
option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;

send host-name = gethostname();

# prepend domain-name-servers 127.0.0.1;
request subnet-mask, broadcast-address, time-offset, routers,
    domain-name, domain-name-servers, domain-search, host-name,
    dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,
    netbios-name-servers, netbios-scope, interface-mtu,
    rfc3442-classless-static-routes, ntp-servers;
# require subnet-mask, domain-name-servers;
timeout 300;
EOF

cat > /etc/dhcp/dhclient-exit-hooks.d/rfc3442-classless-routes <<-EOF
#!/bin/sh
# set classless routes based on the format specified in RFC3442
# e.g.:
#   new_rfc3442_classless_static_routes='24 192 168 10 192 168 1 1 8 10 10 17 66 41'
# specifies the routes:
#   192.168.10.0/24 via 192.168.1.1
#   10.0.0.0/8 via 10.10.17.66.41

RUN="yes"

if [ "$RUN" = "yes" ]; then
    if [ -n "$new_rfc3442_classless_static_routes" ]; then
        if [ "$reason" = "BOUND" ] || [ "$reason" = "REBOOT" ]; then

            set -- $new_rfc3442_classless_static_routes

            while [ $# -gt 0 ]; do
                net_length=$1
                via_arg=''

                case $net_length in
                    32|31|30|29|28|27|26|25)
                        if [ $# -lt 9 ]; then
                            return 1
                        fi
                        net_address="${2}.${3}.${4}.${5}"
                        gateway="${6}.${7}.${8}.${9}"
                        shift 9
                        ;;
                    24|23|22|21|20|19|18|17)
                        if [ $# -lt 8 ]; then
                            return 1
                        fi
                        net_address="${2}.${3}.${4}.0"
                        gateway="${5}.${6}.${7}.${8}"
                        shift 8
                        ;;
                    16|15|14|13|12|11|10|9)
                        if [ $# -lt 7 ]; then
                            return 1
                        fi
                        net_address="${2}.${3}.0.0"
                        gateway="${4}.${5}.${6}.${7}"
                        shift 7
                        ;;
                    8|7|6|5|4|3|2|1)
                        if [ $# -lt 6 ]; then
                            return 1
                        fi
                        net_address="${2}.0.0.0"
                        gateway="${3}.${4}.${5}.${6}"
                        shift 6
                        ;;
                    0)	# default route
                        if [ $# -lt 5 ]; then
                            return 1
                        fi
                        net_address="0.0.0.0"
                        gateway="${2}.${3}.${4}.${5}"
                        shift 5
                        ;;
                    *)	# error
                        return 1
                        ;;
                esac

                # take care of link-local routes
                if [ "${gateway}" != '0.0.0.0' ]; then
                    via_arg="via ${gateway}"
                fi

                # set route (ip detects host routes automatically)
                ip -4 route add "${net_address}/${net_length}" \
                    ${via_arg} dev "${interface}" >/dev/null 2>&1
            done
        fi
    fi
fi
EOF
chmod +x /etc/dhcp/dhclient-exit-hooks.d/rfc3442-classless-routes

# FIXME: remove root and alpine password
step 'Set cloud configuration'
sed -e '/disable_root:/ s/true/false/' \
    -e '/name: alpine/a \     passwd: "*"' \
    -e '/lock_passwd:/ s/True/False/' \
    -e '/shell:/ s#/bin/ash#/bin/zsh#' \
    -i /etc/cloud/cloud.cfg
# 	-e '/ssh_pwauth:/ s/0/no/' \

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

# step 'Remove password for users'
# usermod -p '*' root

# step 'Add user'
# useradd -m -s /bin/zsh -G wheel dan

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
rc-update add termencoding boot
rc-update add sshd default
rc-update add cloud-init default
rc-update add cloud-config default
rc-update add cloud-final default
