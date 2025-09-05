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

  # Поддержка Debian и Ubuntu
  case "$id" in
    "debian")
      if (( version < 12 )); then
        log "ERROR" "Минимально поддерживаемая версия Debian — 12. Обнаружено: $VERSION_ID"
        exit 1
      fi
      log "OK" "Проверка ОС — Debian $VERSION_ID"
      ;;
    "ubuntu")
      if (( version < 24 )); then
        log "ERROR" "Минимально поддерживаемая версия Ubuntu — 24.04. Обнаружено: $VERSION_ID"
        exit 1
      fi
      log "OK" "Проверка ОС — Ubuntu $VERSION_ID"
      ;;
    *)
      log "ERROR" "Поддерживаются только Debian 12+ и Ubuntu 24.04+. Обнаружено: $id $VERSION_ID"
      exit 1
      ;;
  esac
}

install_packages() {
  log "INFO" "Установка необходимых пакетов..."

  # Проверяем наличие пакетного менеджера
  local pkg_manager=""
  if command -v apt >/dev/null 2>&1; then
    pkg_manager="apt"
  elif command -v apt-get >/dev/null 2>&1; then
    pkg_manager="apt-get"
  else
    log "ERROR" "Не найден пакетный менеджер APT. Скрипт поддерживает только Debian-подобные системы"
    exit 1
  fi

  log "INFO" "Используется пакетный менеджер: $pkg_manager"

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
  
  # Обновляем список пакетов и систему
  if ! $pkg_manager update -y; then
    log "ERROR" "Ошибка обновления списка пакетов"
    exit 1
  fi
  
  if ! $pkg_manager upgrade -y; then
    log "ERROR" "Ошибка обновления системы"
    exit 1
  fi
  
  # Устанавливаем необходимые пакеты
  if ! $pkg_manager install -y \
    ca-certificates curl iproute2 iptables nftables iputils-ping \
    resolvconf net-tools jq ipset nano mc sudo libssl-dev \
    conntrack tcpdump arptables ebtables \
    openssh-server openssh-client openssh-sftp-server; then
    log "ERROR" "Ошибка установки пакетов"
    exit 1
  fi
  
  # Очищаем неиспользуемые пакеты
  if ! $pkg_manager autoremove -y; then
    log "WARN" "Ошибка очистки неиспользуемых пакетов"
  fi

  # Восстановление исходного /etc/resolv.conf (без промежуточных правок)
  if [ -s "$resolv_backup" ] || [ -L "$resolv_backup" ]; then
    # -aT сохранит права/типы, а -T гарантирует, что целевой путь трактуется как файл
    cp -aT "$resolv_backup" /etc/resolv.conf
  fi
  rm -f "$resolv_backup"

  # Обновим конфигурацию резолвера по возможности
  if command -v resolvconf >/dev/null 2>&1; then
    resolvconf -u || true
  elif command -v netplan >/dev/null 2>&1 && [[ -d /etc/netplan ]]; then
    netplan apply 2>/dev/null || true
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
      if [[ "$svc" == "NetworkManager" || "$svc" == "systemd-networkd" ]]; then
        # В Ubuntu 24.04 может использоваться netplan, проверяем это
        if ! has_replacement_network_config; then
          log "WARN" "Пропуск отключения $svc: отсутствует конфигурация сети"
          continue
        fi
      fi
      
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
