#!/bin/bash
set -e

### CẤU HÌNH ###
WORKDIR="/home/proxy-installer"
WORKDATA="$WORKDIR/data.txt"
FIRST_PORT=10000

random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

declare -a array=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

ip64() {
  printf "%s%s%s%s" \
    "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}" \
    "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}"
}

gen64() {
  printf "%s:%s:%s:%s:%s\n" "$1" "$(ip64)" "$(ip64)" "$(ip64)" "$(ip64)"
}

install_3proxy() {
  echo "Đang cài đặt 3proxy..."
  local URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
  wget -qO- "$URL" | bsdtar -xvf- || { echo "Lỗi: Tải 3proxy thất bại"; exit 1; }
  cd 3proxy-3proxy-0.8.6 || { echo "Lỗi: Không vào được thư mục"; exit 1; }
  make -f Makefile.Linux || { echo "Lỗi: Biên dịch thất bại"; exit 1; }
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
  chmod +x /etc/init.d/3proxy
  systemctl enable 3proxy
  cd "$WORKDIR"
}

gen_3proxy() {
  local tmp_config=$(mktemp)
  echo "daemon" > "$tmp_config"
  echo "maxconn 1000" >> "$tmp_config"
  echo "nscache 65536" >> "$tmp_config"
  echo "timeouts 1 5 30 60 180 1800 15 60" >> "$tmp_config"
  echo "setgid 65535" >> "$tmp_config"
  echo "setuid 65535" >> "$tmp_config"
  echo "flush" >> "$tmp_config"
  echo "auth strong" >> "$tmp_config"
  echo -n "users " >> "$tmp_config"
  awk -F/ '{printf "%s:CL:%s ", $1, $2}' "$WORKDATA" >> "$tmp_config"
  echo "" >> "$tmp_config"

  while IFS='/' read user pass ip4 port ip6; do
    echo "auth strong" >> "$tmp_config"
    echo "allow $user" >> "$tmp_config"
    echo "proxy -6 -n -a -p$port -i$ip4 -e$ip6" >> "$tmp_config"
    echo "flush" >> "$tmp_config"
  done < "$WORKDATA"

  cp "$tmp_config" /usr/local/etc/3proxy/3proxy.cfg
}

gen_data() {
  local count=0
  while [ "$count" -lt "$COUNT" ]; do
    local port=$(($FIRST_PORT + $count))
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 "$IP6")"
    ((count++))
  done
}

gen_proxy_file_for_user() {
  awk -F '/' '{print $3 ":" $4 ":" $1 ":" $2}' "$WORKDATA" > proxy.txt
}

upload_proxy() {
  local PASS=$(random)
  zip --password "$PASS" proxy.zip proxy.txt || { echo "Lỗi: Nén file thất bại"; exit 1; }
  local URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

  echo ""
  echo "✅ Proxy đã sẵn sàng! Định dạng: IP:PORT:USERNAME:PASSWORD"
  echo "📦 Link tải proxy: $URL"
  echo "🔑 Mật khẩu giải nén: $PASS"
  echo ""
}

install_jq() {
  echo "Đang cài jq..."
  wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
  chmod +x jq
  cp jq /usr/bin
}

gen_iptables() {
  local tmp_iptables=$(mktemp)
  for allowed_ip in "${ALLOWED_IPS[@]}"; do
    while IFS='/' read user pass ip4 port ip6; do
      echo "firewall-cmd --permanent --add-port=$port/tcp --add-source=$allowed_ip" >> "$tmp_iptables"
    done < "$WORKDATA"
  done
  echo "firewall-cmd --reload" >> "$tmp_iptables"
  cp "$tmp_iptables" "$WORKDIR/boot_iptables.sh"
  chmod +x "$WORKDIR/boot_iptables.sh"
  bash "$tmp_iptables"
}

gen_ifconfig() {
  local tmp_ifconfig=$(mktemp)
  while IFS='/' read user pass ip4 port ip6; do
    echo "ip -6 addr add $ip6/64 dev eth0" >> "$tmp_ifconfig"
  done < "$WORKDATA"
  cp "$tmp_ifconfig" "$WORKDIR/boot_ifconfig.sh"
  chmod +x "$WORKDIR/boot_ifconfig.sh"
  bash "$tmp_ifconfig"
}

### BẮT ĐẦU CÀI ĐẶT ###
echo "Cài đặt các gói cần thiết..."
yum -y install gcc net-tools bsdtar zip >/dev/null

mkdir -p "$WORKDIR" && cd "$WORKDIR"

install_3proxy

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IPv4: $IP4 | IPv6 Prefix: $IP6"

read -p "Bạn muốn tạo bao nhiêu proxy? (VD: 300): " COUNT

ALLOWED_IPS=()
echo "Nhập dải IP được phép truy cập (tối đa 5). Nhấn Enter khi xong:"
while true; do
  read -p "IP ${#ALLOWED_IPS[@]}: " IP
  [ -z "$IP" ] && break
  ALLOWED_IPS+=("$IP")
  [ ${#ALLOWED_IPS[@]} -ge 5 ] && break
done

if [ ${#ALLOWED_IPS[@]} -eq 0 ]; then
  echo "⚠️ Không giới hạn IP truy cập. Proxy sẽ mở cho toàn thế giới."
fi

gen_data > "$WORKDATA"
gen_iptables
gen_ifconfig
gen_3proxy
gen_proxy_file_for_user

# Tự động chạy khi reboot
cat >> /etc/rc.local <<EOF
bash $WORKDIR/boot_iptables.sh
bash $WORKDIR/boot_ifconfig.sh
ulimit -n 10048
systemctl start 3proxy
EOF
chmod +x /etc/rc.local
bash /etc/rc.local

install_jq
upload_proxy
