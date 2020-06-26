#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

#====================================================
#	System Request:Debian 9+/Ubuntu 18.04+/Centos 7+
#	Author:	Miroku/h31105
#	Dscription: TLS-Shunt-Proxy&Trojan-Go Script
#	Version: 0.5
#	#	Official document:
# https://www.v2ray.com/
# https://github.com/p4gefau1t/trojan-go
# https://github.com/liberal-boy/tls-shunt-proxy
# https://www.docker.com/
# https://github.com/containrrr/watchtower
# https://github.com/portainer/portainer
# https://github.com/wulabing/V2Ray_ws-tls_bash_onekey
#====================================================

#fonts color
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
#GreenBG="\033[42;37m"
GreenBG="\033[42;36m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
WARN="${Yellow}[警告]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="0.5"
install_mode="None"
github_branch="master"
version_cmp="/tmp/version_cmp.tmp"
tsp_conf_dir="/etc/tls-shunt-proxy"
trojan_conf_dir="/etc/trojan-go"
v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx"
tsp_conf="${tsp_conf_dir}/config.yaml"
trojan_conf="${trojan_conf_dir}/config.json"
v2ray_conf="${v2ray_conf_dir}/config.json"
nginx_conf="${nginx_conf_dir}/nginx.conf"
nginx_dir="/etc/nginx"
web_dir="/home/wwwroot"
old_config_status="off"

#简易随机数
random_num=$((RANDOM % 12 + 4))
#生成伪装路径
camouflage="/$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})/"
THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)
source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

check_system() {
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi

    $INS install dbus
    systemctl stop firewalld
    systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"
    systemctl stop ufw
    systemctl disable ufw
    echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

is_root() {
    if [ 0 == $UID ]; then
        echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}
judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

chrony_install() {
    ${INS} -y install chrony
    judge "安装 chrony 时间同步服务 "
    timedatectl set-ntp true
    if [[ "${ID}" == "centos" ]]; then
        systemctl enable chronyd && systemctl restart chronyd
    else
        systemctl enable chrony && systemctl restart chrony
    fi
    judge "chronyd 启动 "
    timedatectl set-timezone Asia/Shanghai
    echo -e "${OK} ${GreenBG} 等待时间同步 ${Font}"
    sleep 10
    chronyc sourcestats -v
    chronyc tracking -v
    date
    read -rp "请确认时间是否准确,误差范围±3分钟(Y/N): " chrony_install
    [[ -z ${chrony_install} ]] && chrony_install="Y"
    case $chrony_install in
    [yY][eE][sS] | [yY])
        echo -e "${GreenBG} 继续安装 ${Font}"
        sleep 2
        ;;
    *)
        echo -e "${RedBG} 安装终止 ${Font}"
        exit 2
        ;;
    esac
}

dependency_install() {
    ${INS} install wget git lsof -y
    ${INS} -y install bc
    judge "安装 bc"
    ${INS} -y install unzip
    judge "安装 unzip"
    ${INS} -y install curl
    judge "安装 curl"
    ${INS} -y install wget
    judge "安装 wget"
    ${INS} -y install haveged
    #judge "haveged 安装"
    if [[ "${ID}" == "centos" ]]; then
        systemctl start haveged && systemctl enable haveged
        #judge "haveged 启动"
    else
        systemctl start haveged && systemctl enable haveged
        #judge "haveged 启动"
    fi
}

basic_optimization() {
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >>/etc/security/limits.conf
    echo '* hard nofile 65536' >>/etc/security/limits.conf
    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi
}

old_config_exist_check() {
    if [[ -f "$1" ]]; then
        echo -e "${OK} ${GreenBG} 检测到旧配置文件，自动备份旧文件配置 ${Font}"
        cp "$1" "$1.$(date +%Y%m%d%H)"
        echo -e "${OK} ${GreenBG} 已备份旧配置  ${Font}"
        old_config_status="on"
    else
        old_config_status="off"
    fi
}

info_extraction() {
    #关键字 目标文件 字符位置
    grep "$1" "$2" | awk -F "$3" '{print $2}'
}

domain_port_check() {
    read -rp "请输入TLS端口(默认443):" tspport
    [[ -z ${tspport} ]] && tspport="443"
    read -rp "请输入你的域名信息(例如:fk.gfw.com):" domain
    domain_ip=$(ping "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    local_ip=$(curl -4 ip.sb)
    echo -e "域名DNS解析IP：${domain_ip}"
    echo -e "本机IP: ${local_ip}"
    sleep 2
    if [[ $(echo "${local_ip}" | tr '.' '+' | bc) -eq $(echo "${domain_ip}" | tr '.' '+' | bc) ]]; then
        echo -e "${OK} ${GreenBG} 域名DNS解析IP 与 本机IP 匹配 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A 记录，否则将无法正常连接 ${Font}"
        echo -e "${Error} ${RedBG} 域名DNS解析IP 与 本机IP 不匹配 是否继续安装？（y/n）${Font}" && read -r install
        case $install in
        [yY][eE][sS] | [yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        echo -e "${OK} ${GreenBG} 5s 后将尝试自动 kill 占用进程 ${Font}"
        sleep 5
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
        sleep 1
    fi
}

service_status_check() {
    if systemctl is-active $1 &>/dev/null; then
        #echo "${OK} ${GreenBG} $1 已经启动 ${Font}"
        if systemctl is-enabled $1 &>/dev/null; then
            #echo "${OK} ${GreenBG} $1 是开机自启动项 ${Font}"
            service_status="OK"
        else
            echo -e "${WARN} ${Yellow} $1 不是开机自启动项 ${Font}"
            service_status="Warning"
            systemctl enable $1
            judge "设置 $1 为开机自启动"
        fi
    else
        echo -e "${Error} ${RedBG} $1 未启动 ${Font}"
        service_status="Error"
        echo -e "${Error} ${RedBG} 检测到 $1 服务异常，正在尝试修复 ${Font}"
        systemctl restart $1
        judge "尝试启动 $1 "
        sleep 5
        echo -e "${WARN} ${Yellow} 请重新执行脚本 ${Font}"
        exit 4
    fi
}

prereqcheck() {
    service_status_check docker
    if [[ -f ${tsp_conf} ]]; then
        service_status_check tls-shunt-proxy
    else
        echo -e "${Error} ${RedBG} TLS-Shunt-Proxy 配置异常，请尝试重新安装 ${Font}"
        exit 4
    fi
}

trojan_reset() {
    old_config_exist_check ${trojan_conf}
    rm -rf ${trojan_conf} && old_config_status="off"
    read -rp "请输入密码(Trojan-Go)，默认随机 :" tjpasswd
    [[ -z ${tjpasswd} ]] && tjpasswd=$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})
    judge "Trojan-Go 密码设置"
    echo -e "${OK} ${GreenBG} Trojan-Go 密码: ${tjpasswd} ${Font}"
    read -rp "请输入监听端口(Trojan-Go)，默认随机 :" tjport
    [[ -z ${tjport} ]] && tjport=$((RANDOM % 6666 + 10000))
    judge "Trojan-Go 监听端口设置"
    echo -e "${OK} ${GreenBG} Trojan-Go 监听端口为: $tjport ${Font}"
    mkdir -p $trojan_conf_dir
    cat >/etc/trojan-go/config.json <<-EOF
{
    "run_type": "server",
    "disable_http_check": true,
    "local_addr": "127.0.0.1",
    "local_port": ${tjport},
    "remote_addr": "1.1.1.1",
    "remote_port": 80,
    "fallback_addr": "1.1.1.1",
    "fallback_port": 443,
    "password": ["${tjpasswd}"],
    "transport_plugin": {
        "enabled": true,
        "type": "plaintext"
    }
}
EOF
    port_exist_check $tjport
    if [[ -f ${tsp_conf} ]]; then
        sed -i "/#Trojan-GO_Port/c \\      args: 127.0.0.1:${tjport} #Trojan-GO_Port" ${tsp_conf}
        judge "同步 Trojan-Go 配置设置"
        systemctl restart tls-shunt-proxy
        judge "TLS-Shunt-Proxy 应用设置"
        sleep 5
        service_status_check tls-shunt-proxy
    else
        echo -e "${Error} ${RedBG} TLS-Shunt-Proxy 配置异常，请重新安装 ${Font}"
        exit 4
    fi
}

v2ray_reset() {
    old_config_exist_check ${v2ray_conf}
    rm -rf ${v2ray_conf} && old_config_status="off"
    read -rp "请输入监听端口(V2Ray WS)，默认随机 :" v2port
    [[ -z ${v2port} ]] && v2port=$((RANDOM % 6666 + 20000))
    judge "V2Ray 监听端口设置"
    echo -e "${OK} ${GreenBG} V2Ray监听端口为 $v2port ${Font}"
    read -rp "请输入alterID（默认:10 仅允许填数字）:" alterID
    [[ -z ${alterID} ]] && alterID="10"
    judge "V2Ray alterID 设置"
    [ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
    judge "V2ray UUID 设置"
    echo -e "${OK} ${GreenBG} UUID:${UUID} ${Font}"
    judge "V2ray WSPATH 设置"
    echo -e "${OK} ${GreenBG} WSPATH: ${camouflage} ${Font}"
    mkdir -p $v2ray_conf_dir
    cat >$v2ray_conf_dir/config.json <<-EOF
{
    "log": {
        "access": "/var/log/v2ray/access.log",
        "error": "/var/log/v2ray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [
      {
        "port": ${v2port}, 
        "listen": "127.0.0.1", 
        "tag": "vmess-in", 
        "protocol": "vmess", 
        "settings": {
         "clients": [
            {
              "id": "${UUID}", 
             "alterId": ${alterID}
            }
          ]
        }, 
        "streamSettings": {
          "network": "ws", 
          "wsSettings": {
           "path": "${camouflage}"
          }
        }
      }
    ], 
    "outbounds": [
      {
        "protocol": "freedom", 
        "settings": { }, 
        "tag": "direct"
      }, 
      {
        "protocol": "blackhole", 
        "settings": { }, 
        "tag": "blocked"
      }
    ], 
    "dns": {
      "servers": [
        "https+local://1.1.1.1/dns-query",
	    "1.1.1.1",
	    "1.0.0.1",
	    "8.8.8.8",
	    "8.8.4.4",
	    "localhost"
      ]
    },
    "routing": {
      "domainStrategy": "IPOnDemand",
      "rules": [
        {
          "type": "field",
          "outboundTag": "blocked",
          "protocol": ["bittorrent"]
        },
        {
          "type": "field",
          "inboundTag": [
            "vmess-in"
          ],
          "outboundTag": "direct"
        }
      ]
    }
}
EOF
    port_exist_check $v2port
    if [[ -f ${tsp_conf} ]]; then
        sed -i "/#V2Ray_Port/c \\          args: 127.0.0.1:${port} #V2Ray_Port" ${tsp_conf}
        sed -i "/#V2Ray_WSPATH/c \\        - path: ${camouflage} #V2Ray_WSPATH" ${tsp_conf}
        judge "同步 V2Ray WS 配置设置"
        systemctl restart tls-shunt-proxy
        judge "TLS-Shunt-Proxy 应用设置"
        sleep 5
        service_status_check tls-shunt-proxy
    else
        echo -e "${Error} ${RedBG} TLS-Shunt-Proxy 配置异常，请重新安装 ${Font}"
        exit 4
    fi

}

web_camouflage() {
    ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
    rm -rf $web_dir
    mkdir -p $web_dir
    cd $web_dir || exit
    git clone https://github.com/h31105/LodeRunner_TotalRecall.git
    judge "Web 站点伪装"
}

install_docker() {
    ##if [[ "${ID}" == "centos" ]]; then
    ##    ${INS} -y remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    ##    ${INS} -y install yum-utils
    ##    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    ##else
    ##    ${INS} -y remove docker docker-engine docker.io containerd runc
    ##    ${INS} -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    ##    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    ##    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" && ${INS} update
    ##fi
    ##${INS} -y install docker-ce docker-ce-cli containerd.io
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    judge "安装 Docker "
    systemctl daemon-reload
    systemctl enable docker && systemctl restart docker
    judge "Docker 启动 "
}

install_tsp() {
    bash <(curl -L -s https://raw.githubusercontent.com/liberal-boy/tls-shunt-proxy/master/dist/install.sh)
    rm -rf $tsp_conf && old_config_status="off"
    cat >/etc/tls-shunt-proxy/config.yaml <<-EOF
listen: 0.0.0.0:${tspport} #TSP_Port
inboundbuffersize: 4
outboundbuffersize: 32
vhosts:
    - name: ${domain} #TSP_Domain
      tlsoffloading: true
      managedcert: true
      alpn: http/1.1
      protocols: tls12,tls13
      http:
        paths:
          - path: ${camouflage} #V2Ray_WSPATH
            handler: proxyPass
            args: 127.0.0.1:36280 #V2Ray_Port
          - path: /portainer/ #Portainer_PATH
            handler: proxyPass
            args: 127.0.0.1:9000 #Portainer_Port
          - path: /portainer/api/websocket/ #Portainer_API_PATH
            handler: proxyPass
            args: 127.0.0.1:9000 #Portainer_API_Port
        handler: fileServer
        args: ${web_dir} #伪装站
      default:
        handler: proxyPass
        args: 127.0.0.1:26666 #Trojan-GO_Port
EOF
    judge "安装 TLS-Shunt-Proxy"
    systemctl daemon-reload
    systemctl enable tls-shunt-proxy && systemctl restart tls-shunt-proxy
    judge "TLS-Shunt-Proxy 启动 "
}

install_trojan() {
    trojan_reset
    docker run -d --network host --name Trojan-Go --restart=always -v /etc/trojan-go:/etc/trojan-go teddysun/trojan-go
}

install_v2ray() {
    v2ray_reset
    docker run -d --network host --name V2Ray --restart=always -v /etc/v2ray:/etc/v2ray teddysun/v2ray
}

install_watchtower() {
    docker run -d --name WatchTower --restart=always -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower --cleanup
}

install_portainer() {
    docker volume create portainer_data
    docker run -d -p 127.0.0.1:9000:9000 --name Portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer
}

install_nginx() {
    mkdir /etc/nginx &&
        mkdir -p /usr/share/nginx/html &&
        docker run -d --network host --name Nginx --restart=always -v /etc/nginx/nginx.conf:/etc/nginx/nginx.conf -v /usr/share/nginx/html:/usr/share/nginx/html nginx
}

install_trojan_v2ray() {
    is_root
    check_system
    install_docker
    prereqcheck
    read -rp "请选择安装 Trojan-Go(T) / V2Ray WS(V) 或 共用分流(回车)，(T/V/回车):" install_mode
    [[ -z ${install_mode} ]] && install_mode="Both"
    case $install_mode in
    [tT]rojan | [tT])
        echo -e "${GreenBG} 开始安装 Trojan-Go ${Font}"
        install_mode="Trojan"
        sleep 3
        install_trojan
        ;;
    [vV]2[rR]ay | [vV])
        echo -e "${GreenBG} 开始安装 V2Ray WS ${Font}"
        install_mode="V2Ray"
        sleep 3
        install_v2ray
        ;;
    Both)
        echo -e "${GreenBG} 开始安装 Trojan-Go & V2Ray WS ${Font}"
        sleep 3
        install_trojan
        install_v2ray
        ;;
    *)
        echo -e "${RedBG} 请输入正确的字母(T/V/回车) ${Font}"
        ;;
    esac
}

install_tls_shunt_proxy() {
    is_root
    check_system
    dependency_install
    basic_optimization
    domain_port_check
    port_exist_check "${tspport}"
    old_config_exist_check "${tsp_conf}"
    web_camouflage
    install_tsp
}

bbr_boost_sh() {
    [ -f "tcp.sh" ] && rm -rf ./tcp.sh
    wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
}

update_sh() {
    ol_version=$(curl -L -s https://raw.githubusercontent.com/h31105/trojan_v2_docker_onekey/${github_branch}/deploy.sh | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')
    echo "$ol_version" >$version_cmp
    echo "$shell_version" >>$version_cmp
    if [[ "$shell_version" < "$(sort -rV $version_cmp | head -1)" ]]; then
        echo -e "${OK} ${GreenBG} 存在新版本，是否更新 [Y/N]? ${Font}"
        read -r update_confirm
        case $update_confirm in
        [yY][eE][sS] | [yY])
            wget -N --no-check-certificate https://raw.githubusercontent.com/h31105/trojan_v2_docker_onekey/${github_branch}/deploy.sh
            echo -e "${OK} ${GreenBG} 更新完成 ${Font}"
            exit 0
            ;;
        *) ;;

        esac
    else
        echo -e "${OK} ${GreenBG} 当前版本为最新版本 ${Font}"
    fi

}

maintain() {
    echo -e "${RedBG}该选项暂时无法使用（缺少依赖条件）${Font}"
    echo -e "${RedBG}$1${Font}"
    exit 0
}

list() {
    case $1 in
    uninstall)
        uninstall_all
        ;;
    boost)
        bbr_boost_sh
        ;;
    *)
        menu
        ;;
    esac
}

menu() {
    clear
    echo -e " TSP / NGINX / TROJAN-GO / V2RAY 容器化部署脚本 \n"
    echo -e "当前版本:${shell_version}\n"

    echo -e "————————————————————部署管理————————————————————"
    echo -e "${Green}1.${Font}  安装 TLS-Shunt-Proxy 分流器（证书自动管理）"
    echo -e "${Green}2.${Font}  安装 Trojan-Go / V2Ray WS "
    echo -e "${Green}3.${Font}  添加 WatchTower（容器自动更新）"
    echo -e "${Green}4.${Font}  添加 Portainer（容器管理）"
    echo -e "${Green}5.${Font}  添加 Nginx（Web网站）"
    echo -e "————————————————————配置变更————————————————————"
    echo -e "${Green}6.${Font}  变更 Troan-Go 密码"
    echo -e "${Green}7.${Font}  变更 V2Ray UUID / WSPATH"
    echo -e "${Green}8.${Font}  变更 TLS端口 / 域名"
    echo -e "————————————————————查看信息————————————————————"
    echo -e "${Green}9.${Font}  查看 Trojan-Go / V2Ray 配置信息"
    echo -e "————————————————————杂项管理————————————————————"
    echo -e "${Green}10.${Font} 安装 4合1 BBR 锐速脚本"
    echo -e "${Green}11.${Font} 升级 Docker / TLS-Shunt-Proxy"
    echo -e "${Green}12.${Font} 卸载 已安装的组件"
    echo -e "${Green}0.${Font}  退出脚本 "
    echo -e "————————————————————————————————————————————————\n"

    read -p "请输入数字 :" menu_num
    case "$menu_num" in
    1)
        install_tls_shunt_proxy
        ;;
    2)
        install_trojan_v2ray
        ;;
    3)
        install_watchtower
        ;;
    4)
        install_portainer
        ;;
    5)
        install_nginx
        ;;
    6)
        modify_trojan
        ;;
    7)
        modify_v2ray
        ;;
    8)
        modify_tsp
        ;;
    9)
        cat ${trojan_conf}
        cat ${v2ray_conf}
        ;;
    10)
        bbr_boost_sh
        ;;
    11)
        upgrade_docker
        upgrade_tsp
        ;;
    12)
        uninstall_all
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        ;;
    esac
}

update_sh
list "$1"