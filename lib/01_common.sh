#!/usr/bin/env bash

check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log "ERROR" "Скрипт должен быть запущен с правами root!"
    exit 1
  fi
  [[ -t 1 ]] && clear
  log "OK" "Проверка прав root — пройдена"
}

check_os_version() {
  local id version
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    id="$ID"
    version="${VERSION_ID%%.*}"
  else
    log "ERROR" "Невозможно определить версию ОС (отсутствует /etc/os-release)"
    exit 1
  fi

  if [[ "$id" != "debian" ]]; then
    log "ERROR" "Поддерживается только Debian. Обнаружено: $id"
    exit 1
  fi

  if (( version < 12 )); then
    log "ERROR" "Минимально поддерживаемая версия Debian — 12. Обнаружено: $VERSION_ID"
    exit 1
  fi

  log "OK" "Проверка ОС — Debian $VERSION_ID"
}

install_packages() {
  log "INFO" "Установка необходимых пакетов..."

  if ! command -v apt >/dev/null; then
    log "ERROR" "apt не найден. Скрипт поддерживает только Debian-подобные системы с APT"
    exit 1
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt update -y && apt upgrade -y && apt install -y \
    ca-certificates curl iproute2 iptables nftables iputils-ping \
    resolvconf net-tools jq ipset nano mc sudo libssl-dev \
    conntrack tcpdump arptables ebtables \
    openssh-server openssh-client openssh-sftp-server && \
    apt autoremove -y

  log "OK" "Пакеты успешно установлены"
}

disable_conflicting_services() {
  log "INFO" "Отключение конфликтующих системных сервисов"

  local services=(
    NetworkManager
    systemd-networkd
    wicd
    connman
    ifplugd
  )
  local disabled=()

  for svc in "${services[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc.service"; then
      if systemctl is-enabled --quiet "$svc"; then
        systemctl disable --now "$svc"
        log "OK" "$svc отключён"
        disabled+=("$svc")
      else
        log "INFO" "$svc уже отключён"
      fi
    else
      log "INFO" "$svc не установлен"
    fi
  done

  if [[ "${#disabled[@]}" -eq 0 ]]; then
    log "INFO" "Ни один сервис не нуждался в отключении"
  else
    log "OK" "Отключены: ${disabled[*]}"
  fi
}
