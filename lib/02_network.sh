#!/usr/bin/env bash

detect_interfaces() {
  LAN_IF="$(ip route | awk '/default/ {print $5}' | head -n1)"
  if [[ -z "$LAN_IF" ]]; then
    log "ERROR" "Не удалось определить интерфейс с default route"
    exit 1
  fi

  LOCAL_CIDRS="$(ip -o -f inet addr show "$LAN_IF" | awk '{print $4}' | xargs)"
  if [[ -z "$LOCAL_CIDRS" ]]; then
    log "ERROR" "Не удалось получить локальные CIDR для интерфейса $LAN_IF"
    exit 1
  fi

  export LAN_IF LOCAL_CIDRS

  log "OK" "Обнаружен интерфейс: $LAN_IF"
  log "INFO" "Локальные сети: $LOCAL_CIDRS"
}

dump_all_interfaces() {
  local output_dir
  if [[ -n "$SCRIPT_DIR" && -d "$SCRIPT_DIR" ]]; then
    output_dir="$SCRIPT_DIR"
  else
    output_dir="$PWD"
  fi

  local dump_file="$output_dir/network-ifaces.dump"

  {
    echo "# === Сетевые адаптеры (ip link) ==="
    ip -o link show
    echo

    echo "# === IP-адреса (ip addr) ==="
    ip -o addr show
    echo

    echo "# === Маршруты (ip route) ==="
    ip route
    echo

    echo "# === MAC-адреса ==="
    for iface in $(ls /sys/class/net); do
      mac=$(cat "/sys/class/net/$iface/address")
      echo "$iface -> $mac"
    done
  } > "$dump_file"

  log "OK" "Вероятно, что может потребоваться ручная настройка сетевой карты. Сетевые настройки сохранены в: $dump_file"
}
