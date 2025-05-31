  core=$1
  sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /target/etc/ssh/sshd_config
  sed -i 's/http:\/\/github/https:\/\/github/g;s/http:\/\/gitee/https:\/\/gitee/g;s/${core}\/debianbase/https:\/\/snapshot.debian.org\/archive\/debian\/20231007T024024Z/g' /target/etc/apt/sources.list
