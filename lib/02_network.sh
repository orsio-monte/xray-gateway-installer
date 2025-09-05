#!/usr/bin/env bash

rename_network_interface() {
  local iface="$1"
  local target_name="${2:-eth0}"
  local now_utc mac link_dir link_file dump_file

  [[ "$iface" == "$target_name" ]] && {
    log "INFO" "Интерфейс уже имеет имя $target_name"
    return
  }

  [[ -e "/sys/class/net/$iface" ]] || {
    log "ERROR" "Интерфейс $iface не найден"
    return 1
  }

  if [[ -e "/sys/class/net/$target_name" ]]; then
    log "WARN" "Целевое имя $target_name уже занято. Переименование пропущено"
    return
  fi

  mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || true)
  [[ -n "$mac" ]] || {
    log "ERROR" "Не удалось получить MAC для $iface"
    return 1
  }

  now_utc=$(date -u +%Y%m%d-%H%M%S)
  dump_file=/root/network-ifaces.dump
  echo "$mac $iface" > "$dump_file"
  log "INFO" "Сохранил дамп MAC→iface: $dump_file"

  link_dir=/etc/systemd/network
  link_file="$link_dir/10-$target_name.link"
  mkdir -p "$link_dir"

  shopt -s nullglob
  for lf in "$link_dir"/*.link; do
    if grep -qi "MACAddress=$mac" "$lf"; then
      cp -a "$lf" "$lf.bak.$now_utc"
      mv -f "$lf" "$lf.disabled.$now_utc"
      log "INFO" "Отключён конфликтующий .link: $lf"
    fi
  done
  shopt -u nullglob

  cat > "$link_file" <<EOF
[Match]
MACAddress=$mac
[Link]
Name=$target_name
EOF
  log "OK" "Создан файл $link_file"
  udevadm control --reload || true

  local files_to_edit=()
  [[ -e /etc/network/interfaces ]] && files_to_edit+=("/etc/network/interfaces")
  shopt -s nullglob
  for f in /etc/network/interfaces.d/*; do files_to_edit+=("$f"); done
  shopt -u nullglob

  # Обновляем файлы конфигурации сети
  local f
  for f in "${files_to_edit[@]}"; do
    cp -a "$f" "$f.bak.$now_utc"
    sed -ri \
      -e "s/^(auto|allow-hotplug|iface)[[:space:]]+$iface\b/\1 $target_name/" \
      -e "s/\b$iface\b/$target_name/g" \
      "$f"
    log "INFO" "Обновлён $f"
  done

  # Обновляем netplan конфигурации (Ubuntu)
  shopt -s nullglob
  for netplan_file in /etc/netplan/*.yaml; do
    if [[ -f "$netplan_file" ]]; then
      cp -a "$netplan_file" "$netplan_file.bak.$now_utc"
      sed -ri "s/\b$iface\b/$target_name/g" "$netplan_file"
      log "INFO" "Обновлён netplan файл: $netplan_file"
    fi
  done
  shopt -u nullglob

  ip link set dev "$iface" down 2>/dev/null || true
  if ip link set dev "$iface" name "$target_name"; then
    ip link set dev "$target_name" up 2>/dev/null || true
    
    # Перезапускаем сетевые сервисы в зависимости от конфигурации
    if command -v netplan >/dev/null 2>&1 && [[ -d /etc/netplan ]]; then
      log "INFO" "Применение изменений netplan"
      netplan apply 2>/dev/null || true
    else
      systemctl restart networking 2>/dev/null || true
    fi
    
    log "OK" "Интерфейс переименован в $target_name"
  else
    log "WARN" "Онлайн-переименование не удалось, изменения применятся после перезагрузки"
  fi
}

detect_interfaces() {
  local current_if
  current_if="$(ip route | awk '/default/ {print $5}' | head -n1)"
  if [[ -z "$current_if" ]]; then
    log "ERROR" "Не удалось определить интерфейс с default route"
    exit 1
  fi

  rename_network_interface "$current_if" "eth0"

  LAN_IF="$(ip route | awk '/default/ {print $5}' | head -n1)"
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
    for iface_path in /sys/class/net/*; do
      iface="$(basename "$iface_path")"
      mac="$(cat "$iface_path/address")"
      echo "$iface -> $mac"
    done
  } > "$dump_file"

  log "OK" "Вероятно, что может потребоваться ручная настройка сетевой карты. Сетевые настройки сохранены в: $dump_file"
}