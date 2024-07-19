#!/bin/sh

# AWG consts
AMNEZIA_MANAGER_AWG_MessageInitiationSize=148; AMNEZIA_MANAGER_AWG_MessageResponseSize=92

#countConfigurations() {
#    AWG_MANAGER_CONFIGURATION_COUNT=0
#    if [ -d $AWG_MANAGER_DIR ]
#    then
#        AWG_MANAGER_CONFIGURATION_COUNT=$(find $AWG_MANAGER_DIR -name ".awgc" | wc -l)
#    fi
#}


ensureDirExist() {
    [ -d $AM_Dir ] || mkdir -m 600 -p $AM_Dir
}

downloadFile() {
    wget -nv -P $AM_TargetDir $AM_SourcePath
}

downloadServerFile() {
    AM_SourcePath=$AMNEZIA_MANAGER_SCRIPTS_UPSTREAM/$(basename $AM_FilePath)
    AM_TargetDir=$(dirname $AM_FilePath)
    downloadFile
}

runServerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_SCRIPTS_DIR/$AM_ScriptName;
    if [ ! -e $AM_ScriptPath ]; then AM_FilePath=$AM_ScriptPath; downloadServerFile; fi
    . $AM_ScriptPath
}

downloadServerContainerFile() {
    AM_SourcePath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_UPSTREAM/$(basename $AM_FilePath)
    AM_TargetDir=$(dirname $AM_FilePath)
    downloadFile
}

runServerContainerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$AM_ScriptName;
    if [ ! -e $AM_ScriptPath ]; then AM_FilePath=$AM_ScriptPath; downloadServerContainerFile; fi
    . $AM_ScriptPath
}

replaceVars() {
    sed -i s/\$WIREGUARD_SUBNET_IP/$WIREGUARD_SUBNET_IP/ $AM_RV_Path
    sed -i s/\$WIREGUARD_SUBNET_CIDR/$WIREGUARD_SUBNET_CIDR/ $AM_RV_Path
    sed -i s/\$AWG_SERVER_PORT/$AWG_SERVER_PORT/ $AM_RV_Path
    sed -i s/\$JUNK_PACKET_COUNT/$JUNK_PACKET_COUNT/ $AM_RV_Path
    sed -i s/\$JUNK_PACKET_MIN_SIZE/$JUNK_PACKET_MIN_SIZE/ $AM_RV_Path
    sed -i s/\$JUNK_PACKET_MAX_SIZE/$JUNK_PACKET_MAX_SIZE/ $AM_RV_Path
    sed -i s/\$INIT_PACKET_JUNK_SIZE/$INIT_PACKET_JUNK_SIZE/ $AM_RV_Path
    sed -i s/\$RESPONSE_PACKET_JUNK_SIZE/$RESPONSE_PACKET_JUNK_SIZE/ $AM_RV_Path
    sed -i s/\$INIT_PACKET_MAGIC_HEADER/$INIT_PACKET_MAGIC_HEADER/ $AM_RV_Path
    sed -i s/\$RESPONSE_PACKET_MAGIC_HEADER/$RESPONSE_PACKET_MAGIC_HEADER/ $AM_RV_Path
    sed -i s/\$UNDERLOAD_PACKET_MAGIC_HEADER/$UNDERLOAD_PACKET_MAGIC_HEADER/ $AM_RV_Path
    sed -i s/\$TRANSPORT_PACKET_MAGIC_HEADER/$TRANSPORT_PACKET_MAGIC_HEADER/ $AM_RV_Path
}

uploadDockerContainerFile() {
    AM_ReplacePath=$AMNEZIA_MANAGER_TEMP_DIR/$(basename $AM_SourcePath)
    cp -f $AM_SourcePath $AM_ReplacePath
    AM_RV_Path=$AM_ReplacePath; replaceVars

    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME mkdir -p $(dirname $AM_TargetPath)
    if [ $AM_OverwriteMode = "overwrite" ]; then
        docker cp $AM_ReplacePath $AMNEZIA_MANAGER_CONTAINER_NAME:$AM_TargetPath
    else
        docker cp $AM_ReplacePath $AMNEZIA_MANAGER_CONTAINER_NAME:/tmp/tmp.tmp
        docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "cat /tmp/tmp.tmp $AM_TargetPath"
    fi

    #rm -f $AM_ReplacePath
}

removeDockerContainerFile() {
    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME rm $AM_TargetPath
}

runDockerContainerScript() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$AM_ScriptName
    if [ ! -e $AM_ScriptPath ]; then AM_FilePath=$AM_ScriptPath; downloadServerContainerFile; fi
    AM_SourcePath=$AM_ScriptPath;
    AM_TargetPath=/opt/amnezia/$AM_ScriptName;
    AM_OverwriteMode="overwrite"; uploadDockerContainerFile
    docker exec -i $AMNEZIA_MANAGER_CONTAINER_NAME bash $AM_TargetPath
    removeDockerContainerFile
}

installDockerWorker() {
    AM_ScriptName=install_docker.sh; runServerScript
}

prepareHostWorker() {
    AM_ScriptName=prepare_host.sh; runServerScript
}

buildContainerWorker() {
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/Dockerfile
    if [ ! -e $AM_ScriptPath ]; then AM_FilePath=$AM_ScriptPath; downloadServerContainerFile; fi
    AM_ScriptName=build_container.sh; runServerScript
}

runContainerWorker() {
    AM_ScriptName=run_container.sh; runServerContainerScript
}

configureContainerWorker() {
    AM_ScriptName=configure_container.sh; runDockerContainerScript
    #updateContainerConfigAfterInstallation
}

startupContainerWorker() {
    AM_ScriptName=start.sh
    AM_ScriptPath=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR/$AM_ScriptName
    if [ ! -e $AM_ScriptPath ]; then AM_FilePath=$AM_ScriptPath; downloadServerContainerFile; fi
    AM_SourcePath=$AM_ScriptPath;
    AM_TargetPath=/opt/amnezia/$AM_ScriptName;
    AM_OverwriteMode="overwrite"; uploadDockerContainerFile
    docker exec -d $AMNEZIA_MANAGER_CONTAINER_NAME sh -c "chmod a+x /opt/amnezia/$AM_ScriptName && /opt/amnezia/$AM_ScriptName"
}

setupContainer() {
    installDockerWorker
    prepareHostWorker
    buildContainerWorker
    runContainerWorker
    configureContainerWorker
    #setupServerFirewall
    startupContainerWorker
}

addAmneziaWGdocker() {
    AMNEZIA_MANAGER_CONTAINER_TYPE=docker
    AMNEZIA_MANAGER_CONTAINER_TEMPLATE=awg
    AMNEZIA_MANAGER_CONTAINER_NAME=amnezia-${AMNEZIA_MANAGER_CONTAINER_TEMPLATE}0
    AMNEZIA_MANAGER_CONTAINER_CONFIG=$AMNEZIA_MANAGER_CONFIGURATIONS_DIR/$AMNEZIA_MANAGER_CONTAINER_NAME.conf
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR=$AMNEZIA_MANAGER_SCRIPTS_DIR/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE
    AMNEZIA_MANAGER_CONTAINER_SCRIPTS_UPSTREAM=$AMNEZIA_MANAGER_SCRIPTS_UPSTREAM/$AMNEZIA_MANAGER_CONTAINER_TEMPLATE

    AM_Dir=$AMNEZIA_MANAGER_CONTAINER_SCRIPTS_DIR; ensureDirExist
    
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
}

removeConfiguration() {
    CONTAINER_NAME=$AMNEZIA_MANAGER_CONTAINER_NAME

    AM_ScriptName=remove_container.sh; runServerScript

    rm -f $AMNEZIA_MANAGER_CONTAINER_CONFIG
}

removeConfigurations() {
    AM_ScriptName=remove_all_containers.sh; runServerScript

    rm -f $AMNEZIA_MANAGER_CONFIGURATIONS_DIR/*.conf
}

readMenuOption() {
    read -rp "Select an option [${AM_MenuFrom}-${AM_MenuTo}]: " AM_MenuOption
}

getMenuOption() {
    success="false"
    while [ $success != "true" ]; do
        readMenuOption
        case $AM_MenuOption in
            [1-9]) if [ $AM_MenuOption -ge $AM_MenuFrom -a $AM_MenuOption -le $AM_MenuTo ]; then success="true"; fi ;;
            1[0-9]) if [ $AM_MenuOption -ge $AM_MenuFrom -a $AM_MenuOption -le $AM_MenuTo ]; then success="true"; fi ;;
            2[0-9]) if [ $AM_MenuOption -ge $AM_MenuFrom -a $AM_MenuOption -le $AM_MenuTo ]; then success="true"; fi ;;
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
    AM_MenuFrom=1; AM_MenuTo=2; getMenuOption
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
    echo "   1) Remove Configuration"
    AM_MenuFrom=1; AM_MenuTo=1; getMenuOption
    case $AM_MenuOption in
        1) removeConfiguration ;;
    esac
}

mainMenu() {
    echo "Amnezia server manager (https://github.com/romikb/amnezia-manager)"
    echo "Existing configurations:"
    AM_ConfigurationsCount=0
    if [ $(find $AMNEZIA_MANAGER_CONFIGURATIONS_DIR -name "*.conf" | wc -l) -eq 0 ]; then
        echo "   None"
    else
        listConfigurations
    fi
    echo "Other options:"
    if [ $AM_ConfigurationsCount -ne 0 ]; then
        AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
        echo "   $AM_ConfigurationsCount) Remove All Configurations"
        eval "AM_Configuration$AM_ConfigurationsCount"=RemoveConfigurations
    fi
    AM_ConfigurationsCount=$(expr $AM_ConfigurationsCount + 1)
    echo "   $AM_ConfigurationsCount) Add Configuration"
    eval "AM_Configuration$AM_ConfigurationsCount"=AddConfiguration
    AM_MenuFrom=1; AM_MenuTo=$AM_ConfigurationsCount; getMenuOption
    
    eval AM_Configuration="\$AM_Configuration$AM_MenuOption"
    case $AM_Configuration in
        RemoveConfigurations) removeConfigurations ;;
        AddConfiguration) addConfigurationMenu ;;
        *) configurationMenu ;;
    esac
}

[ ! -z "$AMNEZIA_MANAGER_ROOT" ] && [ -d "$AMNEZIA_MANAGER_ROOT" ] || AMNEZIA_MANAGER_ROOT=/var/opt/amnezia-manager

AMNEZIA_MANAGER_CONFIGURATIONS_DIR=/etc/opt/amnezia-manager
AMNEZIA_MANAGER_DIR=/var/opt/amnezia-manager
AMNEZIA_MANAGER_TEMP_DIR=/var/opt/amnezia-manager/temp
AMNEZIA_MANAGER_SCRIPTS_DIR=/var/opt/amnezia-manager/server_scripts
AMNEZIA_MANAGER_SCRIPTS_UPSTREAM=https://raw.githubusercontent.com/amnezia-vpn/amnezia-client/dev/client/server_scripts

AM_Dir=$AMNEZIA_MANAGER_CONFIGURATIONS_DIR; ensureDirExist
AM_Dir=$AMNEZIA_MANAGER_DIR; ensureDirExist
AM_Dir=$AMNEZIA_MANAGER_TEMP_DIR; ensureDirExist
AM_Dir=$AMNEZIA_MANAGER_SCRIPTS_DIR; ensureDirExist

mainMenu
