# Check to make sure your root
if [[ $EUID -ne 0 ]]; then
  echo -ne "\033[0;31mThis script must be run as root.\e[0m\n"
  exit 1
fi

# Check if running on Ubuntu 22.04 or Debian 12
OS_Check=$(grep -E "22.04|12" "/etc/"*"release")
if ! [[ $OS_Check ]]; then
    echo -ne "\033[0;31mThis script will only work on Ubuntu 22.04 or Debian 12\e[0m\n"
    exit 1
fi

# Enter domain
while [[ $domain != *[.]*[.]* ]]
do
    echo -ne "Enter your Fully Qualified Domain -- example (itflow.domain.com)${NC}: "
    read domain
done

# Generate mariadb password
mariadbpwd=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 20 | head -n 1)

# Generate Cron Key
cronkey=$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w 20 | head -n 1)

# Get the latest OS updates
apt-get update && apt-get -y upgrade

# Install apache2 & mariadb
apt-get install -y apache2
apt-get install -y mariadb-server
mariadb_secure_installation
apt-get install -y php libapache2-mod-php php-intl php-mysqli php-curl php-imap php-mailparse 
apt-get install -y rewrite libapache2-mod-md
apt-get install -y certbot python3-certbot-apache
apt-get install -y git
apt-get install -y sudo
a2enmod md
a2enmod ssl

# Restart apache2
systemctl restart apache2

# Set firewall
# ufw allow OpenSSH
# ufw allow 'Apache Full'
# ufw enable

# Create and set permissions on webroot
mkdir /var/www/${domain}

chown -R www-data:www-data /var/www/

# Set Apache2 config file
apache2="$(cat << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName ${domain}
    DocumentRoot /var/www/${domain}
    ErrorLog /\${APACHE_LOG_DIR}/error.log
    CustomLog /\${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
)"
echo "${apache2}" > /etc/apache2/sites-available/${domain}.conf

a2ensite ${domain}.conf
a2dissite 000-default.conf
systemctl restart apache2

# Run certbot to get Free Lets Encrypt TLS Certificate
certbot --apache --non-interactive --agree-tos --register-unsafely-without-email --domains ${domain}

# Go to webroot
cd /var/www/${domain}

# Clone ITFlow
git clone https://github.com/itflow-org/itflow.git .

# Add Cronjobs
(crontab -l 2>/dev/null; echo "0 2 * * * sudo -u www-data php /var/www/${domain}/cron.php ${cronkey}") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * sudo -u www-data php /var/www/${domain}/cron_ticket_email_parser.php ${cronkey}") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * sudo -u www-data php /var/www/${domain}/cron_mail_queue.php ${cronkey}") | crontab -

# Create temp file with the cronkey that setup will read and use
echo "<?php" > /var/www/${domain}/uploads/tmp/cronkey.php
echo "\$itflow_install_script_generated_cronkey = \"${cronkey}\";" >> /var/www/${domain}/uploads/tmp/cronkey.php
echo "?>" >> /var/www/${domain}/uploads/tmp/cronkey.php

# Set permissions
chown -R www-data:www-data /var/www/

# Create MySQL DB
mysql -e "CREATE DATABASE itflow /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -e "CREATE USER itflow@localhost IDENTIFIED BY '${mariadbpwd}';"
mysql -e "GRANT ALL PRIVILEGES ON itflow.* TO 'itflow'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Print URL/DB/User info for end user to finish the setup process
printf >&2 "Please go to https://${domain} to finish setting up ITFlow"
printf >&2 "\n\n"
printf >&2 "In database setup section enter the following:\n\n"
printf >&2 "Database User: itflow\n"
printf >&2 "Database Name: itflow\n"
printf >&2 "Database Password: ${mariadbpwd} \n\n"
