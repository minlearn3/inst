###############

silent() { "$@" >/dev/null 2>&1; }

echo "Installing Dependencies"
silent apt-get update -y
silent apt-get install -y curl sudo mc
echo "Installed Dependencies"

get_latest_release() {
  curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
PORTAINER_LATEST_VERSION=$(get_latest_release "portainer/portainer")
PORTAINER_AGENT_LATEST_VERSION=$(get_latest_release "portainer/agent")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")

echo "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
silent sh <(curl -sSL https://get.docker.com)
echo "Installed Docker $DOCKER_LATEST_VERSION"

echo "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
curl -sSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose
echo "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

read -r -p "Would you like to add Portainer? <y/N> " prompt </dev/tty
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  echo "Installing Portainer $PORTAINER_LATEST_VERSION"
  docker volume create portainer_data >/dev/null
  silent docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name=portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  echo "Installed Portainer $PORTAINER_LATEST_VERSION"
else
  read -r -p "Would you like to add the Portainer Agent? <y/N> " prompt </dev/tty
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    echo "Installing Portainer agent $PORTAINER_AGENT_LATEST_VERSION"
    silent docker run -d \
      -p 9001:9001 \
      --name portainer_agent \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent
    echo "Installed Portainer Agent $PORTAINER_AGENT_LATEST_VERSION"
  fi
fi

cat > /root/init.sh << 'EOL'
if [[ -n $1 ]]; then
  docker stop `docker ps -a -q  --filter ancestor=$1` && docker rm `docker ps -a -q  --filter ancestor=$1`
  for i in `seq 1 10`; do sleep 5 && docker run -d --restart=always $1;done
fi
EOL
chmod +x /root/init.sh


echo "Cleaning up"
silent apt-get -y autoremove
silent apt-get -y autoclean
echo "Cleaned"