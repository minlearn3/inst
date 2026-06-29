###############

silent() { "$@" >/dev/null 2>&1 || { echo "Error running: $*"; echo "sth error"; exit 1; }; }


debmirror=${1:-http://deb.debian.org/debian}
echo -e "deb ${debmirror} bullseye main\ndeb ${debmirror} bullseye-updates main\ndeb ${debmirror}-security bullseye-security main" > /etc/apt/sources.list

echo "Installing Dependencies"
silent apt-get update -y
silent apt-get install -y curl sudo mc qrencode jq
echo "Installed Dependencies"

silent apt-get install -y procps debconf-utils
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections >/dev/null 2>&1; \
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections >/dev/null 2>&1;
silent apt-get install -y iptables-persistent

cd /root

arch=$([[ "$(arch)" == "aarch64" ]] && echo _arm64)
rlsmirror=${2:-https://github.com/minlearn/inst/releases/download/inital}
mkdir -p download
[[ ! -f download/tmp.tar.gz ]] && wget --no-check-certificate $rlsmirror/xray$arch.tar.gz -O download/tmp.tar.gz

mkdir -p app/xray
tar -xzvf download/tmp.tar.gz -C app/xray xray --strip-components=1

cat > /lib/systemd/system/xray.service << 'EOL'
[Unit]
Description=this is xray service,please change the token then daemon-reload it
After=network.target nss-lookup.target
Wants=network.target nss-lookup.target
Requires=network.target nss-lookup.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c "date=$$(echo -n $$(ip addr |grep $$(ip route show |grep -o 'default via [0-9]\\{1,3\\}.[0-9]\\{1,3\\}.[0-9]\\{1,3\\}.[0-9]\\{1,3\\}.*' |head -n1 |sed 's/proto.*\\|onlink.*//g' |awk '{print $$NF}') |grep 'global' |grep 'brd' |head -n1 |grep -o '[0-9]\\{1,3\\}.[0-9]\\{1,3\\}.[0-9]\\{1,3\\}.[0-9]\\{1,3\\}/[0-9]\\{1,2\\}') |cut -d'/' -f1);PATH=/usr/local/bin:$PATH exec sed -i s/xxx.xxxxxx.com/$${date}/g /root/app/xray/config.yaml"
ExecStart=/root/app/xray/xray -c /root/app/xray/config.yaml
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOL

cat > /root/app/xray/config.yaml << 'EOL'
{
  "log": null,
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "port": "443",
        "network": "udp",
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "www.gstatic.com"
        ],
        "outboundTag": "direct"
      },
      {
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "vps-outbound-v4",
        "domain": [
          "api.myip.com"
        ]
      },
      {
        "type": "field",
        "outboundTag": "vps-outbound-v6",
        "domain": [
          "api64.ipify.org"
        ]
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "network": "udp,tcp"
      }
    ]
  },
  "dns": null,
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "streamSettings": null,
      "tag": "api",
      "sniffing": null
    },
    {
      "listen": null,
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "xxxxxxxxxxxxxxxxx",
            "flow": ""
          }
        ],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "localhost",
          "rejectUnknownSni": false,
          "minVersion": "1.2",
          "maxVersion": "1.3",
          "cipherSuites": "",
          "certificates": [
            {
              "ocspStapling": 3600,
              "certificateFile": "/root/app/xray/certs/localhost.crt",
              "keyFile": "/root/app/xray/certs/localhost.key"
            }
          ],
          "alpn": [
            "http/1.1",
            "h2"
          ],
          "settings": [
            {
              "allowInsecure": false,
              "fingerprint": "",
              "serverName": ""
            }
          ]
        },
        "wsSettings": {
          "path": "/mywebsocket",
          "headers": {
            "Host": "xxx.xxxxxx.com"
          }
        }
      },
      "tag": "inbound-443",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "blackhole",
      "tag": "blocked"
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4v6"
      }
    },
    {
      "tag": "vps-outbound-v4",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4v6"
      }
    },
    {
      "tag": "vps-outbound-v6",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv6v4"
      }
    }
  ],
  "transport": null,
  "policy": {
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    },
    "levels": {
      "0": {
        "handshake": 10,
        "connIdle": 100,
        "uplinkOnly": 2,
        "downlinkOnly": 3,
        "bufferSize": 10240
      }
    }
  },
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ],
    "tag": "api"
  },
  "stats": {},
  "reverse": null,
  "fakeDns": null
}
EOL

cat > /root/token.sh << 'EOL'
read -p "give a uuid:" token </dev/tty
sed -i s#xxxxxxxxxxxxxxxxx#${token}#g /root/app/xray/config.yaml
systemctl restart xray
EOL
chmod +x /root/token.sh

cat > /root/ip.sh << 'EOL'
read -p "give a ip:" ip </dev/tty
date=$(echo -n $(ip addr |grep $(ip route show |grep -o 'default via [0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}.*' |head -n1 |sed 's/proto.*\|onlink.*//g' |awk '{print $NF}') |grep 'global' |grep 'brd' |head -n1 |grep -o '[0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}/[0-9]\{1,2\}') |cut -d'/' -f1)
sed -i s#${date}#${ip}#g /root/app/xray/config.yaml
systemctl restart xray
EOL
chmod +x /root/ip.sh

cat > /root/client.sh << 'EOL'
echo "标准proxies节点（无配置头无规则）:"
jq -r '
  .inbounds[]
  | select(.protocol=="vless")
  | "  - {name: \"" +
      (.streamSettings.tlsSettings.serverName // .streamSettings.wsSettings.headers.Host // "yourip") +
      "\", server: \"" + 
      (.streamSettings.tlsSettings.serverName // .streamSettings.wsSettings.headers.Host // "yourip") +
      "\", port: " + (.port|tostring) +
      ", client-fingerprint: chrome" +
      ", type: vless" +
      ", uuid: " + (.settings.clients[0].id|@sh) +
      ", tls: true, tfo: false, skip-cert-verify: true, network: ws" +
      ", ws-opts: {path: " + (.streamSettings.wsSettings.path|@sh) +
      ", headers: {Host: " + (.streamSettings.wsSettings.headers.Host|@sh) +
      "}}}"
' /root/app/xray/config.yaml
VLESSURL=$(jq -r '
  .inbounds[]
  | select(.protocol=="vless")
  | "vless://" + .settings.clients[0].id + "@" +
    (.streamSettings.tlsSettings.serverName // .streamSettings.wsSettings.headers.Host // "yourip") +
    ":" + (.port|tostring) +
    "?encryption=none&security=tls&type=ws&host=" +
    (.streamSettings.wsSettings.headers.Host) +
    "&path=" + (.streamSettings.wsSettings.path|@uri) +
    "#"+ (.streamSettings.tlsSettings.serverName // .streamSettings.wsSettings.headers.Host // "yourip")
' /root/app/xray/config.yaml)
echo "$VLESSURL" > /root/sub.txt
qrencode -m 2 -t ANSIUTF8 $VLESSURL >> /root/sub.txt
echo ""
echo "标准vless订阅url:" $VLESSURL 
echo "订阅信息及二维码已保存到sub.txt，可用进一步用subconverter等处理"
echo "客户端连接时建议勾选skip-cert-verify之类开关"
EOL
chmod +x /root/client.sh

cat > /root/transport.sh << 'EOL'
silent() { "$@" >/dev/null 2>&1 || { echo "Error running: $*"; exit 1; }; }
read -r -p "Enable transparent gateway TPROXY mode, remove public VLESS inbound, ONLY RDP port traffic go vmess proxy, continue? <y/N> " prompt </dev/tty
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    MAIN_CFG="/root/app/xray/config.yaml"
    TMP_CFG=$(mktemp)

    # 开启info日志
    jq '.log = {"loglevel": "info"}' "$MAIN_CFG" > "$TMP_CFG"
    cp "$TMP_CFG" "$MAIN_CFG"
    rm -f "$TMP_CFG"
    echo "[OK] Enable Xray info log level"

    # 删除公网VLESS 443入站
    jq '.inbounds |= map(select(.tag != "inbound-443"))' "$MAIN_CFG" > "$TMP_CFG"
    cp "$TMP_CFG" "$MAIN_CFG"
    rm -f "$TMP_CFG"
    echo "[OK] Removed public VLESS 443 inbound"

    # TPROXY 透明入站配置
    TRAN_INBOUND='{
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp",
        "followRedirect": true
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      },
      "tag": "transparent"
    }'

    # RDP端口最高优先级路由规则
    RULE_RDP='{
      "type": "field",
      "inboundTag": ["transparent"],
      "port": "13389,3389",
      "outboundTag": "proxy"
    }'

    # 内网网段直连规则
    RULE_LAN='{
      "type": "field",
      "ip": ["10.0.0.0/8","192.168.0.0/16","172.16.0.0/12"],
      "outboundTag": "direct"
    }'

    # VMESS出站节点，自行替换IP/域名与UUID
    OUT_VMESS='{
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "你的VMESS节点地址",
            "port": 443,
            "users": [
              {
                "id": "你的VMESS UUID",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tcpSettings": {
          "header": {
            "type": "none"
          },
          "keepAlive": true
        }
      }
    }'

    # 追加透明入站
    if ! jq -e '.inbounds[] | select(.tag == "transparent")' "$MAIN_CFG" >/dev/null 2>&1; then
        jq --argjson newin "$TRAN_INBOUND" '.inbounds += [$newin]' "$MAIN_CFG" > "$TMP_CFG"
        cp "$TMP_CFG" "$MAIN_CFG"
        rm -f "$TMP_CFG"
        echo "[OK] Add TPROXY transparent inbound 12345"
    fi

    # RDP规则置顶，最高优先级
    jq --argjson r "$RULE_RDP" '.routing.rules = [$r] + .routing.rules' "$MAIN_CFG" > "$TMP_CFG"
    cp "$TMP_CFG" "$MAIN_CFG"
    rm -f "$TMP_CFG"
    echo "[OK] Top priority rule: RDP port force proxy"

    # 内网直连规则插入兜底direct前
    LAN_LIST='["10.0.0.0/8","192.168.0.0/16","172.16.0.0/12"]'
    if ! jq -e --argjson ip "$LAN_LIST" '.routing.rules[] | select(.ip == $ip)' "$MAIN_CFG" >/dev/null 2>&1; then
        jq --argjson r "$RULE_LAN" '.routing.rules |= .[:-1] + [$r] + .[-1:]' "$MAIN_CFG" > "$TMP_CFG"
        cp "$TMP_CFG" "$MAIN_CFG"
        rm -f "$TMP_CFG"
        echo "[OK] Insert LAN direct rule before default direct"
    fi

    # 追加vmess proxy出站
    if ! jq -e '.outbounds[] | select(.tag == "proxy")' "$MAIN_CFG" >/dev/null 2>&1; then
        jq --argjson out "$OUT_VMESS" '.outbounds += [$out]' "$MAIN_CFG" > "$TMP_CFG"
        cp "$TMP_CFG" "$MAIN_CFG"
        rm -f "$TMP_CFG"
        echo "[OK] Add vmess proxy outbound"
    fi

    # TPROXY 路由表持久写入网卡配置
    grep -xF "100 tproxy" /etc/iproute2/rt_tables || echo "100 tproxy" >> /etc/iproute2/rt_tables
    GW_LINE="gateway 10.10.10.254"
    CHECK_STR="post-up ip rule add fwmark 100 table tproxy"
    grep -q "$CHECK_STR" /etc/network/interfaces || silent sed -i "/$GW_LINE/a\\        post-up ip rule add fwmark 100 table tproxy\n\\        post-up ip route add local 0.0.0.0/0 dev lo table tproxy\n\\        pre-down ip rule del fwmark 100 table tproxy || true\n\\        pre-down ip route del default table tproxy || true" /etc/network/interfaces

    # 开启内核转发
    grep -q '^net.ipv4.ip_forward = 1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    grep -q '^net.ipv4.conf.all.route_localnet = 1' /etc/sysctl.conf || echo 'net.ipv4.conf.all.route_localnet = 1' >> /etc/sysctl.conf
    silent sysctl -p

    # 清空旧nat劫持链（REDIRECT模式废弃）
    silent iptables -t nat -F PREROUTING
    if iptables -t nat -L xray >/dev/null 2>&1; then
        silent iptables -t nat -X xray
    fi
    silent netfilter-persistent save

    # 清空mangle旧规则，TPROXY专用规则（仅标记RDP端口，LXC兼容无多逗号端口）
    silent iptables -t mangle -F PREROUTING
    if iptables -t mangle -L XRAY_TPROXY >/dev/null 2>&1; then
        silent iptables -t mangle -X XRAY_TPROXY
    fi
    silent iptables -t mangle -N XRAY_TPROXY

    # 内网网段直接放行跳过劫持
    silent iptables -t mangle -A XRAY_TPROXY -d 0.0.0.0/8 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 10.0.0.0/8 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 127.0.0.0/8 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 169.254.0.0/16 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 172.16.0.0/12 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 192.168.0.0/16 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 224.0.0.0/4 -j RETURN
    silent iptables -t mangle -A XRAY_TPROXY -d 240.0.0.0/4 -j RETURN

    # 分开两条端口，规避legacy iptables逗号报错
    silent iptables -t mangle -A XRAY_TPROXY -p tcp --dport 13389 -j MARK --set-mark 100
    silent iptables -t mangle -A XRAY_TPROXY -p tcp --dport 3389 -j MARK --set-mark 100

    # 匹配标记流量转发TPROXY（无--fwmark兼容旧iptables）
    silent iptables -t mangle -A XRAY_TPROXY -m mark --mark 100 -j TPROXY --on-port 12345

    # 其余流量直接放行不劫持
    silent iptables -t mangle -A XRAY_TPROXY -j RETURN

    # 绑定全局前置处理链
    silent iptables -t mangle -A PREROUTING -p tcp -j XRAY_TPROXY

    # 基础转发、12345端口权限
    silent iptables -P FORWARD ACCEPT
    silent iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 12345 -j ACCEPT
    silent iptables -A INPUT -p tcp --dport 12345 -j DROP

    # 持久保存
    silent netfilter-persistent save

    # 重启网络与xray
    silent systemctl restart networking
    silent systemctl restart xray

    echo -e "\n✅ Finished: TPROXY transparent proxy enabled, ONLY RDP 13389/3389 traffic go vmess"
fi
EOL
chmod +x /root/transport.sh

systemctl enable -q --now xray


echo "Cleaning up"
silent apt-get -y autoremove
silent apt-get -y autoclean
echo "Cleaned"

##############
