#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	Yêu cầu hệ thống: CentOS/Debian/Ubuntu
#	Mô tả: Script quản lý Shadowsocks Rust
#	Tác giả: 翠花
#	Trang web: https://about.nange.cn
#=================================================

sh_ver="1.4.4"
filepath=$(cd "$(dirname "$0")"; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/etc/ss-rust"
FILE="/usr/local/bin/ss-rust"
CONF="/etc/ss-rust/config.json"
Now_ver_File="/etc/ss-rust/ver.txt"
Local="/etc/sysctl.d/local.conf"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[Thông tin]${Font_color_suffix}"
Error="${Red_font_prefix}[Lỗi]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[Chú ý]${Font_color_suffix}"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} Hiện tại không phải là tài khoản ROOT (hoặc không có quyền ROOT), không thể tiếp tục thao tác, vui lòng chuyển sang tài khoản ROOT hoặc sử dụng lệnh ${Green_background_prefix}sudo su${Font_color_suffix} để nhận quyền ROOT tạm thời (sau khi thực hiện có thể sẽ yêu cầu nhập mật khẩu tài khoản hiện tại)." && exit 1
}

check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
}

sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i686"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="arm"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="x86_64"
    fi    
}

#Kích hoạt TCP Fast Open của hệ thống
enable_systfo() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen
		[[ ! -e $Local ]] && echo "fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/local.conf && sysctl --system >/dev/null 2>&1
	else
		echo -e "$ErrorPhiên bản kernel của hệ thống quá thấp, không hỗ trợ TCP Fast Open!"
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Shadowsocks Rust chưa được cài đặt, vui lòng kiểm tra!" && exit 1
}

check_status(){
	status=`systemctl status ss-rust | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
}

check_new_ver(){
	new_ver=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases| jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')
	[[ -z ${new_ver} ]] && echo -e "${Error} Không lấy được phiên bản mới nhất của Shadowsocks Rust!" && exit 1
	echo -e "${Info} Phát hiện phiên bản mới nhất của Shadowsocks Rust là [ ${new_ver} ]"
}

check_ver_comparison(){
	now_ver=$(cat ${Now_ver_File})
	if [[ "${now_ver}" != "${new_ver}" ]]; then
		echo -e "${Info} Đã phát hiện phiên bản mới của Shadowsocks Rust [ ${new_ver} ], phiên bản cũ [ ${now_ver} ]"
		read -e -p "Có muốn cập nhật không? [Y/n]：" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ $yn == [Yy] ]]; then
			check_status
			# [[ "$status" == "running" ]] && systemctl stop ss-rust
			\cp "${CONF}" "/tmp/config.json"
			# rm -rf ${FOLDER}
			Download
			mv -f "/tmp/config.json" "${CONF}"
			Restart
		fi
	else
		echo -e "${Info} Shadowsocks Rust hiện đã là phiên bản mới nhất [ ${new_ver} ]!" && exit 1
	fi
}

stable_Download() {
	echo -e "${Info} Bắt đầu tải về Shadowsocks Rust từ nguồn chính thức ……"
	wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
	if [[ ! -e "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz" ]]; then
		echo -e "${Error} Tải về Shadowsocks Rust từ nguồn chính thức thất bại!"
		return 1 && exit 1
	else
		tar -xvf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
	fi
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Giải nén Shadowsocks Rust thất bại!"
		echo -e "${Error} Cài đặt Shadowsocks Rust thất bại!"
		return 1 && exit 1
	else
		rm -rf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
        chmod +x ssserver
	    mv -f ssserver "${FILE}"
	    rm sslocal ssmanager ssservice ssurl
	    echo "${new_ver}" > ${Now_ver_File}

        echo -e "${Info} Tải và cài đặt Shadowsocks Rust thành công!"
		return 0
	fi
}

backup_Download() {
	echo -e "${Info} Thử tải Shadowsocks Rust từ nguồn dự phòng (phiên bản cũ) ……"
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/shadowsocks-rust/v1.14.1/shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
	if [[ ! -e "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz" ]]; then
		echo -e "${Error} Tải từ nguồn dự phòng thất bại!"
		return 1 && exit 1
	else
		tar -xvf "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
	fi
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Giải nén từ nguồn dự phòng thất bại!"
		echo -e "${Error} Cài đặt từ nguồn dự phòng thất bại!"
		return 1 && exit 1
	else
		rm -rf "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
		chmod +x ssserver
	    mv -f ssserver "${FILE}"
	    rm sslocal ssmanager ssservice ssurl
		echo "v1.14.1" > ${Now_ver_File}
		echo -e "${Info} Cài đặt thành công từ nguồn dự phòng!"
		return 0
	fi
}

Download() {
	if [[ ! -e "${FOLDER}" ]]; then
		mkdir "${FOLDER}"
	# else
		# [[ -e "${FILE}" ]] && rm -rf "${FILE}"
	fi
	stable_Download
	if [[ $? != 0 ]]; then
		backup_Download
	fi
}

Service(){
	echo '
[Unit]
Description= Shadowsocks Rust Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStartPre=/bin/sh -c 'ulimit -n 51200'
ExecStart=/usr/local/bin/ss-rust -c /etc/ss-rust/config.json
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/ss-rust.service
systemctl enable --now ss-rust
	echo -e "${Info} Dịch vụ Shadowsocks Rust đã được cấu hình xong!"
}

Installation_dependency(){
	if [[ ${release} == "centos" ]]; then
		yum update
		yum install jq gzip wget curl unzip xz openssl -y
	else
		apt-get update
		apt-get install jq gzip wget curl unzip xz-utils openssl -y
	fi
	\cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

Write_config(){
	cat > ${CONF}<<-EOF
{
    "server": "::",
    "server_port": ${port},
    "password": "${password}",
    "method": "${cipher}",
    "fast_open": ${tfo},
    "mode": "tcp_and_udp",
    "user":"nobody",
    "timeout":300,
    "nameserver":"8.8.8.8"
}
EOF
}

Read_config(){
	[[ ! -e ${CONF} ]] && echo -e "${Error} Không tìm thấy file cấu hình Shadowsocks Rust!" && exit 1
	port=$(cat ${CONF}|jq -r '.server_port')
	password=$(cat ${CONF}|jq -r '.password')
	cipher=$(cat ${CONF}|jq -r '.method')
	tfo=$(cat ${CONF}|jq -r '.fast_open')
}

Set_port(){
	while true
		do
		echo -e "${Tip} Bước này không liên quan đến thao tác mở cổng trên tường lửa hệ thống, vui lòng mở cổng tương ứng theo cách thủ công!"
		echo -e "Vui lòng nhập cổng Shadowsocks Rust [1-65535]"
		read -e -p "(Mặc định: 2525)：" port
		[[ -z "${port}" ]] && port="2525"
		echo $((${port}+0)) &>/dev/null
		if [[ $? -eq 0 ]]; then
			if [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
				echo && echo "=================================="
				echo -e "Cổng: ${Red_background_prefix} ${port} ${Font_color_suffix}"
				echo "==================================" && echo
				break
			else
				echo "Lỗi nhập, vui lòng nhập cổng hợp lệ."
			fi
		else
			echo "Lỗi nhập, vui lòng nhập cổng hợp lệ."
		fi
		done
}

Set_tfo(){
	echo -e "Bật TCP Fast Open?
==================================
${Green_font_prefix} 1.${Font_color_suffix} Bật  ${Green_font_prefix} 2.${Font_color_suffix} Tắt
=================================="
	read -e -p "(Mặc định: 1. Bật)：" tfo
	[[ -z "${tfo}" ]] && tfo="1"
	if [[ ${tfo} == "1" ]]; then
		tfo=true
		enable_systfo
	else
		tfo=false
	fi
	echo && echo "=================================="
	echo -e "Trạng thái TCP Fast Open: ${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_password(){
	# Kiểm tra loại mã hóa được chọn
	if [[ ${cipher} == "aes-256-gcm" || ${cipher} == "2022-blake3-aes-256-gcm" ]]; then
		password_length=32
	elif [[ ${cipher} == "aes-128-gcm" || ${cipher} == "2022-blake3-aes-128-gcm" ]]; then
		password_length=16
	else
		password_length=16  # Đặt mặc định là 16 cho các loại mã hóa khác
	fi

	echo "Vui lòng nhập mật khẩu Shadowsocks Rust [0-9][a-z][A-Z]"
	read -e -p "(Mặc định: Tạo ngẫu nhiên Base64)：" password
	[[ -z "${password}" ]] && password=$(openssl rand -base64 ${password_length})

	echo && echo "=================================="
	echo -e "Mật khẩu: ${Red_background_prefix} ${password} ${Font_color_suffix}"
	echo "=================================="
}

Set_cipher(){
	echo -e "Chọn phương thức mã hóa cho Shadowsocks Rust
==================================	
 ${Green_font_prefix} 1.${Font_color_suffix} aes-128-gcm ${Green_font_prefix}(Mặc định)${Font_color_suffix}
 ${Green_font_prefix} 2.${Font_color_suffix} aes-256-gcm ${Green_font_prefix}(Khuyến nghị)${Font_color_suffix}
 ${Green_font_prefix} 3.${Font_color_suffix} chacha20-ietf-poly1305 ${Green_font_prefix}${Font_color_suffix}
 ${Green_font_prefix} 4.${Font_color_suffix} plain ${Red_font_prefix}(Không khuyến nghị)${Font_color_suffix}
 ${Green_font_prefix} 5.${Font_color_suffix} none ${Red_font_prefix}(Không khuyến nghị)${Font_color_suffix}
 ${Green_font_prefix} 6.${Font_color_suffix} table
 ${Green_font_prefix} 7.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 8.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-256-ctr 
 ${Green_font_prefix}10.${Font_color_suffix} camellia-256-cfb
 ${Green_font_prefix}11.${Font_color_suffix} rc4-md5
 ${Green_font_prefix}12.${Font_color_suffix} chacha20-ietf
==================================
 ${Tip} Mã hóa AEAD 2022 (yêu cầu phiên bản v1.15.0 trở lên và mật khẩu cần mã hóa Base64)
==================================	
 ${Green_font_prefix}13.${Font_color_suffix} 2022-blake3-aes-128-gcm ${Green_font_prefix}(Khuyến nghị)${Font_color_suffix}
 ${Green_font_prefix}14.${Font_color_suffix} 2022-blake3-aes-256-gcm ${Green_font_prefix}(Khuyến nghị)${Font_color_suffix}
 ${Green_font_prefix}15.${Font_color_suffix} 2022-blake3-chacha20-poly1305
 ${Green_font_prefix}16.${Font_color_suffix} 2022-blake3-chacha8-poly1305
 ==================================
 ${Tip} Nếu cần phương thức mã hóa khác, vui lòng tự chỉnh sửa file cấu hình!" && echo
	read -e -p "(Mặc định: 1. aes-128-gcm)：" cipher
	[[ -z "${cipher}" ]] && cipher="1"
	if [[ ${cipher} == "1" ]]; then
		cipher="aes-128-gcm"
	elif [[ ${cipher} == "2" ]]; then
		cipher="aes-256-gcm"
	elif [[ ${cipher} == "3" ]]; then
		cipher="chacha20-ietf-poly1305"
	elif [[ ${cipher} == "4" ]]; then
		cipher="plain"
	elif [[ ${cipher} == "5" ]]; then
		cipher="none"
	elif [[ ${cipher} == "6" ]]; then
		cipher="table"
	elif [[ ${cipher} == "7" ]]; then
		cipher="aes-128-cfb"
	elif [[ ${cipher} == "8" ]]; then
		cipher="aes-256-cfb"
	elif [[ ${cipher} == "9" ]]; then
		cipher="aes-256-ctr"
	elif [[ ${cipher} == "10" ]]; then
		cipher="camellia-256-cfb"
	elif [[ ${cipher} == "11" ]]; then
		cipher="arc4-md5"
	elif [[ ${cipher} == "12" ]]; then
		cipher="chacha20-ietf"
	elif [[ ${cipher} == "13" ]]; then
		cipher="2022-blake3-aes-128-gcm"
	elif [[ ${cipher} == "14" ]]; then
		cipher="2022-blake3-aes-256-gcm"
	elif [[ ${cipher} == "15" ]]; then
		cipher="2022-blake3-chacha20-poly1305"
	elif [[ ${cipher} == "16" ]]; then
		cipher="2022-blake3-chacha8-poly1305"		
	else
		cipher="aes-128-gcm"
	fi
	echo && echo "=================================="
	echo -e "Mã hóa: ${Red_background_prefix} ${cipher} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set(){
	check_installed_status
	echo && echo -e "Bạn muốn làm gì?
==================================
 ${Green_font_prefix}1.${Font_color_suffix}  Thay đổi cài đặt cổng
 ${Green_font_prefix}2.${Font_color_suffix}  Thay đổi mật khẩu
 ${Green_font_prefix}3.${Font_color_suffix}  Thay đổi phương thức mã hóa
 ${Green_font_prefix}4.${Font_color_suffix}  Thay đổi cấu hình TFO
==================================
 ${Green_font_prefix}5.${Font_color_suffix}  Thay đổi toàn bộ cấu hình" && echo
	read -e -p "(Mặc định: Hủy bỏ)：" modify
	[[ -z "${modify}" ]] && echo "Đã hủy..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		password=${password}
		cipher=${cipher}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_password
		port=${port}
		cipher=${cipher}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_cipher
		port=${port}
		password=${password}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		Set_tfo
		cipher=${cipher}
		port=${port}
		password=${password}
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_port
		Set_password
		Set_cipher
		Set_tfo
		Write_config
		Restart
	else
		echo -e "${Error} Vui lòng nhập số hợp lệ (1-5)" && exit 1
	fi
}

Install(){
	[[ -e ${FILE} ]] && echo -e "${Error} Phát hiện Shadowsocks Rust đã được cài đặt!" && exit 1
	echo -e "${Info} Bắt đầu thiết lập cấu hình..."
	Set_port
	Set_password
	Set_cipher
	Set_tfo
	echo -e "${Info} Bắt đầu cài đặt các phụ thuộc..."
	Installation_dependency
	echo -e "${Info} Bắt đầu tải về và cài đặt..."
	check_new_ver
	Download
	echo -e "${Info} Bắt đầu cài đặt dịch vụ hệ thống..."
	Service
	echo -e "${Info} Bắt đầu ghi file cấu hình..."
	Write_config
	echo -e "${Info} Tất cả bước đã hoàn tất, khởi động..."
	Start
}

Start(){
	check_installed_status
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Shadowsocks Rust đang chạy!" && exit 1
	systemctl start ss-rust
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Shadowsocks Rust khởi động thành công!"
    sleep 3s
    Start_Menu
}

Stop(){
	check_installed_status
	check_status
	[[ !"$status" == "running" ]] && echo -e "${Error} Shadowsocks Rust không đang chạy, vui lòng kiểm tra!" && exit 1
	systemctl stop ss-rust
    sleep 3s
    Start_Menu
}

Restart(){
	check_installed_status
	systemctl restart ss-rust
	echo -e "${Info} Shadowsocks Rust đã khởi động lại!"
	sleep 3s
	View
    Start_Menu
}

Update(){
	check_installed_status
	check_new_ver
	check_ver_comparison
	echo -e "${Info} Cập nhật Shadowsocks Rust hoàn tất!"
    sleep 3s
    Start_Menu
}

Uninstall(){
	check_installed_status
	echo "Bạn có chắc chắn muốn gỡ bỏ Shadowsocks Rust không? (y/N)"
	echo
	read -e -p "(Mặc định: n)：" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		check_status
		[[ "$status" == "running" ]] && systemctl stop ss-rust
        systemctl disable ss-rust
		rm -rf "${FOLDER}"
		rm -rf "${FILE}"
		echo && echo "Đã gỡ bỏ Shadowsocks Rust!" && echo
	else
		echo && echo "Đã hủy gỡ bỏ..." && echo
	fi
    sleep 3s
    Start_Menu
}

getipv4(){
	ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ipv4}" ]]; then
		ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ipv4}" ]]; then
			ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ipv4}" ]]; then
				ipv4="IPv4_Error"
			fi
		fi
	fi
}
getipv6(){
	ipv6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
	if [[ -z "${ipv6}" ]]; then
		ipv6="IPv6_Error"
	fi
}

urlsafe_base64(){
	date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
	echo -e "${date}"
}

Link_QR(){
	if [[ "${ipv4}" != "IPv4_Error" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@${ipv4}:${port}")
		SSurl="ss://${SSbase64}"
		SSQRcode="https://cli.im/api/qrcode/code?text=${SSurl}"
		link_ipv4=" Liên kết  [IPv4]：${Red_font_prefix}${SSurl}${Font_color_suffix} \n Mã QR [IPv4]：${Red_font_prefix}${SSQRcode}${Font_color_suffix}"
	fi
	if [[ "${ipv6}" != "IPv6_Error" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@${ipv6}:${port}")
		SSurl="ss://${SSbase64}"
		SSQRcode="https://cli.im/api/qrcode/code?text=${SSurl}"
		link_ipv6=" Liên kết  [IPv6]：${Red_font_prefix}${SSurl}${Font_color_suffix} \n Mã QR [IPv6]：${Red_font_prefix}${SSQRcode}${Font_color_suffix}"
	fi
}

View(){
	check_installed_status
	Read_config
	getipv4
	getipv6
	Link_QR
	clear && echo
	echo -e "Cấu hình Shadowsocks Rust:"
	echo -e "——————————————————————————————————"
	[[ "${ipv4}" != "IPv4_Error" ]] && echo -e " Địa chỉ: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
	[[ "${ipv6}" != "IPv6_Error" ]] && echo -e " Địa chỉ: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
	echo -e " Cổng: ${Green_font_prefix}${port}${Font_color_suffix}"
	echo -e " Mật khẩu: ${Green_font_prefix}${password}${Font_color_suffix}"
	echo -e " Mã hóa: ${Green_font_prefix}${cipher}${Font_color_suffix}"
	echo -e " TFO : ${Green_font_prefix}${tfo}${Font_color_suffix}"
	echo -e "——————————————————————————————————"
	[[ ! -z "${link_ipv4}" ]] && echo -e "${link_ipv4}"
	[[ ! -z "${link_ipv6}" ]] && echo -e "${link_ipv6}"
	echo -e "——————————————————————————————————"
	Before_Start_Menu
}

Status(){
	echo -e "${Info} Đang lấy nhật ký hoạt động của Shadowsocks Rust ……"
	echo -e "${Tip} Quay lại menu chính, nhấn phím q!"
	systemctl status ss-rust
	Start_Menu
}

Update_Shell(){
	echo -e "Phiên bản hiện tại là [ ${sh_ver} ], bắt đầu kiểm tra phiên bản mới nhất..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/xOS/Shadowsocks-Rust/master/ss-rust.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} Không lấy được phiên bản mới nhất!" && Start_Menu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "Đã phát hiện phiên bản mới [ ${sh_new_ver} ], có muốn cập nhật không? [Y/n]"
		read -p "(Mặc định: y)：" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -O ss-rust.sh --no-check-certificate https://raw.githubusercontent.com/xOS/Shadowsocks-Rust/master/ss-rust.sh && chmod +x ss-rust.sh
			echo -e "Script đã được cập nhật lên phiên bản mới nhất [ ${sh_new_ver} ]!"
			echo -e "Sẽ chạy script mới sau 3 giây"
            sleep 3s
            bash ss-rust.sh
		else
			echo && echo "	Đã hủy bỏ..." && echo
            sleep 3s
            Start_Menu
		fi
	else
		echo -e "Phiên bản hiện tại đã là phiên bản mới nhất [ ${sh_new_ver} ]!"
		sleep 3s
        Start_Menu
	fi
	sleep 3s
    	bash ss-rust.sh
}

Before_Start_Menu() {
    echo && echo -n -e "${yellow}* Nhấn Enter để quay lại menu chính *${plain}" && read temp
    Start_Menu
}

Start_Menu(){
clear
check_root
check_sys
sysArch
action=$1
	echo && echo -e "  
==================================
Script quản lý Shadowsocks Rust ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==================================
 ${Green_font_prefix} 0.${Font_color_suffix} Cập nhật script
——————————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} Cài đặt Shadowsocks Rust
 ${Green_font_prefix} 2.${Font_color_suffix} Cập nhật Shadowsocks Rust
 ${Green_font_prefix} 3.${Font_color_suffix} Gỡ cài đặt Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix} 4.${Font_color_suffix} Khởi động Shadowsocks Rust
 ${Green_font_prefix} 5.${Font_color_suffix} Dừng Shadowsocks Rust
 ${Green_font_prefix} 6.${Font_color_suffix} Khởi động lại Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix} 7.${Font_color_suffix} Thiết lập cấu hình
 ${Green_font_prefix} 8.${Font_color_suffix} Xem cấu hình
 ${Green_font_prefix} 9.${Font_color_suffix} Xem trạng thái hoạt động
——————————————————————————————————
 ${Green_font_prefix} 10.${Font_color_suffix} Thoát script
==================================" && echo
	if [[ -e ${FILE} ]]; then
		check_status
		if [[ "$status" == "running" ]]; then
			echo -e " Trạng thái hiện tại: ${Green_font_prefix}Đã cài đặt${Font_color_suffix} và ${Green_font_prefix}Đang chạy${Font_color_suffix}"
		else
			echo -e " Trạng thái hiện tại: ${Green_font_prefix}Đã cài đặt${Font_color_suffix} nhưng ${Red_font_prefix}Không chạy${Font_color_suffix}"
		fi
	else
		echo -e " Trạng thái hiện tại: ${Red_font_prefix}Chưa cài đặt${Font_color_suffix}"
	fi
	echo
	read -e -p " Vui lòng nhập số [0-10]：" num
	case "$num" in
		0)
		Update_Shell
		;;
		1)
		Install
		;;
		2)
		Update
		;;
		3)
		Uninstall
		;;
		4)
		Start
		;;
		5)
		Stop
		;;
		6)
		Restart
		;;
		7)
		Set
		;;
		8)
		View
		;;
		9)
		Status
		;;
		10)
		exit 1
		;;
		*)
		echo "Vui lòng nhập số hợp lệ [0-10]"
		;;
	esac
}
Start_Menu