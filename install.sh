#!/usr/bin/env bash

set -euo pipefail

# === Глобальные переменные ===
GRUB_FILE="/etc/default/grub"
LAN_IF=""
LOCAL_CIDRS=""
SYSCTL_CONF="/etc/sysctl.d/99-xray-gateway.conf"
XRAY_USER="xray"
XRAY_USER_GROUP=$XRAY_USER
XRAY_EXTRA_GROUPS=(nogroup)
XRAY_GID=23333
XRAY_FOLDER="/opt/xray"
XRAY_DAT_PATH="$XRAY_FOLDER/dat"
XRAY_JSONS_PATH="$XRAY_FOLDER/configs"
XRAY_LOG_PATH="$XRAY_FOLDER/logs"
XRAY_INSTALLER_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
XRAY_INSTALLER_PATH="/root/xray-install.sh"
TPROXY_GID=$XRAY_GID
TPROXY_USER=$XRAY_USER
IPTABLE_UNIT_NAME="xray-iptables.service"
IPTABLE_UNIT_PATH="/etc/systemd/system/$IPTABLE_UNIT_NAME"
IPTABLE_RESTART_UNIT_NAME="xray-iptables-restart.service"
IPTABLE_RESTART_UNIT_PATH="/etc/systemd/system/$IPTABLE_RESTART_UNIT_NAME"

ADMIN_EXTRA_GROUPS=("sudo" "adm" "nogroup" "$XRAY_USER_GROUP")
SKIP_ADMIN_USER_SETUP="true" #пропуск создания пользователя
ADMIN_USER=""  # Новый пользователь с sudo-доступом
ADMIN_SSH_KEY=""  # Публичный ключ SSH

GITHUB_REPO_RAW="https://raw.githubusercontent.com/Torotin/xray-gateway-installer/main"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR=$SCRIPT_DIR"/lib"
TEMPLATE_DIR=$SCRIPT_DIR"/template"
LOADED_MODULES=()

log() {
  local level="$1"
  shift

  local timestamp caller module_path
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  caller="${FUNCNAME[1]:-MAIN}"

  # Путь к вызывающему файлу (если есть)
  if [[ ${BASH_SOURCE[1]+isset} ]]; then
    module_path="$(realpath "${BASH_SOURCE[1]}" 2>/dev/null || echo "${BASH_SOURCE[1]}")"
  else
    module_path="$(realpath "$0" 2>/dev/null || echo "$0")"
  fi

  local log_file="${SCRIPT_DIR:-.}/install.log"
  local color reset="\033[0m"

  case "$level" in
    INFO)        color='\033[1;34m' ;;
    OK|SUCCESS)  color='\033[1;32m' ;;
    WARN*)       color='\033[1;33m' ;;
    ERR*|FAIL*)  color='\033[1;31m' ;;
    SEP|SEPARATOR)
      color='\033[1;30m'
      local sep="────────────────────────────────────────────────────────────"
      echo -e "${color}${sep}${reset}"
      echo "${sep}" >> "$log_file"
      return
      ;;
    TITLE|HEADER)
      color='\033[1;36m'
      local title="== [$module_path] $* =="
      echo -e "${color}${title}${reset}"
      echo "$title" >> "$log_file"
      return
      ;;
    *) color='\033[0m' ;;
  esac

  echo -e "${color}[${timestamp}] [$level] [$module_path] [$caller]${reset} $*"
  echo "[${timestamp}] [$level] [$module_path] [$caller] $*" >> "$log_file"
}


ensure_lib_loaded() {
  local file="$1"
  local local_path="$LIB_DIR/$file"
  local remote_url="$GITHUB_REPO_RAW/lib/$file"

  if [[ -f "$local_path" ]]; then
    source "$local_path"
    log OK "Модуль загружен локально: $local_path"
  else
    mkdir -p "$LIB_DIR"
    if curl -fsSL "$remote_url" -o "$local_path"; then
      source "$local_path"
      log OK "Модуль загружен с GitHub: $file"
    else
      log ERR "Не удалось загрузить модуль: $file"
      exit 1
    fi
  fi

  LOADED_MODULES+=("$file")
}


shopt -s nullglob
for module in "$LIB_DIR"/{00..10}_*.sh; do
  ensure_lib_loaded "$(basename "$module")"
done
shopt -u nullglob

main() {
  log "SEP"
  log "TITLE" "Старт скрипта"

  check_root

  log SEP
  log HEADER "Загружено ${#LOADED_MODULES[@]} модулей:"
  for module in "${LOADED_MODULES[@]}"; do
    log INFO "$module"
  done
  log SEP

  # check_os_version
  # detect_interfaces
  # install_packages
  # dump_all_interfaces
  # configure_grub
  # setup_admin_user
  # configure_sysctl
  # force_use_iptables_legacy
  # disable_conflicting_services
  # xray_create_user_and_dirs
  # xray_install
  # xray_override_systemd_unit
  # xray_create_sample_configs
  # xray_setup_log_rotation
  # generate_xray_iptables_script
  generate_xray_dat_update
  # xray_enable_and_start
  # xray_print_final_info
  log "TITLE" "Завершение скрипта"
}

main "$@"
