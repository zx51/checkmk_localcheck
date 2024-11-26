#!/bin/bash

# Variaveis DEFAULT
DIR_CACHE="."

#
# Funções de auxilio
#
function get_smart_info () {
    local block_device="$1"
    local file_cache=$(find $DIR_CACHE -name "smart_${block_device}.cache" -mtime -1 2>/dev/null)
    if [ -z "$file_cache" ]; then
        file_cache="${DIR_CACHE}/smart_${block_device}.cache"
        smartctl -a /dev/${block_device} &> $file_cache
    fi
    cat $file_cache
}

#
# Funções para coletar informações do smartctl
#
function get_health_status() {
    get_smart_info $1 | grep -i "SMART overall-health self-assessment test result" | awk -F: '{print $2}' | sed 's/\ \+//g'
}

function get_temperature() {
    get_smart_info $1 | grep -i "Temperature:" | awk '{print $2}'
}

function get_percentage_used() {
    get_smart_info $1 | grep -i "Percentage Used" | awk '{print $3}' | cut -d '%' -f1
}

function get_media_errors() {
    get_smart_info $1 | grep -i "Media and Data Integrity Errors" | cut -d':' -f2 | sed 's/\ \+//g'
}

# Função principal
function check_disk_health() {

    # Disco
    local block_device="$1"    

    # Variaveis do check_mk
    local cmk_status="0"
    local cmk_service_name="Check_SMART_Disk_${block_device}"
    local cmk_value_metrics="-"
    local cmk_status_detail="OK - Disk integrity"
    
    # Obtendo as informações do smartctl
    HEALTH=$(get_health_status "$block_device")
    TEMPERATURE=$(get_temperature "$block_device")
    PERCENT_USED=$(get_percentage_used "$block_device")
    MEDIA_ERRORS=$(get_media_errors "$block_device")

    # Verificando o estado de saúde do disco
    if [[ "$HEALTH" != "PASSED" ]]; then
        cmk_status_detail="CRITICAL - Disk health is $HEALTH"
        cmk_status="2"
    fi

    # Verificando a temperatura (exemplo: crítica se acima de 50°C)
    if [[ -n "$TEMPERATURE" && "$TEMPERATURE" -gt 50 ]]; then
        cmk_status_detail="CRITICAL - High temperature: $TEMPERATURE°C"
        cmk_status="2"
    fi

    # Verificando o percentual de uso do disco (exemplo: alerta se acima de 90%)
    if [[ -n "$PERCENT_USED" && "$PERCENT_USED" -gt 90 ]]; then
        cmk_status_detail="WARNING - Disk usage at $PERCENT_USED%"
        cmk_status="1"
    fi

    # Verificando erros de integridade
    if [[ -n "$MEDIA_ERRORS" && "$MEDIA_ERRORS" -gt 0 ]]; then
        cmk_status_detail="CRITICAL - Media/Data Integrity Errors: $MEDIA_ERRORS"
        cmk_status="2"
    fi

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics} ${cmk_status_detail}"
}

# Identifica quais discos estão conectados ao servidor
BLOCK_DEVICES="$(lsblk -n -d -o NAME | grep -v 'loop')"

for BLOCK_DEVICE in ${BLOCK_DEVICES}; do
    check_disk_health "$BLOCK_DEVICE"
done
# check_disk_health "nvme0n1"