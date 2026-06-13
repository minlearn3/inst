###############

silent() { "$@" >/dev/null 2>&1 || { echo "Error running: $*"; echo "sth error"; exit 1; }; }


debmirror=${1:-http://deb.debian.org/debian}
echo -e "deb ${debmirror} bullseye main\ndeb ${debmirror} bullseye-updates main\ndeb ${debmirror}-security bullseye-security main" > /etc/apt/sources.list

echo "Installing Dependencies"
silent apt-get update -y
silent apt-get install -y curl sudo mc gnupg2 procps
echo "Installed Dependencies"

silent apt-get install -y postgresql-client nginx redis
silent apt-get install -y git build-essential autoconf bison libpq-dev libssl-dev libyaml-dev \
  libreadline-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libgmp-dev \
  libdb-dev libsqlite3-dev sqlite3

curl -sL https://deb.nodesource.com/setup_16.x | bash -
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
silent apt-get update -y
silent apt-get install nodejs yarn -y
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
gpg2 --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
curl -sSL https://get.rvm.io | bash -s stable
# source using in this script dont actually apply env to current session, need reboot
[ -f /etc/profile.d/rvm.sh ] && source /etc/profile.d/rvm.sh || source "$HOME/.rvm/scripts/rvm"
rvm autolibs disable
rvm install "ruby-3.1.3"
rvm --default use "ruby-3.1.3"

cd /root
git clone https://github.com/chatwoot/chatwoot.git
cd chatwoot
git checkout b1ec67d11020ac52b74fa96af9803abdaa521509

cat > /root/compile.sh << 'EOL'
cd /root/chatwoot

# fix: 让source脚本对current session立刻生效, so avoid reboot
[ -f /etc/profile.d/rvm.sh ] && source /etc/profile.d/rvm.sh || source "$HOME/.rvm/scripts/rvm"
[[ ! -f /usr/bin/mkdir ]] && ln -s /bin/mkdir /usr/bin/mkdir
sed -i 's/sassc (2.4.0)/sassc (2.1.0)/' Gemfile.lock
bundle
sed -i '/"@chatwoot\/prosemirror-schema":/c\    "@chatwoot/prosemirror-schema": "https://github.com/chatwoot/prosemirror-schema.git#58fe432",' package.json
sed -e 's/variable-mention/58fe432/g' -e 's/2205f322e54517c415d54b013742838f2e5faf89/58fe4323c3c62c78df5150fca19fa169c9a9e881/g' -i yarn.lock
yarn
secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 63 ; echo '')
echo $secret > secret.tmp
#export NODE_ENV="production"
SECRET_KEY_BASE=$secret bundle exec rake assets:precompile RAILS_ENV=production
EOL

cat > /root/start.sh << 'EOL'
cd /root/chatwoot

# https://github.com/chatwoot/chatwoot/blob/master/deployment/nginx_chatwoot.conf
tee /root/chatwoot/config/nginx.default.tpl > /dev/null << 'EOF'
upstream app_backend {
    server localhost:3000;
}

server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 25m;
    root /root/chatwoot/public;

    location / {
        proxy_pass http://app_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        #所有动态页面：强制不缓存、透传 Cookie
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "-1";
    }
}
EOF

# https://github.com/chatwoot/chatwoot/blob/master/deployment/setup_20.04.sh
if [ ! -f /root/inited ]; then
  secret=$(cat /root/chatwoot/secret.tmp)
  RAILS_ENV=production
  read -p "give a postgresql host ip(127.0.0.1,10.10.10.x,etc..):" ip
  read -p "give a postgresql admin password:" pw
  read -p "give a chatwoot user dbpassword:" cpw

  cp .env.example .env
  sed -i "/SECRET_KEY_BASE/ s/=.*/=${secret}/" .env
  sed -i "/REDIS_URL/ s/=.*/=redis:\/\/localhost:6379/" .env
  sed -i "/POSTGRES_HOST/ s/=.*/=${ip}/" .env
  sed -i "/POSTGRES_USERNAME/ s/=.*/=chatwoot/" .env
  sed -i "/POSTGRES_PASSWORD/ s/=.*/=${cpw}/" .env
  sed -i "/RAILS_ENV/ s/=.*/=${RAILS_ENV}/" .env
  echo -en "\nINSTALLATION_ENV=linux_script" >> ".env"

  PGPASSWORD="$pw" psql -h $ip -p 5432 -U postgres << EOF
    CREATE USER chatwoot CREATEDB;
    ALTER USER chatwoot PASSWORD '$cpw';
    ALTER ROLE chatwoot SUPERUSER;
    UPDATE pg_database SET datistemplate = FALSE WHERE datname = 'template1';
    DROP DATABASE template1;
    CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UNICODE';
    UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'template1';
    \c template1
    VACUUM FREEZE;
EOF

  bundle exec rails db:chatwoot_prepare RAILS_ENV=production

  # https://github.com/chatwoot/chatwoot/blob/master/deployment/chatwoot-worker.service
  tee /etc/systemd/system/chatwoot-worker.service > /dev/null << 'EOF'
[Unit]
Description=Chatwoot Worker Server
After=network.target postgresql.service

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/root/chatwoot
Environment="RAILS_ENV=production"
#用/bin/bash套起来从主机自动获取环变和路径，否则systemd默认得不到ruby需要的大量环境变量和路径需要手动喂
ExecStart=/bin/bash -lc 'bin/bundle exec sidekiq -C config/sidekiq.yml'

[Install]
WantedBy=multi-user.target
EOF
  # https://github.com/chatwoot/chatwoot/blob/master/deployment/chatwoot-web.service
  tee /etc/systemd/system/chatwoot-web.service > /dev/null << 'EOF'
[Unit]
Description=Chatwoot Web Server
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
User=root
WorkingDirectory=/root/chatwoot
Environment="RAILS_ENV=production"
#用/bin/bash套起来从主机自动获取环变和路径，否则systemd默认得不到ruby需要的大量环境变量和路径需要手动喂
ExecStart=/bin/bash -lc 'bin/rails server -p 3000'

[Install]
WantedBy=multi-user.target
EOF
  systemctl start redis
  systemctl enable -q --now chatwoot-worker
  systemctl enable -q --now chatwoot-web

  chmod -R 755 /root/chatwoot
  sed -i "s/user www-data;/user root;/g" /etc/nginx/nginx.conf
  cp /root/chatwoot/config/nginx.default.tpl /etc/nginx/sites-enabled/default
  systemctl restart nginx

  touch /root/inited
fi

EOL

echo "Cleaning up"
silent apt-get -y autoremove
silent apt-get -y autoclean
echo "Cleaned"

##############
