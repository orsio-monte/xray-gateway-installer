#!/bin/bash

set -euo pipefail

XRAY_SERVICE="xray"
XRAY_FOLDER="__XRAY_FOLDER__"
XRAY_DAT_PATH="$XRAY_FOLDER/dat"
XRAY_DATCHECK_DIR="$XRAY_FOLDER/dat-check"
ETAG_DIR="$XRAY_DATCHECK_DIR/etag"
HASH_DIR="$XRAY_DATCHECK_DIR/hash"
TMP_DIR="$XRAY_DATCHECK_DIR/tmp"
XRAY_USER="__XRAY_USER__"
XRAY_USER_GROUP="__XRAY_USER_GROUP__"

script_path="$(realpath "$0")"
script_dir="$(dirname "$script_path")"
script_name="$(basename "$script_path")"
log_name="${script_name%.*}.log"
log_path="$script_dir/$log_name"

declare -A FILES=(
  ["geoip_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-IP/releases/latest/download/geoip.dat"
  ["geosite_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-Domains/releases/latest/download/geosite.dat"
  ["geoip_v2fly.dat"]="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
  ["geosite_v2fly.dat"]="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
  ["geoip_zkeen.dat"]="https://github.com/jameszeroX/zkeen-ip/releases/latest/download/zkeenip.dat"
  ["geosite_zkeengeo.dat"]="https://github.com/jameszeroX/zkeen-domains/releases/latest/download/zkeen.dat"
  ["geoip_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geoip.db"
  ["geosite_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geosite.db"
  ["geoip_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat"
  ["geosite_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat"
)

logs() {
  local level="$1"
  shift
  local caller="${FUNCNAME[1]:-MAIN}"
  local color reset timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  reset='\033[0m'
  local log_file="${SCRIPT_DIR:-.}/install.log"
  local module="${MODULE_NAME:-$(realpath "$0" 2>/dev/null || echo "$0")}"

  case "$level" in
    INFO)        color='\033[1;34m' ;; # синий
    OK|SUCCESS)  color='\033[1;32m' ;; # зелёный
    WARN*)       color='\033[1;33m' ;; # жёлтый
    ERR*|FAIL*)  color='\033[1;31m' ;; # красный
    SEP|SEPARATOR)
      color='\033[1;30m'
      local sep="────────────────────────────────────────────────────────────"
      echo -e "${color}${sep}${reset}"
      echo "${sep}" >> "$log_file"
      return
      ;;
    TITLE|HEADER)
      color='\033[1;36m'
      local title="== [$module] $* =="
      echo -e "${color}${title}${reset}"
      echo "$title" >> "$log_file"
      return
      ;;
    *)           color='\033[0m' ;;
  esac

  echo -e "${color}[${timestamp}] [$level] [$module] [$caller] ${reset} $*"
  echo "[${timestamp}] [$level] [$module] [$caller] $*" >> "$log_file"
}

xray_dat_schedule_cron() {
    local cronline
    echo -e "\n Настройка автоматического обновления GeoIP/GeoSite"

    echo "  Выберите день недели:"
    echo "     0. Отмена"
    echo "     1. Понедельник"
    echo "     2. Вторник"
    echo "     3. Среда"
    echo "     4. Четверг"
    echo "     5. Пятница"
    echo "     6. Суббота"
    echo "     7. Воскресенье"
    echo "     8. Ежедневно"
    echo "     9. Удалить задачу из cron"
    echo

    local day_choice hour minute day_of_week cron_expr
    while true; do
        read -rp "  Ваш выбор: " day_choice
        [[ "$day_choice" =~ ^[0-9]$ ]] && break
        echo "  ❌ Некорректный ввод. Введите число от 0 до 9."
    done

    if [[ "$day_choice" == "9" ]]; then
        logs INFO "Попытка удалить cron-задачу для: $script_path"

        tmp_cron="$(mktemp)"
        crontab -l 2>/dev/null | grep -vF "$script_path" > "$tmp_cron" || true
        crontab "$tmp_cron"
        rm -f "$tmp_cron"

        if crontab -l 2>/dev/null | grep -Fq "$script_path"; then
            logs ERR "❌ Не удалось удалить cron-задачу: $script_path"
        else
            logs OK "🗑 Cron-задача удалена (если была): $script_path"
        fi

        return
    fi


    if [[ "$day_choice" -eq 0 ]]; then
        echo "  ⚠ Автообновление не будет добавлено в cron"
        return
    fi

    read -rp "  Введите час запуска (0-23): " hour
    while [[ ! "$hour" =~ ^[0-9]+$ || "$hour" -lt 0 || "$hour" -gt 23 ]]; do
        echo "  ❌ Некорректный час. Повторите ввод."
        read -rp "  Введите час (0-23): " hour
    done

    read -rp "  Введите минуту запуска (0-59): " minute
    while [[ ! "$minute" =~ ^[0-9]+$ || "$minute" -lt 0 || "$minute" -gt 59 ]]; do
        echo "  ❌ Некорректные минуты. Повторите ввод."
        read -rp "  Введите минуты (0-59): " minute
    done

    if [[ "$day_choice" -eq 8 ]]; then
        cron_expr="$minute $hour * * *"
    else
        [[ "$day_choice" -eq 7 ]] && day_of_week=0 || day_of_week=$day_choice
        cron_expr="$minute $hour * * $day_of_week"
    fi

    cronline="$cron_expr $script_path >> $log_path 2>&1"

    # Добавление в cron
    logs "INFO" "script_path = $script_path"
    logs "INFO" "Будет добавлено в crontab: $cronline"

    tmp_cron="$(mktemp)"
    
    # Удаляем строки, содержащие полный путь скрипта (а не только имя!)
    crontab -l 2>/dev/null | grep -vF "$script_path" > "$tmp_cron" || true

    echo "$cronline" >> "$tmp_cron"

    if crontab "$tmp_cron"; then
        logs "OK" "crontab успешно обновлён"
    else
        logs "ERR" "Не удалось установить crontab"
        rm -f "$tmp_cron"
        return 1
    fi

    rm -f "$tmp_cron"

    if crontab -l | grep -Fq "$script_path"; then
        full_line=$(crontab -l | grep -F "$script_path")
        logs "OK" "Cron-задача успешно добавлена"
        logs "INFO" "Cron-строка: $full_line"
    else
        logs "ERR" "Ошибка: cron-задача не добавлена"
        return
    fi

}

main() {
    if [[ "${1:-}" == "-ci" ]]; then
        xray_dat_schedule_cron
        logs SEP
        logs TITLE "Полное текущее содержимое crontab:"
        crontab -l | while read -r line; do
            logs INFO "$line"
        done
        logs SEP
    fi

    mkdir -p "$TMP_DIR" "$XRAY_DAT_PATH" "$ETAG_DIR" "$HASH_DIR"
    updated=0

    for filename in "${!FILES[@]}"; do
    url="${FILES[$filename]}"
    tmpfile="$TMP_DIR/$filename"
    localfile="$XRAY_DAT_PATH/$filename"
    etag_file="$ETAG_DIR/.etag-$filename"
    hash_file="$HASH_DIR/.hash-$filename"
    header_file="$TMP_DIR/header-$filename"

    etag=$(cat "$etag_file" 2>/dev/null || echo "")
    http_status=$(curl -sS -L \
      --connect-timeout 10 \
      --max-time 30 \
      -H "If-None-Match: $etag" \
      -w "%{http_code}" \
      -D "$header_file" \
      -o "$tmpfile" \
      "$url")

    etag_server=$(grep -i '^ETag:' "$header_file" | cut -d' ' -f2 | tr -d '\r"')
    current_hash=$(sha256sum "$tmpfile" 2>/dev/null | cut -d' ' -f1)
    old_hash=$(cat "$hash_file" 2>/dev/null || echo "")

    if [[ "$http_status" == "200" ]]; then
      if [[ "$etag_server" == "$etag" && "$current_hash" == "$old_hash" ]]; then
        logs "INFO" "ПРОПУЩЕНО: $filename — ETag и хеш совпадают"
        rm -f "$tmpfile" "$header_file"
        continue
      fi
      [[ "$etag_server" == "$etag" && "$current_hash" != "$old_hash" ]] && \
        logs "WARN" "ETag совпадает, но хеш отличается для $filename — обновляем"

      mv "$tmpfile" "$localfile"
      echo "$etag_server" > "$etag_file"
      echo "$current_hash" > "$hash_file"
      logs "OK" "ОБНОВЛЕНО: $filename"
      updated=1
    elif [[ "$http_status" == "304" ]]; then
      logs "INFO" "ПРОПУЩЕНО: $filename — HTTP 304 (не изменено)"
      rm -f "$tmpfile" "$header_file"
    elif [[ "$http_status" == "404" ]]; then
      logs "ERROR" "Файл не найден (404) для $filename"
      rm -f "$tmpfile" "$header_file" "$etag_file"
    else
      logs "WARN" "Неожиданный статус HTTP $http_status для $filename"
      rm -f "$tmpfile" "$header_file"
    fi
    done

    rm -rf "$TMP_DIR"

    if [[ $updated -eq 1 ]]; then
    logs "INFO" "Перезапуск службы Xray: $XRAY_SERVICE"
    if systemctl restart "$XRAY_SERVICE"; then
      logs "OK" "Обновление завершено, служба перезапущена"
    else
      logs "ERR" "Ошибка при перезапуске службы $XRAY_SERVICE"
    fi
    else
        logs "INFO" "Все файлы актуальны. Перезапуск не требуется"
    fi
}

main "$@"
