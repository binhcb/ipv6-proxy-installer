#!/bin/bash
set -e
### CẤU HÌNH ###
WORKDIR="/home/proxy-installer" WORKDATA="$WORKDIR/data.txt" 
FIRST_PORT=10000
### HÀM SINH NGẪU NHIÊN ###
random() { tr </dev/urandom -dc A-Za-z0-9 | head -c5 echo
}
declare -a array=(0 1 2 3 4 5 6 7 8 9 a b c d e f) gen64() { local 
  ip64() {
    printf "%s%s:%s%s" \ "${array[$RANDOM % 16]}" "${array[$RANDOM % 
      16]}" \ "${array[$RANDOM % 16]}" "${array[$RANDOM % 16]}"
  }
  printf "%s:%s:%s:%s:%s\n" "$1" "$(ip64)" "$(ip64)" "$(ip64)" 
  "$(ip64)"
}
### CÀI 3PROXY ###
install_3proxy() { echo "Dang cai dat 3proxy..." local 
  URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz" 
  wget -qO- "$URL" | tar xz || { echo "Loi tai 3proxy"; exit 1; } cd 
  3proxy-3proxy-0.8.6 make -f Makefile.Linux mkdir -p 
  /usr/local/etc/3proxy/{bin,logs,stat} cp src/3proxy 
  /usr/local/etc/3proxy/bin/ cp ./scripts/rc.d/proxy.sh 
  /etc/init.d/3proxy chmod +x /etc/init.d/3proxy cd "$WORKDIR"
}
### SINH CẤU HÌNH 3PROXY ###
gen_3proxy() { local cfg="/usr/local/etc/3proxy/3proxy.cfg" cat <<EOF 
  > "$cfg"
daemon maxconn 1000 nscache 65536 timeouts 1 5 30 60 180 1800 15 60 
setgid 65535 setuid 65535 auth strong users $(awk -F/ 'BEGIN{ORS="";} 
{print $1":CL:"$2" "}' "$WORKDATA") EOF
  while IFS='/' read user pass ip4 port ip6; do echo "auth strong" >> 
    "$cfg" echo "allow $user" >> "$cfg" echo "proxy -6 -n -a -p$port 
    -i$ip4 -e$ip6" >> "$cfg" echo "flush" >> "$cfg"
  done < "$WORKDATA"
}
### SINH DATA ###
gen_data() { local count=0 while [ "$count" -lt "$COUNT" ]; do local 
    port=$(($FIRST_PORT + $count)) echo 
    "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)" ((count++))
  done
}
### IPTABLES ###
gen_iptables() { local script="$WORKDIR/boot_iptables.sh"
  > "$script"
  for ip in "${ALLOWED_IPS[@]}"; do while IFS='/' read _ _ _ port _; 
    do
      echo "firewall-cmd --permanent --add-port=${port}/tcp 
      --add-source=${ip}" >> "$script"
    done < "$WORKDATA" done echo "firewall-cmd --reload" >> "$script" 
  chmod +x "$script" bash "$script"
}
### IFCONFIG ###
gen_ifconfig() { local script="$WORKDIR/boot_ifconfig.sh"
  > "$script"
  while IFS='/' read _ _ _ _ ip6; do echo "ip -6 addr add $ip6/64 dev 
    eth0" >> "$script"
  done < "$WORKDATA" chmod +x "$script" bash "$script"
}
### TẠO FILE PROXY ###
gen_proxy_file_for_user() { awk -F '/' '{print $3":"$4":"$1":"$2}' 
  "$WORKDATA" > "$WORKDIR/proxy.txt"
}
upload_proxy() { local pass=$(random) zip --password "$pass" 
  "$WORKDIR/proxy.zip" "$WORKDIR/proxy.txt" local url=$(curl -s 
  --upload-file "$WORKDIR/proxy.zip" https://transfer.sh/proxy.zip) 
  echo "\nProxy đã tạo xong!" echo "URL tải về: $url" echo "Mật khẩu 
  giải nén: $pass"
}
install_jq() { wget -O /usr/bin/jq 
  https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 
  chmod +x /usr/bin/jq
}
### MAIN ###
echo "Dang cai goi can thiet..." yum install -y epel-release gcc 
net-tools bsdtar zip wget curl firewalld >/dev/null systemctl enable 
--now firewalld mkdir -p "$WORKDIR" && cd "$WORKDIR" IP4=$(curl -4 -s 
icanhazip.com) IP6=$(curl -6 -s icanhazip.com | cut -d':' -f1-4) read 
-p "Ban muon tao bao nhieu proxy? (vi du: 300): " COUNT ALLOWED_IPS=() 
echo "Nhap toi da 5 dải IP duoc phep truy cap (Enter de bo qua):" for 
i in {1..5}; do
  read -p "IP thu $i: " ip [[ -z "$ip" ]] && break 
  ALLOWED_IPS+=("$ip")
done install_3proxy gen_data > "$WORKDATA" gen_iptables gen_ifconfig 
gen_3proxy echo -e "\nbash $WORKDIR/boot_iptables.sh\nbash 
$WORKDIR/boot_ifconfig.sh\nulimit -n 10048\nsystemctl start 3proxy" >> 
/etc/rc.local chmod +x /etc/rc.d/rc.local systemctl enable 
rc-local.service systemctl start rc-local gen_proxy_file_for_user 
install_jq upload_proxy systemctl status 3proxy --no-pager
