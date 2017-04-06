#!/usr/bin/bash

$DOMAIN=test.example.com

# Check to ensure the script is run as root/sudo
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root. Later hater." 1>&2
	exit 1 
fi

curl -sL https://deb.nodesource.com/setup_4.x | sudo bash -
apt install ack-grep build-essential ffmpeg git imagemagick libpq-dev libxml2-dev libxslt1-dev nginx postgresql postgresql-contrib redis-server redis-tools ruby2.3 ruby2.3-dev
npm install -g npm yarn json json-diff

su - postgres
psql

CREATE USER mastodon CREATEDB;
\q

rbenv install 2.3.1

cd ~
git clone https://github.com/tootsuite/mastodon.git live
cd live

gem install bundler
bundle install --deployment --without development test
yarn install

cp .env.production.sample .env.production

sed "s@LOCAL_DOMAIN=example.com@LOCAL_DOMAIN=$DOMAIN@g" -i .env.production
sed "s@PAPERCLIP_SECRET=@PAPERCLIP_SECRET=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32; echo)@g" -i .env.production
sed "s@SECRET_KEY_BASE=@SECRET_KEY_BASE=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32; echo)@g" -i .env.production
sed "s@OTP_SECRET=@OTP_SECRET=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32; echo)@g" -i .env.production

RAILS_ENV=production bundle exec rails db:setup
RAILS_ENV=production bundle exec rails assets:precompile

cat << 'EOF' > /etc/systemd/system/mastodon-web.service
[Unit]
Description=mastodon-web
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment="RAILS_ENV=production"
Environment="PORT=3000"
ExecStart=/home/mastodon/.rbenv/shims/bundle exec puma -C config/puma.rb
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/mastodon-sidekiq.service
[Unit]
Description=mastodon-sidekiq
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment="RAILS_ENV=production"
Environment="DB_POOL=5"
ExecStart=/home/mastodon/.rbenv/shims/bundle exec sidekiq -c 5 -q default -q mailers -q pull -q push
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/mastodon-streaming.service
[Unit]
Description=mastodon-streaming
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment="NODE_ENV=production"
Environment="PORT=4000"
ExecStart=/usr/bin/npm run start
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable mastodon-*.service
systemctl restart mastodon-*.service
