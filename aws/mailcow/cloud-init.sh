#!/bin/bash
set -Eeuo pipefail
exec > >(tee -a /var/log/norcom-mail-bootstrap.log | logger -t norcom-mail-bootstrap -s 2>/dev/console) 2>&1

MAIL_DOMAIN="${mail_domain}"
MAIL_HOST="${mail_hostname}"
CONTACT_EMAIL="${contact_email}"
export DEBIAN_FRONTEND=noninteractive

echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string $MAIL_DOMAIN" | debconf-set-selections
echo "roundcube-core roundcube/dbconfig-install boolean false" | debconf-set-selections

apt-get update
apt-get install -y --no-install-recommends \
  postfix dovecot-imapd apache2 libapache2-mod-php \
  roundcube-core roundcube-sqlite3 \
  php-sqlite3 sqlite3 php-intl php-mbstring php-xml php-curl php-zip php-gd \
  certbot python3-certbot-apache ssl-cert fail2ban openssl

# Defense in depth: expose only the webmail and ACME ports at the host.
# AWS security groups separately restrict ingress and egress to TCP 80/443.
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose

fallocate -l 1G /swapfile || true
chmod 600 /swapfile
mkswap /swapfile || true
swapon /swapfile || true
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

postconf -e "myhostname = $MAIL_HOST"
postconf -e "mydomain = $MAIL_DOMAIN"
postconf -e 'myorigin = $mydomain'
postconf -e 'mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain'
postconf -e 'home_mailbox = Maildir/'
postconf -e 'inet_interfaces = all'
postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination'
postconf -e 'smtpd_sasl_type = dovecot'
postconf -e 'smtpd_sasl_path = private/auth'
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_security_options = noanonymous'
postconf -e 'smtpd_tls_security_level = may'
postconf -e 'smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem'
postconf -e 'smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key'
postconf -e 'smtpd_tls_auth_only = yes'
postconf -e 'smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination'
postconf -e 'smtpd_client_restrictions = permit_mynetworks, permit_sasl_authenticated, reject'

sed -ri 's/^#?disable_plaintext_auth =.*/disable_plaintext_auth = yes/' /etc/dovecot/conf.d/10-auth.conf
sed -ri 's/^#?auth_mechanisms =.*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf
sed -ri 's|^#?mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
cat > /etc/dovecot/conf.d/99-norcom-mail-tls.conf <<EOF
ssl = required
ssl_cert = </etc/ssl/certs/ssl-cert-snakeoil.pem
ssl_key = </etc/ssl/private/ssl-cert-snakeoil.key
EOF

python3 - <<'PY'
from pathlib import Path
path = Path('/etc/dovecot/conf.d/10-master.conf')
text = path.read_text()
lines = text.splitlines()
start = next((i for i, line in enumerate(lines)
              if line.strip() == '#unix_listener /var/spool/postfix/private/auth {'), None)
if start is not None:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() == '#}'), None)
    if end is None:
        raise SystemExit('Commented Postfix auth socket block is incomplete')
    for i in range(start, end + 1):
        lines[i] = lines[i].replace('#', '', 1)
else:
    active = any(line.strip() == 'unix_listener /var/spool/postfix/private/auth {' for line in lines)
    if not active:
        try:
            service = next(i for i, line in enumerate(lines) if line.strip() == 'service auth {')
        except StopIteration:
            raise SystemExit('Dovecot auth service block not found')
        lines[service + 1:service + 1] = [
            '  unix_listener /var/spool/postfix/private/auth {',
            '    mode = 0660',
            '    user = postfix',
            '    group = postfix',
            '  }',
        ]
path.write_text('\n'.join(lines) + '\n')

master = Path('/etc/postfix/master.cf')
lines = master.read_text().splitlines()
start = next((i for i, line in enumerate(lines) if line.startswith('#submission inet ')), None)
if start is not None:
    end = next((i for i in range(start, len(lines))
                if 'milter_macro_daemon_name=ORIGINATING' in lines[i]), start)
    del lines[start:end + 1]
lines = [line for line in lines if not line.startswith('submission inet ')]
lines.extend([
    '',
    'submission inet n - y - - smtpd',
    '  -o syslog_name=postfix/submission',
    '  -o smtpd_tls_security_level=encrypt',
    '  -o smtpd_sasl_auth_enable=yes',
    '  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject',
    '  -o milter_macro_daemon_name=ORIGINATING',
])
master.write_text('\n'.join(lines) + '\n')
PY

for USER in norcom-admin norcom-trabajador; do
  PASSWORD="$(openssl rand -hex 18)"
  useradd --create-home --shell /bin/bash "$USER"
  printf '%s:%s\n' "$USER" "$PASSWORD" | chpasswd
  install -d -m 700 -o "$USER" -g "$USER" "/home/$USER/Maildir"
  install -d -m 700 -o "$USER" -g "$USER" "/home/$USER/Maildir/cur" "/home/$USER/Maildir/new" "/home/$USER/Maildir/tmp"
  printf '%s@%s %s\n' "$USER" "$MAIL_DOMAIN" "$PASSWORD" >> /root/norcom-mail-demo-credentials.txt
  unset PASSWORD
done
chmod 600 /root/norcom-mail-demo-credentials.txt

if [ -f /etc/roundcube/config.inc.php ]; then
  sed -ri "s|^\$config\['imap_host'\].*|\$config['imap_host'] = ['ssl://127.0.0.1:993'];|" /etc/roundcube/config.inc.php
  python3 - <<'PY'
from pathlib import Path
import re
path = Path('/etc/roundcube/config.inc.php')
text = path.read_text()
text, count = re.subn(r"(?m)^\s*\$config\['smtp_host'\].*$",
                     "$config['smtp_host'] = 'tls://127.0.0.1:587';", text, count=1)
if count == 0:
    text += "\n$config['smtp_host'] = 'tls://127.0.0.1:587';\n"
path.write_text(text)
PY
  cat >> /etc/roundcube/config.inc.php <<'PHP'
$config['db_dsnw'] = 'sqlite:////var/lib/roundcube/db/roundcube.sqlite?mode=0640';
$config['imap_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false]];
$config['smtp_conn_options'] = ['ssl' => ['verify_peer' => false, 'verify_peer_name' => false]];
$config['product_name'] = 'NORCOM Webmail Demo';
PHP
fi
install -d -m 750 -o www-data -g www-data /var/lib/roundcube/db
if [ ! -f /var/lib/roundcube/db/roundcube.sqlite ]; then
  sqlite3 /var/lib/roundcube/db/roundcube.sqlite < /usr/share/roundcube/SQL/sqlite.initial.sql
fi
chown www-data:www-data /var/lib/roundcube/db/roundcube.sqlite
chmod 640 /var/lib/roundcube/db/roundcube.sqlite

if [ -f /etc/apache2/conf-available/roundcube.conf ]; then
  sed -ri 's|^#([[:space:]]*Alias /roundcube )|\1|' /etc/roundcube/apache.conf
  a2enconf roundcube
fi
a2enmod ssl rewrite headers
a2ensite default-ssl
cat > /etc/apache2/conf-available/norcom-mail-https.conf <<'EOF'
<VirtualHost *:80>
  RewriteEngine On
  RewriteCond %%{REQUEST_URI} !^/\.well-known/acme-challenge/
  RewriteRule ^ https://%%{HTTP_HOST}%%{REQUEST_URI} [R=301,L]
</VirtualHost>
EOF
a2enconf norcom-mail-https
python3 - <<PY
from pathlib import Path
for name in ('000-default.conf', 'default-ssl.conf'):
    path = Path('/etc/apache2/sites-available') / name
    if not path.exists():
        continue
    text = path.read_text()
    if 'ServerName $MAIL_HOST' in text:
        continue
    for marker in ('<VirtualHost *:80>', '<VirtualHost _default_:443>'):
        if marker in text:
            text = text.replace(marker, marker + '\n  ServerName $MAIL_HOST', 1)
            break
    path.write_text(text)
PY

cat > /usr/local/sbin/norcom-enable-mail-tls <<'EOF'
#!/bin/bash
set -euo pipefail
MAIL_HOST='${mail_hostname}'
CONTACT_EMAIL='${contact_email}'
MARKER=/etc/norcom-mail-tls-enabled
[ -e "$MARKER" ] && exit 0
getent ahostsv4 "$MAIL_HOST" >/dev/null || exit 0
certbot --apache --non-interactive --agree-tos --keep-until-expiring \
  --email "$CONTACT_EMAIL" -d "$MAIL_HOST"
postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$MAIL_HOST/fullchain.pem"
postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$MAIL_HOST/privkey.pem"
cat > /etc/dovecot/conf.d/99-norcom-mail-tls.conf <<CONF
ssl = required
ssl_cert = </etc/letsencrypt/live/$MAIL_HOST/fullchain.pem
ssl_key = </etc/letsencrypt/live/$MAIL_HOST/privkey.pem
CONF
systemctl restart dovecot postfix
touch "$MARKER"
EOF
chmod 750 /usr/local/sbin/norcom-enable-mail-tls
cat > /etc/systemd/system/norcom-mail-tls.service <<'EOF'
[Unit]
Description=Obtain and configure the NORCOM demo mail TLS certificate
After=network-online.target apache2.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/norcom-enable-mail-tls
EOF
cat > /etc/systemd/system/norcom-mail-tls.timer <<'EOF'
[Unit]
Description=Retry public TLS setup until mail DNS is ready

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=norcom-mail-tls.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now norcom-mail-tls.timer

install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-norcom-mail <<'EOF'
#!/bin/sh
systemctl reload-or-restart apache2 postfix dovecot
EOF
chmod 750 /etc/letsencrypt/renewal-hooks/deploy/reload-norcom-mail

postfix check
doveconf -n >/dev/null
apachectl configtest
systemctl enable --now postfix dovecot apache2 fail2ban
systemctl restart postfix dovecot apache2
touch /var/lib/cloud/instance/norcom-mail-bootstrap-complete
