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

  if ! command -v apt >/dev/null 2>&1; then
    log "ERROR" "apt не найден. Скрипт поддерживает только Debian-подобные системы с APT"
    exit 1
  fi

  # Бэкап resolv.conf без изменения содержимого и с сохранением типа (файл/симлинк)
  local resolv_backup
  resolv_backup="$(mktemp /tmp/resolv.conf.backup.XXXXXX)"
  if [ -e /etc/resolv.conf ]; then
    cp -a /etc/resolv.conf "$resolv_backup"
  else
    # На всякий случай создадим пустую заглушку, чтобы логика восстановления была одинаковой
    : > "$resolv_backup"
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt update -y && apt upgrade -y && apt install -y \
    ca-certificates curl iproute2 iptables nftables iputils-ping \
    resolvconf net-tools jq ipset nano mc sudo libssl-dev \
    conntrack tcpdump arptables ebtables \
    openssh-server openssh-client openssh-sftp-server && \
    apt autoremove -y

  # Восстановление исходного /etc/resolv.conf (без промежуточных правок)
  if [ -s "$resolv_backup" ] || [ -L "$resolv_backup" ]; then
    # -aT сохранит права/типы, а -T гарантирует, что целевой путь трактуется как файл
    cp -aT "$resolv_backup" /etc/resolv.conf
  fi
  rm -f "$resolv_backup"

  # Обновим конфигурацию резолвера по возможности
  if command -v resolvconf >/dev/null 2>&1; then
    resolvconf -u || true
  else
    systemctl restart networking 2>/dev/null || true
  fi

  log "OK" "Пакеты успешно установлены"
}

has_replacement_network_config() {
  if [[ -f /etc/network/interfaces ]] \
    && grep -Eq '^\s*(iface|auto)\s+' /etc/network/interfaces; then
    return 0
  fi
  if compgen -G "/etc/network/interfaces.d/*" >/dev/null 2>&1; then
    return 0
  fi
  if compgen -G "/etc/netplan/*.yaml" >/dev/null 2>&1; then
    return 0
  fi
  return 1
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
      if [[ "$svc" == "NetworkManager" || "$svc" == "systemd-networkd" ]] \
        && ! has_replacement_network_config; then
        log "WARN" "Пропуск отключения $svc: отсутствует конфигурация сети"
      elif systemctl is-enabled --quiet "$svc"; then
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
