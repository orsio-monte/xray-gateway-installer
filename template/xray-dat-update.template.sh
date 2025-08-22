#!/bin/bash

set -euo pipefail
umask 022
PATH=/usr/sbin:/usr/bin:/sbin:/bin

XRAY_SERVICE="xray"
XRAY_FOLDER="__XRAY_FOLDER__"
XRAY_DAT_PATH="$XRAY_FOLDER/dat"
XRAY_DATCHECK_DIR="$XRAY_FOLDER/dat-check"
ETAG_DIR="$XRAY_DATCHECK_DIR/etag"
HASH_DIR="$XRAY_DATCHECK_DIR/hash"
# TMP_DIR будет создан динамически через mktemp ниже
# shellcheck disable=SC2034
XRAY_USER="__XRAY_USER__"
# shellcheck disable=SC2034
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
  local log_file="$log_path"
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

# === Глобальная блокировка от параллельных запусков ===
mkdir -p "$XRAY_DATCHECK_DIR"
exec 9>"$XRAY_DATCHECK_DIR/.lock"
if ! flock -n 9; then
  echo "[WARN] Another instance is running; exiting." >&2
  exit 0
fi

xray_dat_schedule_cron() {
  echo -e "\n Настройка автоматического обновления GeoIP/GeoSite"
  cat <<'MENU'
  Выберите день недели:
     0. Отмена
     1. Понедельник
     2. Вторник
     3. Среда
     4. Четверг
     5. Пятница
     6. Суббота
     7. Воскресенье
     8. Ежедневно
     9. Удалить задачу из cron
MENU

  local day_choice hour minute day_of_week cron_expr
  while true; do
    read -rp "  Ваш выбор: " day_choice
    [[ "$day_choice" =~ ^[0-9]$ ]] && break
    echo "  ❌ Некорректный ввод. Введите число от 0 до 9."
  done

  if [[ "$day_choice" == "0" ]]; then
    logs INFO "Отменено пользователем"
    return
  fi

  if [[ "$day_choice" == "9" ]]; then
    logs INFO "Удаляю cron-задачи для: $script_path"
    local tmp_cron
    tmp_cron="$(mktemp)"
    crontab -l 2>/dev/null | grep -vF "$script_path" > "$tmp_cron" || true
    crontab "$tmp_cron" || { logs ERR "Не удалось применить crontab"; rm -f "$tmp_cron"; return 1; }
    rm -f "$tmp_cron"
    logs OK "Задачи удалены (если были)"
    return
  fi

  read -rp "  Час (0–23): " hour
  read -rp "  Минута (0–59): " minute
  [[ "$hour" =~ ^([01]?[0-9]|2[0-3])$ ]] || { logs ERR "Неверный час"; return 1; }
  [[ "$minute" =~ ^([0-5]?[0-9])$ ]] || { logs ERR "Неверная минута"; return 1; }

  case "$day_choice" in
    1) day_of_week=1;;
    2) day_of_week=2;;
    3) day_of_week=3;;
    4) day_of_week=4;;
    5) day_of_week=5;;
    6) day_of_week=6;;
    7) day_of_week=0;; # в crontab 0=воскресенье
    8) day_of_week="*";;
    *) logs ERR "Неожиданный выбор"; return 1;;
  esac

  # безопасно экранируем путь, добавим окружение для cron
  local qpath
  qpath="$(printf '%q' "$script_path")"
  cron_expr="$minute $hour * * $day_of_week $qpath"

  {
    crontab -l 2>/dev/null | grep -vF "$script_path" || true
    echo "SHELL=/bin/bash"
    echo "PATH=/usr/sbin:/usr/bin:/sbin:/bin"
    echo "$cron_expr"
  } | crontab -

  if crontab -l | grep -Fq "$script_path"; then
    logs OK "crontab успешно обновлён"
    local full_line
    full_line="$(crontab -l | grep -F "$script_path" || true)"
    [[ -n "$full_line" ]] && logs INFO "Cron-строка: $full_line" || logs WARN "Не нашёл cron-строку после установки"
  else
    logs ERR "Не удалось установить crontab"
    return 1
  fi
}

cleanup() {
  [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"
}

update_file() {
  local filename="$1" url="$2"
  local tmpfile="$TMP_DIR/$filename"
  local localfile="$XRAY_DAT_PATH/$filename"
  local etag_file="$ETAG_DIR/.etag-$filename"
  local hash_file="$HASH_DIR/.hash-$filename"
  local header_file="$TMP_DIR/header-$filename"

  local etag http_status etag_server current_hash old_hash curl_rc
  etag="$(cat "$etag_file" 2>/dev/null || true)"

  # Собираем аргументы curl
  local -a curl_args=(-sS -L --connect-timeout 10 --max-time 60 --retry 3 --retry-all-errors \
                      -w "%{http_code}" -D "$header_file" -o "$tmpfile" "$url")
  if [[ -n "${etag:-}" ]]; then
    curl_args=( -H "If-None-Match: $etag" "${curl_args[@]}" )
  fi

  # Выполняем curl и отдельно берём код возврата и http-код
  set +e
  http_status="$(curl "${curl_args[@]}")"
  curl_rc=$?
  set -e

  if (( curl_rc != 0 )); then
    logs WARN "Сетевая ошибка curl (rc=$curl_rc) для $filename"
    rm -f "$tmpfile" "$header_file"
    return 1
  fi

  # Берём ПОСЛЕДНИЙ ETag из всех блоков заголовков (после редиректов)
  etag_server="$(
    awk '
      tolower($1)=="etag:"{
        $1="";
        sub(/^[ \t]+/,"");
        gsub(/"/,"");
        sub(/^W\//,"");
        last=$0
      }
      END{ if(length(last)) print last }
    ' "$header_file"
  )"

  old_hash="$(cat "$hash_file" 2>/dev/null || true)"

  case "$http_status" in
    200)
      current_hash="$(sha256sum "$tmpfile" 2>/dev/null | cut -d" " -f1 || true)"
      if [[ -n "$etag_server" && "$etag_server" == "$etag" && -n "$current_hash" && "$current_hash" == "$old_hash" ]]; then
        logs INFO "ПРОПУЩЕНО: $filename — ETag и хеш совпадают"
        rm -f "$tmpfile" "$header_file"
        return 1
      fi
      [[ -n "$etag_server" && "$etag_server" == "$etag" && -n "$current_hash" && "$current_hash" != "$old_hash" ]] \
        && logs WARN "ETag совпадает, но хеш отличается для $filename — обновляем"

      mv "$tmpfile" "$localfile"
      if [[ -n "${XRAY_USER:-}" && -n "${XRAY_USER_GROUP:-}" ]] && id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown "$XRAY_USER:$XRAY_USER_GROUP" "$localfile" || true
      fi
      [[ -n "$etag_server" ]] && echo "$etag_server" > "$etag_file" || :
      [[ -n "$current_hash" ]] && echo "$current_hash" > "$hash_file" || :
      logs OK "ОБНОВЛЕНО: $filename"
      return 0
      ;;
    304)
      logs INFO "ПРОПУЩЕНО: $filename — HTTP 304 (не изменено)"
      rm -f "$tmpfile" "$header_file"
      return 1
      ;;
    404)
      logs ERR "Файл не найден (404) для $filename"
      rm -f "$tmpfile" "$header_file" "$etag_file"
      return 1
      ;;
    *)
      logs WARN "Неожиданный статус HTTP $http_status для $filename"
      rm -f "$tmpfile" "$header_file"
      return 1
      ;;
  esac
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

  # Базовые директории
  mkdir -p "$XRAY_DAT_PATH" "$ETAG_DIR" "$HASH_DIR" "$XRAY_DATCHECK_DIR"

  # Временная директория в пределах XRAY_DATCHECK_DIR
  TMP_DIR="$(mktemp -d "$XRAY_DATCHECK_DIR/tmp.XXXXXX")"

  local updated=0

  # Детерминированный порядок файлов
  mapfile -t _keys < <(printf '%s\n' "${!FILES[@]}" | sort)
  for filename in "${_keys[@]}"; do
    if update_file "$filename" "${FILES[$filename]}"; then
      updated=1
    fi
  done

  if [[ $updated -eq 1 ]]; then
    logs INFO "Перезапуск службы Xray: $XRAY_SERVICE"
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^${XRAY_SERVICE}\.service"; then
      if systemctl restart "$XRAY_SERVICE"; then
        logs OK "Обновление завершено, служба перезапущена"
      else
        logs ERR "Ошибка при перезапуске службы $XRAY_SERVICE"
      fi
    else
      logs WARN "systemctl/юнит недоступны — пропускаю перезапуск"
    fi
  else
    logs INFO "Все файлы актуальны. Перезапуск не требуется"
  fi
}

trap cleanup EXIT
main "$@"
