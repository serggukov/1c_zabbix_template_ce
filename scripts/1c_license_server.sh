#!/bin/bash
#
# Мониторинг 1С Предприятия 8.3 (сервер лицензирования)
#
# (c) 2019-2020, Алексей Ю. Федотов
#
# Email: fedotov@kaminsoft.ru
#

WORK_DIR=$(dirname "${0}" | sed -r 's/\\/\//g; s/^(.{1}):/\/\1/')
source "${WORK_DIR}"/1c_common_module.sh 2>/dev/null || { echo "ОШИБКА: Не найден файл 1c_common_module.sh!" ; exit 1; }

declare -A LICENSE_CODE=(    # Коды пользовательских лицензий
    [0000000100005]=5        # 5 пользователей
    [0000000100015]=10       # 10 пользователей
    [0000000100050]=50       # 50 пользователей
    [0000000100100]=100      # 100 пользователей
    [0000000100500]=500 )    # 500 пользователей

function licenses_summary {

    RING_TOOL=$(check_ring_license) || exit 1
    
    ( execute_tasks license_info $(get_license_list "${RING_TOOL}") ) | \
        awk 'BEGIN { files=0; users=0 } 
            { files+=1; users+=$1 } 
            END { print files":"users }'

}

function license_info {

    CURRENT_CODE=$( "${RING_TOOL}" license info --send-statistics false --name ${1} | \
        awk '/0{7}10{2}[0-9]+/' | perl -pe 's/.*: (\d{10})/\1/; s/^$//' )

    [[ -n ${CURRENT_CODE} ]] && echo ${LICENSE_CODE[${CURRENT_CODE}]}

}

function get_license_counts {

    CLSTR_LIST=${1##*:}

    for CURR_CLSTR in ${CLSTR_LIST//;/ }; do
        timeout -s HUP ${RAS_PARAMS[timeout]} rac session list --licenses --cluster=${CURR_CLSTR%%,*} \
            ${RAS_PARAMS[auth]} ${1%%:*}:${RAS_PARAMS[port]} 2>/dev/null | \
            awk '/(user-name|rmngr-address|app-id)/' | \
            perl -pe 's/ //g; s/\n/|/; s/rmngr-address:(\"(.*)\"|)\||/\2/; s/app-id://; s/user-name:/\n/;' | \
            awk -F"|" -v hostname=${HOSTNAME,,} -v cluster=${CURR_CLSTR%%,*} 'BEGIN { sc=0; hc=0; cc=0; wc=0 } \
                { if ($1 != "") { sc+=1; uc[$1]; if ( index(tolower($3), hostname) > 0 ) { hc+=1 } \
                if ($2 == "WebClient") { wc+=1 } if ($3 == "") { cc+=1 } } } \
                END {print "CL#"cluster":"hc":"length(uc)":"sc":"cc":"wc }'
    done

}

function used_license {

    ( execute_tasks get_license_counts $( pop_clusters_list ) ) | \
        awk -F: 'BEGIN {ul=0; as=0; cl=0; uu=0; wc=0} \
            { print $0; ul+=$2; uu+=$3; as+=$4; cl+=$5; wc+=$6; } \
            END { print "summary:"ul":"uu":"as":"cl":"wc }' | sed 's/<sp>/ /g'

}

function get_clusters_list {

    pop_clusters_list | cut -f2 -d: | perl -pe 's/;[^\n]/\n/; s/;//' | \
        awk 'BEGIN {FS=","; print "{\"data\":[" } \
            {print "{\"{#CLSTR_UUID}\":\""$1"\",\"{#CLSTR_NAME}\":\""$3"\"}," } \
            END { print "]}" }' | \
        perl -pe 's/\n//;' | perl -pe 's/(.*),]}/\1]}\n/; s/<sp>/ /g'

}

function check_clusters_disconnection {

    LOST_CLSTR=$( check_clusters_cache lost | sed 's/ /<sp>/g; s/"//g' )
    
    if [[ -n ${LOST_CLSTR} ]]; then
        echo "Произошло отключение от кластера (сервер, имя):"
        for CURR_RMNGR in ${LOST_CLSTR}; do
            for CURR_CLSTR in ${CURR_RMNGR//;/ }; do
                echo "${CURR_RMNGR%:*} - ${CURR_CLSTR##*,}" | sed 's/<sp>/ /g'
            done
        done
    else
        echo "OK"
    fi

}

case ${1} in
    info) licenses_summary ;;
    used) shift; make_ras_params ${@}; used_license ;;
    clusters) get_clusters_list ;;
    check) check_clusters_disconnection ;;
    *) error "${ERROR_UNKNOWN_MODE}" ;;
esac
