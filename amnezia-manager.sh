#!/bin/sh

RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Main consts
AMNEZIA_MANAGER_CONFIGURATIONS_DIR=/etc/opt/amnezia-manager
AMNEZIA_MANAGER_DIR=/var/opt/amnezia-manager
AMNEZIA_MANAGER_TEMP_DIR=/var/opt/amnezia-manager/temp
AMNEZIA_MANAGER_SCRIPTS_DIR=/var/opt/amnezia-manager/server_scripts
AMNEZIA_MANAGER_SCRIPTS_UPSTREAM=https://raw.githubusercontent.com/amnezia-vpn/amnezia-client/dev/client/server_scripts

# Dependent consts
AMNEZIA_MANAGER_CONFIGURATIONS_PARAMS=$AMNEZIA_MANAGER_CONFIGURATIONS_DIR/params

# AWG consts
AMNEZIA_MANAGER_AWG_MessageInitiationSize=148;
AMNEZIA_MANAGER_AWG_MessageResponseSize=92
AMNEZIA_MANAGER_AWG_ServerConfigPath=/opt/amnezia/awg/wg0.conf

#countConfigurations() {
#    AWG_MANAGER_CONFIGURATION_COUNT=0
#    if [ -d $AWG_MANAGER_DIR ]
#    then
#        AWG_MANAGER_CONFIGURATION_COUNT=$(find $AWG_MANAGER_DIR -name ".awgc" | wc -l)
#    fi
#}


# 1 - Dir
ensureDirExist() {
    [ -d $1 ] || mkdir -m 600 -p $1
}

# 1 - FileName or FilePath (basename used)
# return TempPath
getTempPath() {
    AM_LocalTempPath=$AMNEZIA_MANAGER_TEMP_DIR/$(basename $1).$(shuf -i0-999 -n1)
    while [ -e $AM_LocalTempPath ]; do AM_LocalTempPath=$AMNEZIA_MANAGER_TEMP_DIR/$(basename $1).$(shuf -i0-999 -n1); done
    echo $AM_LocalTempPath
}

# 1 - SourceUrl
# 2 - TargetDir
downloadFile() {
    wget -nv -P $2 $1
}

# 1 - TargetPath
downloadServerFile() {
    downloadFile $AMNEZIA_MANAGER_SCRIPTS_UPSTREAM/$(basename $1) $(dirname $1)
}

# 1 - ScriptName
runServerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_SCRIPTS_DIR/$1;
    if [ ! -e $AM_ScriptPath ]; then downloadServerFile $AM_ScriptPath; fi
    . $AM_ScriptPath
}

# 1 - TargetPath
downloadServerContainerFile() {
    if [ ! -e $1 ]; then downloadFile $AMNEZIA_MANAGER_CONTAINER_SCRIPTS_UPSTREAM/$(basename $1) $(dirname $1); fi
}

# 1 - ScriptName
runServerContainerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$1;
    downloadServerContainerFile $AM_ScriptPath
    . $AM_ScriptPath
}

# 1 - Path
replaceVars() {
    sed -i s/\$WIREGUARD_SUBNET_IP/$WIREGUARD_SUBNET_IP/ $1
    sed -i s/\$WIREGUARD_SUBNET_CIDR/$WIREGUARD_SUBNET_CIDR/ $1
    sed -i s/\$AWG_SERVER_PORT/$AWG_SERVER_PORT/ $1
    sed -i s/\$JUNK_PACKET_COUNT/$JUNK_PACKET_COUNT/ $1
    sed -i s/\$JUNK_PACKET_MIN_SIZE/$JUNK_PACKET_MIN_SIZE/ $1
    sed -i s/\$JUNK_PACKET_MAX_SIZE/$JUNK_PACKET_MAX_SIZE/ $1
    sed -i s/\$INIT_PACKET_JUNK_SIZE/$INIT_PACKET_JUNK_SIZE/ $1
    sed -i s/\$RESPONSE_PACKET_JUNK_SIZE/$RESPONSE_PACKET_JUNK_SIZE/ $1
    sed -i s/\$INIT_PACKET_MAGIC_HEADER/$INIT_PACKET_MAGIC_HEADER/ $1
    sed -i s/\$RESPONSE_PACKET_MAGIC_HEADER/$RESPONSE_PACKET_MAGIC_HEADER/ $1
    sed -i s/\$UNDERLOAD_PACKET_MAGIC_HEADER/$UNDERLOAD_PACKET_MAGIC_HEADER/ $1
    sed -i s/\$TRANSPORT_PACKET_MAGIC_HEADER/$TRANSPORT_PACKET_MAGIC_HEADER/ $1

    sed -i s/\$SERVER_IP_ADDRESS/$SERVER_IP_ADDRESS/ $1
}

downloadDockerContainerFile() {
    docker cp $AMNEZIA_MANAGER_CONTAINER_NAME:$AM_SourcePath $AM_TargetPath
}

# 1 - SourcePath
# 2 - TargetPath
# 3 - OverwriteMode: "overwrite" | "append"
uploadDockerContainerFile() {
    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME mkdir -p $(dirname $2)
    if [ $3 = "overwrite" ]; then
        docker cp $1 $AMNEZIA_MANAGER_CONTAINER_NAME:$2
    elif [ $3 = "append" ]; then
        docker cp $1 $AMNEZIA_MANAGER_CONTAINER_NAME:/tmp/tmp.tmp
        docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "cat /tmp/tmp.tmp >> $2"
    fi
}

# 1 - Path
removeDockerContainerFile() {
    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME rm $1
}

runDockerContainerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$AM_ScriptName
    downloadServerContainerFile $AM_ScriptPath

    AM_TempPath=$(getTempPath $AM_ScriptPath)
    cp -f $AM_ScriptPath $AM_TempPath
    replaceVars $AM_TempPath

    AM_TargetPath=/opt/amnezia/$AM_ScriptName;
    uploadDockerContainerFile $AM_TempPath $AM_TargetPath "overwrite"
    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME bash $AM_TargetPath
    removeDockerContainerFile $AM_TargetPath

    rm $AM_TempPath
}

installDockerWorker() {
    runServerScript install_docker.sh
}

prepareHostWorker() {
    runServerScript prepare_host.sh
}

removeContainer() {
    runServerScript remove_container.sh
}

buildContainerWorker() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/Dockerfile
    downloadServerContainerFile $AM_ScriptPath
    runServerScript build_container.sh
}

runContainerWorker() {
    runServerContainerScript run_container.sh
}

configureContainerWorker() {
    AM_ScriptName=configure_container.sh; runDockerContainerScript
    #updateContainerConfigAfterInstallation
}

setupServerFirewall() {
    runServerScript setup_host_firewall.sh
}

startupContainerWorker() {
    AM_ScriptName=start.sh
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$AM_ScriptName
    downloadServerContainerFile $AM_ScriptPath

    AM_TempPath=$(getTempPath $AM_ScriptPath)
    cp -f $AM_ScriptPath $AM_TempPath
    replaceVars $AM_TempPath

    AM_TargetPath=/opt/amnezia/$AM_ScriptName;
    uploadDockerContainerFile $AM_TempPath $AM_TargetPath "overwrite"
    docker exec -d $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "chmod a+x $AM_TargetPath && $AM_TargetPath"

    rm $AM_TempPath
}

setupContainer() {
    installDockerWorker
    prepareHostWorker
    removeContainer
    buildContainerWorker
    runContainerWorker
    configureContainerWorker
    setupServerFirewall
    startupContainerWorker
}

replaceAmneziaWGdockerVars() {
    sed -i s:\$WIREGUARD_CLIENT_PRIVATE_KEY:$WIREGUARD_CLIENT_PRIVATE_KEY: $1
    sed -i s:\$WIREGUARD_CLIENT_IP:$WIREGUARD_CLIENT_IP: $1
    sed -i s:\$WIREGUARD_SERVER_PUBLIC_KEY:$WIREGUARD_SERVER_PUBLIC_KEY: $1
    sed -i s:\$WIREGUARD_PSK:$WIREGUARD_PSK: $1

    sed -i s/\$PRIMARY_DNS/$PRIMARY_DNS/ $1
    sed -i s/\$SECONDARY_DNS/$SECONDARY_DNS/ $1
}

createConfigAmneziaWGdocker() {
    AM_ClientTemplatePath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/template.conf
    downloadServerContainerFile $AM_ClientTemplatePath
    
    AM_ServerTempFile=$(getTempPath $AMNEZIA_MANAGER_AWG_ServerConfigPath)
    AM_ClientTempPath=$(getTempPath $AM_ClientTemplatePath)
    
    cp -f $AM_ClientTemplatePath $AM_ClientTempPath
    replaceVars $AM_ClientTempPath

    AM_ServerConfigAllowedIPs=$(docker exec $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "grep AllowedIPs $AMNEZIA_MANAGER_AWG_ServerConfigPath")
    AM_ClientPrivateKey=$(docker exec $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "wg genkey")
    AM_ClientPublicKey=$(docker exec $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "echo $AM_ClientPrivateKey | wg pubkey")
    AM_ServerPublicKey=$(docker exec $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "cat /opt/amnezia/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE/wireguard_server_public_key.key")
    AM_PresharedKey=$(docker exec $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "cat /opt/amnezia/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE/wireguard_psk.key")

    AM_SubnetPrefixWithDot=${WIREGUARD_SUBNET_IP%.*}.
    AM_NextIp=2
    AM_ClientAddress=$AM_SubnetPrefixWithDot$AM_NextIp
    while echo $AM_ServerConfigAllowedIPs | grep -Fq $AM_ClientAddress $AM_TargetPath && [ $AM_NextIp -le 254 ]; do
        AM_NextIp=$(expr $AM_NextIp + 1)
        AM_ClientAddress=$AM_SubnetPrefixWithDot$AM_NextIp
    done

    WIREGUARD_CLIENT_PRIVATE_KEY=$AM_ClientPrivateKey
    WIREGUARD_CLIENT_IP=$AM_ClientAddress
    WIREGUARD_SERVER_PUBLIC_KEY=$AM_ServerPublicKey
    WIREGUARD_PSK=$AM_PresharedKey
    PRIMARY_DNS=$PRIMARY_SERVER_DNS
    SECONDARY_DNS=$SECONDARY_SERVER_DNS

    echo "[Peer]
PublicKey = $AM_ClientPublicKey
PresharedKey = $AM_PresharedKey
AllowedIPs = $AM_ClientAddress/32" > $AM_ServerTempFile

    uploadDockerContainerFile $AM_ServerTempFile $AMNEZIA_MANAGER_AWG_ServerConfigPath "append"
    sudo docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME bash -c "wg syncconf wg0 <(wg-quick strip $AMNEZIA_MANAGER_AWG_ServerConfigPath)"

    replaceAmneziaWGdockerVars $AM_ClientTempPath

    echo ""
    echo "${GREEN}Here is your client config file as text:${NC}"
    echo ""
    cat $AM_ClientTempPath
    echo ""

  	# Generate QR code if qrencode is installed
    if command -v qrencode > /dev/null; then
		echo "${GREEN}Here is your client config file as a QR Code:${NC}"
		echo ""
        qrencode -t ansiutf8 -l L < $AM_ClientTempPath
		echo ""
	fi
}

addAmneziaWGdocker() {
    AMNEZIA_MANAGER_CONTAINER_TYPE=docker
    AMNEZIA_MANAGER_CONTAINER_TEMPLATE=awg
    AMNEZIA_MANAGER_CONTAINER_NAME=amnezia-${AMNEZIA_MANAGER_CONTAINER_TEMPLATE}0
    AMNEZIA_MANAGER_CONTAINER_CONFIG=$AMNEZIA_MANAGER_CONFIGURATIONS_DIR/$AMNEZIA_MANAGER_CONTAINER_NAME.conf
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR=$AMNEZIA_MANAGER_SCRIPTS_DIR/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_UPSTREAM=$AMNEZIA_MANAGER_SCRIPTS_UPSTREAM/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE

    ensureDirExist $AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR
    
    # GenerateContainerConfig

    AM_ConfigSubnetAddress=10.8.1.0
    AM_ConfigSubnetCidr=24

    AM_ConfigPort=$(shuf -i30000-50000 -n1)
    AM_ConfigJunkPacketCount=$(shuf -i3-10 -n1)
    AM_ConfigJunkPacketMinSize=50
    AM_ConfigJunkPacketMaxSize=1000;

    AM_S1=$(shuf -i15-150 -n1)
    AM_S2=$(shuf -i15-150 -n1)
    while [ $(expr $AM_S1 + $AMNEZIA_MANAGER_AWG_MessageInitiationSize) -eq $(expr $AM_S2 + $AMNEZIA_MANAGER_AWG_MessageResponseSize) ]; do
        AM_S2=$(shuf -i15-150 -n1)
    done

    AM_ConfigInitPacketJunkSize=$AM_S1
    AM_ConfigResponsePacketJunkSize=$AM_S2

    AM_H1=$(shuf -i5-2147483647 -n1)
    AM_H2=$(shuf -i5-2147483647 -n1)
    while [ $AM_H1 -eq $AM_H2 ]; do
        AM_H2=$(shuf -i5-2147483647 -n1)
    done
    AM_H3=$(shuf -i5-2147483647 -n1)
    while [ $AM_H1 -eq $AM_H3 -o $AM_H2 -eq $AM_H3 ]; do
        AM_H3=$(shuf -i5-2147483647 -n1)
    done
    AM_H4=$(shuf -i5-2147483647 -n1)
    while [ $AM_H1 -eq $AM_H4 -o $AM_H2 -eq $AM_H4 -o $AM_H3 -eq $AM_H4 ]; do
        AM_H4=$(shuf -i5-2147483647 -n1)
    done

    AM_ConfigInitPacketMagicHeader=$AM_H1
    AM_ConfigResponsePacketMagicHeader=$AM_H2
    AM_ConfigUnderloadPacketMagicHeader=$AM_H3
    AM_ConfigTransportPacketMagicHeader=$AM_H4

    echo "AMNEZIA_MANAGER_CONTAINER_TYPE=$AMNEZIA_MANAGER_CONTAINER_TYPE
AMNEZIA_MANAGER_CONTAINER_TEMPLATE=$AMNEZIA_MANAGER_CONTAINER_TEMPLATE
AMNEZIA_MANAGER_CONTAINER_NAME=$AMNEZIA_MANAGER_CONTAINER_NAME
WIREGUARD_SUBNET_IP=$AM_ConfigSubnetAddress
WIREGUARD_SUBNET_CIDR=$AM_ConfigSubnetCidr
AWG_SERVER_PORT=$AM_ConfigPort
JUNK_PACKET_COUNT=$AM_ConfigJunkPacketCount
JUNK_PACKET_MIN_SIZE=$AM_ConfigJunkPacketMinSize
JUNK_PACKET_MAX_SIZE=$AM_ConfigJunkPacketMaxSize
INIT_PACKET_JUNK_SIZE=$AM_ConfigInitPacketJunkSize
RESPONSE_PACKET_JUNK_SIZE=$AM_ConfigResponsePacketJunkSize
INIT_PACKET_MAGIC_HEADER=$AM_ConfigInitPacketMagicHeader
RESPONSE_PACKET_MAGIC_HEADER=$AM_ConfigResponsePacketMagicHeader
UNDERLOAD_PACKET_MAGIC_HEADER=$AM_ConfigUnderloadPacketMagicHeader
TRANSPORT_PACKET_MAGIC_HEADER=$AM_ConfigTransportPacketMagicHeader" > $AMNEZIA_MANAGER_CONTAINER_CONFIG

    . $AMNEZIA_MANAGER_CONTAINER_CONFIG

    CONTAINER_NAME=$AMNEZIA_MANAGER_CONTAINER_NAME
    DOCKERFILE_FOLDER=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR

    setupContainer

    createConfigAmneziaWGdocker
}

addClient() {
    createConfigAmneziaWGdocker 11 22 33
}

removeConfiguration() {
    CONTAINER_NAME=$AMNEZIA_MANAGER_CONTAINER_NAME

    removeContainer

    rm -f $AMNEZIA_MANAGER_CONTAINER_CONFIG
}

removeConfigurations() {
    runServerScript remove_all_containers.sh

    rm -f $AMNEZIA_MANAGER_CONFIGURATIONS_DIR/*.conf
}

# 1 - From
# 2 - To
# return $AM_MenuOption
readMenuOption() {
    read -rp "Select an option [$1-$2]: " AM_MenuOption
}

# 1 - From
# 2 - To
getMenuOption() {
    success="false"
    while [ $success != "true" ]; do
        readMenuOption $1 $2
        case $AM_MenuOption in
            [1-9]) if [ $AM_MenuOption -ge $1 -a $AM_MenuOption -le $2 ]; then success="true"; fi ;;
            1[0-9]) if [ $AM_MenuOption -ge $1 -a $AM_MenuOption -le $2 ]; then success="true"; fi ;;
            2[0-9]) if [ $AM_MenuOption -ge $1 -a $AM_MenuOption -le $2 ]; then success="true"; fi ;;
        esac
    done
}

listConfigurations() {
    for AM_Path in $AMNEZIA_MANAGER_CONFIGURATIONS_DIR/*.conf; do
        AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
        . $AM_Path
        echo "   $AM_ConfigurationsCount) $AMNEZIA_MANAGER_CONTAINER_NAME: $AMNEZIA_MANAGER_CONTAINER_TEMPLATE ($AMNEZIA_MANAGER_CONTAINER_TYPE)"
        eval "AM_Configuration$AM_ConfigurationsCount"=$AM_Path
    done
}

addConfigurationMenu() {
    echo "   1) Add AmneziaWG (native) - require about 2GB of free space for kernel module compilation)"
    echo "   2) Add AmneziaWG (docker)"
    getMenuOption 1 2
    case $AM_MenuOption in
        1) addAmneziaWGnative ;;
        2) addAmneziaWGdocker ;;
    esac
}

configurationMenu() {
    . $AM_Configuration
    AMNEZIA_MANAGER_CONTAINER_CONFIG=$AM_Configuration
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR=$AMNEZIA_MANAGER_SCRIPTS_DIR/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_UPSTREAM=$AMNEZIA_MANAGER_SCRIPTS_UPSTREAM/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE
    
    echo "Name: $AMNEZIA_MANAGER_CONTAINER_NAME, Type: $AMNEZIA_MANAGER_CONTAINER_TEMPLATE ($AMNEZIA_MANAGER_CONTAINER_TYPE)"
    echo "   1) Add Client"
    echo "   2) Remove Configuration"
    getMenuOption 1 2
    case $AM_MenuOption in
        1) addClient ;;
        2) removeConfiguration ;;
    esac
}

basicSetup() {
    echo ""
    echo "We need a basic setup."
	echo "You can keep the default options and just press enter if you are ok with them."

  	# Detect public IPv4 or IPv6 address and pre-fill for the user
	SERVER_IP_ADDRESS=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	if [ -z $SERVER_IP_ADDRESS ]; then
		# Detect public IPv6 address
		SERVER_IP_ADDRESS=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi
	read -rp "Public IPv4 or IPv6 address or domain [$SERVER_IP_ADDRESS]: " input
    SERVER_IP_ADDRESS=${input:-$SERVER_IP_ADDRESS}

    PRIMARY_SERVER_DNS=1.1.1.1
    SECONDARY_SERVER_DNS=1.0.0.1

    echo "SERVER_IP_ADDRESS=$SERVER_IP_ADDRESS
PRIMARY_SERVER_DNS=$PRIMARY_SERVER_DNS
SECONDARY_SERVER_DNS=$SECONDARY_SERVER_DNS" > $AMNEZIA_MANAGER_CONFIGURATIONS_PARAMS
}

mainMenu() {
    echo ""
    echo "Existing configurations:"
    AM_ConfigurationsCount=0
    if [ $(find $AMNEZIA_MANAGER_CONFIGURATIONS_DIR -name "*.conf" | wc -l) -eq 0 ]; then
        echo "   None"
    else
        listConfigurations
    fi
    echo ""
    echo "Other options:"
    if [ $AM_ConfigurationsCount -ne 0 ]; then
        AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
        echo "   $AM_ConfigurationsCount) Remove All Configurations"
        eval "AM_Configuration$AM_ConfigurationsCount"=RemoveConfigurations
    else
        AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
        echo "   $AM_ConfigurationsCount) Basic Setup"
        eval "AM_Configuration$AM_ConfigurationsCount"=BasicSetup
    fi
    AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
    echo "   $AM_ConfigurationsCount) Add Configuration"
    eval "AM_Configuration$AM_ConfigurationsCount"=AddConfiguration
    echo ""
    getMenuOption 1 $AM_ConfigurationsCount
    
    eval AM_Configuration="\$AM_Configuration$AM_MenuOption"
    case $AM_Configuration in
        RemoveConfigurations) removeConfigurations ;;
        AddConfiguration) addConfigurationMenu ;;
        BasicSetup) basicSetup ;;
        *) configurationMenu ;;
    esac
}

isRoot() {
	if [ $(id -u) -ne 0 ]; then
		echo "You need to run this script as root"
		exit 1
	fi
}

#checkVirt() {
#	if [ "$(systemd-detect-virt)" = "openvz" ]; then
#		echo "OpenVZ is not supported"
#		exit 1
#	fi
#
#	if [ "$(systemd-detect-virt)" = "lxc" ]; then
#		echo "LXC is not supported"
#		exit 1
#	fi
#
#  	if [ "$(systemd-detect-virt)" = "wsl" ]; then
#		echo "WSL is not supported"
#		exit 1
#	fi
#}

#initialCheck() {
#	isRoot
#	checkVirt
#	checkOS
#}

isRoot

ensureDirExist $AMNEZIA_MANAGER_CONFIGURATIONS_DIR
ensureDirExist $AMNEZIA_MANAGER_DIR
ensureDirExist $AMNEZIA_MANAGER_TEMP_DIR
ensureDirExist $AMNEZIA_MANAGER_SCRIPTS_DIR

echo ""
echo "Amnezia server manager (https://github.com/romikb/amnezia-manager)"

if [ ! -e $AMNEZIA_MANAGER_CONFIGURATIONS_PARAMS ]; then basicSetup; else . $AMNEZIA_MANAGER_CONFIGURATIONS_PARAMS; fi

mainMenu
