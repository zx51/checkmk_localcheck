#!/bin/bash

# Configurações e threshold
DIR_CACHE="."
PERIOD_CACHE="1440" # Em minutos
TEMPERATURE_CRIT="50"
PERCENT_USED_CRIT="90"
MEDIA_ERRORS_CRIT="0"

#
# Gera arquivo de cache da consulta do smartctl
#
function get_smart_info_stric() {

    local block_device="$1"
    local cache_file="${DIR_CACHE}/smart_${block_device}_strict.cache"

    # Se o arquivo de cache não existir ou for mais antigo que 1 dia, coletamos os dados novamente
    if [ ! -f "$cache_file" ] || [ $(find "$cache_file" -mmin +${PERIOD_CACHE}) ]; then
        smartctl -a /dev/${block_device} > "$cache_file"
    fi

    cat "$cache_file"

}

function get_smart_info_general() {

    local block_device="$1"
    local cache_file="${DIR_CACHE}/smart_${block_device}_general.cache"

    # Se o arquivo de cache não existir ou for mais antigo que 1 dia, coletamos os dados novamente
    if [ ! -f "$cache_file" ] || [ $(find "$cache_file" -mmin +${PERIOD_CACHE}) ]; then
        smartctl -i /dev/${block_device} > "$cache_file"
    fi

    cat "$cache_file"

}

#
# Filtra e processa as informações da consulta, do smartctl, realizada por sensor de cada disco
#

# Traz informações genéricas sobre o dispositivo
function general_status() {

    local block_device="$1"
    local cmk_status="0"
    local cmk_service_name="S.M.A.R.T_Disk_${block_device}_General_Information"
    local cmk_value_metrics="-"
    local cmk_status_detail="General Information"

    while IFS= read -r line; do
        cmk_status_detail="${cmk_status_detail}\n${line}"
    done <<< "$(get_smart_info_general "$block_device")"

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics:=-} ${cmk_status_detail}"

}

# Verifica o estado de saúde do disco
function health_status() {

    local block_device="$1"
    local cmk_service_name="S.M.A.R.T_Disk_${block_device}_Health"
    local sensor_filter="SMART overall-health self-assessment test result"

    local HEALTH=$(get_smart_info_stric "$block_device" | grep -i "$sensor_filter" | awk -F: '{print $2}' | sed 's/\ \+//g')

    if [[ "$HEALTH" != "PASSED" ]]; then
        local cmk_status_detail="CRITICAL - Disk health is ${HEALTH}"
        local cmk_status="2"
    else
        local cmk_status_detail="OK - Disk integrity ${HEALTH}"
        local cmk_status="0"
    fi

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics:=-} ${cmk_status_detail}"

}

# Verifica a temperatura (exemplo: crítica se acima de 50°C)
function temperature_status() {

    local block_device="$1"
    local cmk_service_name="S.M.A.R.T_Disk_${block_device}_Temperature"
    local sensor_filter="Temperature:"

    local TEMPERATURE=$(get_smart_info_stric "$block_device" | grep -i "$sensor_filter" | awk '{print $2}')

    if [[ -n "$TEMPERATURE" && "$TEMPERATURE" -gt "$TEMPERATURE_CRIT" ]]; then
        local cmk_status_detail="CRITICAL - High temperature: ${TEMPERATURE}°C"
        local cmk_status="2"
    else
        local cmk_status_detail="OK - Normal temperature: ${TEMPERATURE}°C"
        local cmk_status="0"   
    fi

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics:=-} ${cmk_status_detail}"

}

# Verificando o percentual de uso do disco (exemplo: alerta se acima de 90%)
function percentage_used_status() {

    local block_device="$1"
    local cmk_service_name="S.M.A.R.T_Disk_${block_device}_Percentage_Used"
    local sensor_filter="Percentage Used:"

    local PERCENT_USED=$(get_smart_info_stric "$block_device" | grep -i "$sensor_filter" | awk '{print $3}' | cut -d '%' -f1)

    if [[ -n "$PERCENT_USED" && "$PERCENT_USED" -gt "$PERCENT_USED_CRIT" ]]; then
        local cmk_status_detail="WARNING - Disk usage at ${PERCENT_USED}%"
        local cmk_status="1"
    else
        local cmk_status_detail="OK - Disk usage at ${PERCENT_USED}%"
        local cmk_status="0"
    fi

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics:=-} ${cmk_status_detail}"

}

# Verificando erros de integridade dos dados
function media_errors_status() {

    local block_device="$1"
    local cmk_service_name="S.M.A.R.T_Disk_${block_device}_Media_Erros"
    local sensor_filter="Media and Data Integrity Errors"

    local MEDIA_ERRORS=$(get_smart_info_stric "$block_device" | grep -i "$sensor_filter" | cut -d':' -f2 | sed 's/\ \+//g')

    if [[ -n "$MEDIA_ERRORS" && "$MEDIA_ERRORS" -gt "$MEDIA_ERRORS_CRIT" ]]; then
        local cmk_status_detail="CRITICAL - Media/Data Integrity Errors: ${MEDIA_ERRORS}"
        local cmk_status="2"
    else
        local cmk_status_detail="OK - No Media/Data Integrity Errors Found: ${MEDIA_ERRORS}"
        local cmk_status="0"
    fi

    echo "${cmk_status} ${cmk_service_name} ${cmk_value_metrics:=-} ${cmk_status_detail}"

}

#
# Função principal
#
function main() {

    # Identifica quais discos estão conectados ao servidor
    BLOCK_DEVICES="$(lsblk -n -d -o NAME | grep -v 'loop')"

    # Gera um sensor para cada sensor do SMART de cada disco
    for BLOCK_DEVICE in ${BLOCK_DEVICES}; do

        # Verifica pelo nome do disco as funções corretas
        if [[ "$BLOCK_DEVICE" =~ ^sd[a-z]$ ]]; then
        
            general_status "$BLOCK_DEVICE"
            health_status "$BLOCK_DEVICE"

        elif [[ "$BLOCK_DEVICE" =~ ^nvme[0-9][a-z][0-9]$ ]]; then

            general_status "$BLOCK_DEVICE"
            health_status "$BLOCK_DEVICE"
            temperature_status "$BLOCK_DEVICE"
            percentage_used_status "$BLOCK_DEVICE"
            media_errors_status "$BLOCK_DEVICE"

        fi

    done

}
main
