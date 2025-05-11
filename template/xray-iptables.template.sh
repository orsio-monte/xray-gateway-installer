#!/usr/bin/env bash
set -e

MARK_ID=0x__XRAY_GID__
TPROXY_GID=__XRAY_GID__
ROUTE_TABLE_ID=233

XRAY_CHAIN="XRAY"
XRAY_SELF_CHAIN="XRAY_SELF"

XRAY_CONFIG_DIR="__XRAY_CONFIG_DIR__"
XRAY_TPROXY_PORT=""
XRAY_REDIRECT_PORT=""

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
UNIT_NAME="__IPTABLE_UNIT_NAME__"
UNIT_PATH="__IPTABLE_UNIT_PATH__"
IPTABLE_RESTART_UNIT_NAME="__IPTABLE_RESTART_UNIT_NAME__"
IPTABLE_RESTART_UNIT_PATH="__IPTABLE_RESTART_UNIT_PATH__"

CUSTOM_BYPASS_CIDRS=()
CUSTOM_BYPASS_IPS=()
CUSTOM_BYPASS_PORTS=()

detect_interfaces() {
  echo "[INFO] Определение основного сетевого интерфейса..."

  LAN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)

  if [[ -z "$LAN_IF" ]]; then
    echo "[ERROR] Не удалось определить интерфейс с default route"
    exit 1
  else
    echo "[OK] Интерфейс по умолчанию: $LAN_IF"
  fi

  echo "[INFO] Получение локальных CIDR для интерфейса $LAN_IF..."
  LOCAL_CIDRS=$(ip -o -f inet addr show "$LAN_IF" | awk '{print $4}')

  if [[ -z "$LOCAL_CIDRS" ]]; then
    echo "[ERROR] Не удалось получить локальные CIDR для $LAN_IF"
    exit 1
  else
    echo "[OK] Найдены локальные подсети: $LOCAL_CIDRS"
  fi
}

ensure_exclusion_files_exist() {
  local base_dir="$(dirname "$0")"

  [[ -f "$base_dir/xray-exclude-iptables.cidrs" ]] || cat > "$base_dir/xray-exclude-iptables.cidrs" <<EOF
# CIDR-сети, исключаемые из обработки
# Пример:
# 10.0.0.0/8
# 192.168.0.0/16
EOF

  [[ -f "$base_dir/xray-exclude-iptables.ips" ]] || cat > "$base_dir/xray-exclude-iptables.ips" <<EOF
# IP-адреса, исключаемые из обработки
# Пример:
# 8.8.8.8
# 1.1.1.1
EOF

  [[ -f "$base_dir/xray-exclude-iptables.ports" ]] || cat > "$base_dir/xray-exclude-iptables.ports" <<EOF
# TCP-порты, исключаемые из обработки
# Пример:
# 22     # SSH
# 443    # HTTPS
# 8080   # Локальный UI
EOF
}

load_custom_exclusions() {
  local base_dir="$(dirname "$0")"

  # Чтение из переменных окружения — если заданы заранее
  local cidrs_from_env=("${CUSTOM_BYPASS_CIDRS[@]}")
  local ips_from_env=("${CUSTOM_BYPASS_IPS[@]}")
  local ports_from_env=("${CUSTOM_BYPASS_PORTS[@]}")

  # Чтение из файлов рядом со скриптом
  [[ -f "$base_dir/xray-exclude-iptables.cidrs" ]] && \
    mapfile -t cidrs_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.cidrs")

  [[ -f "$base_dir/xray-exclude-iptables.ips" ]] && \
    mapfile -t ips_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.ips")

  [[ -f "$base_dir/xray-exclude-iptables.ports" ]] && \
    mapfile -t ports_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.ports")

  # Объединение значений и удаление дубликатов
  CUSTOM_BYPASS_CIDRS=($(printf "%s\n" "${cidrs_from_env[@]}" "${cidrs_from_file[@]}" | sort -u))
  CUSTOM_BYPASS_IPS=($(printf "%s\n" "${ips_from_env[@]}" "${ips_from_file[@]}" | sort -u))
  CUSTOM_BYPASS_PORTS=($(printf "%s\n" "${ports_from_env[@]}" "${ports_from_file[@]}" | sort -u))

  echo "[INFO] Загружено исключений:"
  echo "  ├─ CIDRs: ${#CUSTOM_BYPASS_CIDRS[@]}"
  echo "  ├─ IPs:   ${#CUSTOM_BYPASS_IPS[@]}"
  echo "  └─ Ports: ${#CUSTOM_BYPASS_PORTS[@]}"
}


extract_xray_port_protocol() {
  local json_files
  json_files=$(find "$XRAY_CONFIG_DIR" -type f -name '*.json' 2>/dev/null || true)

  XRAY_TPROXY_PORT=""
  XRAY_REDIRECT_PORT=""

  for file in $json_files; do
    local inbounds
    inbounds=$(jq -c '.inbounds[]?' "$file" 2>/dev/null || true)

    for entry in $inbounds; do
      local protocol tproxy port network tag
      protocol=$(echo "$entry" | jq -r '.protocol // empty')
      tproxy=$(echo "$entry" | jq -r '.streamSettings.sockopt.tproxy // empty')
      port=$(echo "$entry" | jq -r '.port // empty')
      network=$(echo "$entry" | jq -r '.settings.network // empty' | tr '[:upper:]' '[:lower:]')
      tag=$(echo "$entry" | jq -r '.tag // empty')

      [[ -z "$port" || "$protocol" != "dokodemo-door" ]] && continue

      # Проверка наличия "udp" или "tcp" в списке сетей
      if [[ "$tproxy" == "tproxy" && "$network" == *udp* ]]; then
        XRAY_TPROXY_PORT="$port"
      elif [[ -z "$tproxy" && "$network" == *tcp* && "$tag" == "redirect" ]]; then
        XRAY_REDIRECT_PORT="$port"
      fi
    done
  done

  if [[ -n "$XRAY_TPROXY_PORT" || -n "$XRAY_REDIRECT_PORT" ]]; then
    echo "[INFO] Обнаруженные порты:"
    [[ -n "$XRAY_TPROXY_PORT" ]] && echo "  └─ TPROXY:   $XRAY_TPROXY_PORT" || echo "  └─ TPROXY:   [не найден]"
    [[ -n "$XRAY_REDIRECT_PORT" ]] && echo "  └─ REDIRECT: $XRAY_REDIRECT_PORT" || echo "  └─ REDIRECT: [не найден]"
  else
    echo "[WARN] Не удалось определить ни один порт из конфигов ($XRAY_CONFIG_DIR)"
  fi
}


clear_rules() {
  echo "[INFO] Удаление ip rule и маршрутов..."

  if ip rule del fwmark $MARK_ID table $ROUTE_TABLE_ID 2>/dev/null; then
    echo "[OK] ip rule удалён: fwmark=$MARK_ID → table $ROUTE_TABLE_ID"
  else
    echo "[WARN] ip rule не найден или уже удалён"
  fi

  if ip route flush table $ROUTE_TABLE_ID 2>/dev/null; then
    echo "[OK] Таблица маршрутов $ROUTE_TABLE_ID очищена"
  else
    echo "[WARN] Таблица маршрутов $ROUTE_TABLE_ID уже пуста или не существует"
  fi

  echo "[INFO] Удаление XRAY цепочек из PREROUTING и OUTPUT..."
  iptables -t mangle -D PREROUTING -j XRAY_ENABLED 2>/dev/null && echo "[OK] XRAY_ENABLED удалена из PREROUTING" || echo "[WARN] XRAY_ENABLED не была подключена"
  iptables -t mangle -D PREROUTING -j $XRAY_CHAIN 2>/dev/null && echo "[OK] $XRAY_CHAIN удалена из PREROUTING" || echo "[WARN] $XRAY_CHAIN не была подключена"
  iptables -t nat -D PREROUTING -j $XRAY_CHAIN 2>/dev/null && echo "[OK] $XRAY_CHAIN удалена из PREROUTING (nat)" || echo "[WARN] $XRAY_CHAIN не была подключена (nat)"
  iptables -t mangle -D OUTPUT -m owner ! --gid-owner $TPROXY_GID -j $XRAY_SELF_CHAIN 2>/dev/null && echo "[OK] $XRAY_SELF_CHAIN удалена из OUTPUT" || echo "[WARN] $XRAY_SELF_CHAIN не была подключена"

  echo "[INFO] Очистка содержимого цепочек XRAY, XRAY_SELF и XRAY_ENABLED..."
  iptables -t mangle -F $XRAY_CHAIN 2>/dev/null && echo "[OK] Очищена цепочка $XRAY_CHAIN (mangle)" || echo "[WARN] Цепочка $XRAY_CHAIN (mangle) не существует"
  iptables -t nat -F $XRAY_CHAIN 2>/dev/null && echo "[OK] Очищена цепочка $XRAY_CHAIN (nat)" || echo "[WARN] Цепочка $XRAY_CHAIN (nat) не существует"
  iptables -t mangle -F $XRAY_SELF_CHAIN 2>/dev/null && echo "[OK] Очищена цепочка $XRAY_SELF_CHAIN" || echo "[WARN] Цепочка $XRAY_SELF_CHAIN не существует"
  iptables -t mangle -F XRAY_ENABLED 2>/dev/null && echo "[OK] Очищена цепочка XRAY_ENABLED" || echo "[WARN] Цепочка XRAY_ENABLED не существует"

  echo "[INFO] Создание или очистка XRAY_DISABLED для DROP по умолчанию..."
  iptables -t mangle -F XRAY_DISABLED 2>/dev/null || iptables -t mangle -N XRAY_DISABLED
  iptables -t mangle -D PREROUTING -j XRAY_DISABLED 2>/dev/null || true
  iptables -t mangle -A PREROUTING -j XRAY_DISABLED

  echo "[INFO] Применение исключений в XRAY_DISABLED..."

  # Системные CIDR (например, localhost и локальные сети)
  for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
    iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
  done

  # Исключения IP-адресов
  for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
    iptables -t mangle -A XRAY_DISABLED -d "$ip" -j RETURN
  done

  # Исключения по CIDR
  for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
    iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
  done

  # Исключения по TCP-портам
  for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
    iptables -t mangle -A XRAY_DISABLED -p tcp --dport "$port" -j RETURN
  done

  # По умолчанию — DROP
  iptables -t mangle -A XRAY_DISABLED -j DROP
  echo "[OK] Добавлена цепочка XRAY_DISABLED с исключениями и DROP по умолчанию"
}


apply_rules() {
  echo "[INFO] Очистка предыдущих правил..."
  clear_rules

  echo "[INFO] Удаление цепочки XRAY_DISABLED (если существует)..."
  iptables -t mangle -D PREROUTING -j XRAY_DISABLED 2>/dev/null || true
  iptables -t mangle -F XRAY_DISABLED 2>/dev/null
  iptables -t mangle -X XRAY_DISABLED 2>/dev/null && echo "[OK] Удалена цепочка XRAY_DISABLED"

  echo "[INFO] Установка ip rule и таблицы маршрутов..."
  ip rule add fwmark $MARK_ID table $ROUTE_TABLE_ID || {
    echo "[ERROR] Не удалось добавить ip rule"
    exit 1
  }

  ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE_ID || {
    echo "[ERROR] Не удалось добавить маршрут в таблицу $ROUTE_TABLE_ID"
    exit 1
  }

  echo "[INFO] Настройка цепочек XRAY..."
  iptables -t mangle -N $XRAY_CHAIN 2>/dev/null || iptables -t mangle -F $XRAY_CHAIN
  iptables -t nat -N $XRAY_CHAIN 2>/dev/null || iptables -t nat -F $XRAY_CHAIN
  iptables -t mangle -N $XRAY_SELF_CHAIN 2>/dev/null || iptables -t mangle -F $XRAY_SELF_CHAIN
  iptables -t mangle -N XRAY_ENABLED 2>/dev/null || iptables -t mangle -F XRAY_ENABLED

  iptables -t mangle -D PREROUTING -j XRAY_ENABLED 2>/dev/null || true
  iptables -t mangle -A PREROUTING -j XRAY_ENABLED

  iptables -t mangle -C XRAY_ENABLED -j $XRAY_CHAIN 2>/dev/null || \
  iptables -t mangle -A XRAY_ENABLED -j $XRAY_CHAIN
  echo "[OK] Цепочка XRAY_ENABLED направляет трафик в XRAY"

  echo "[INFO] Подключение XRAY к PREROUTING и NAT (внутри XRAY_ENABLED)..."
  iptables -t nat -D PREROUTING -j $XRAY_CHAIN 2>/dev/null || true
  iptables -t nat -A PREROUTING -j $XRAY_CHAIN

  echo "[INFO] Добавление системных исключений..."
  for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
    iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
    iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
  done

  iptables -t mangle -A $XRAY_CHAIN -i lo -j RETURN
  iptables -t nat -A $XRAY_CHAIN -i lo -j RETURN

  echo "[INFO] Применение кастомных исключений..."
  for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
    iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
    iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
  done

  for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
    iptables -t mangle -A $XRAY_CHAIN -d "$ip" -j RETURN
    iptables -t nat -A $XRAY_CHAIN -d "$ip" -j RETURN
  done

  for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
    iptables -t mangle -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
    iptables -t nat -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
  done

  echo "[INFO] Добавление правил TPROXY (UDP) и REDIRECT (TCP)..."
  [[ -n "$XRAY_TPROXY_PORT" ]] && {
    iptables -t mangle -A $XRAY_CHAIN -p udp -j TPROXY --on-port $XRAY_TPROXY_PORT --tproxy-mark $MARK_ID/0xffffffff
    echo "[OK] Применено TPROXY для UDP на порт $XRAY_TPROXY_PORT"
  }

  [[ -n "$XRAY_REDIRECT_PORT" ]] && {
    iptables -t nat -A $XRAY_CHAIN -p tcp -j REDIRECT --to-ports $XRAY_REDIRECT_PORT
    echo "[OK] Применено REDIRECT для TCP на порт $XRAY_REDIRECT_PORT"
  }

  echo "[INFO] Исключение трафика самого Xray (gid=$TPROXY_GID)..."
  iptables -t mangle -D OUTPUT -m owner ! --gid-owner $TPROXY_GID -j $XRAY_SELF_CHAIN 2>/dev/null || true
  iptables -t mangle -A OUTPUT -m owner ! --gid-owner $TPROXY_GID -j $XRAY_SELF_CHAIN
  iptables -t mangle -A $XRAY_SELF_CHAIN -j RETURN
  echo "[OK] Трафик Xray исключён из обработки"
}

print_status_debug() {
  echo "Ожидание 10 секунд"
  sleep 10
  echo "========== XRAY IPTABLES STATUS DEBUG =========="

  echo -e "\n[+] Проверка ip rule:"
  ip rule list | grep -E "$MARK_ID|table $ROUTE_TABLE_ID" || echo "[!] Правило не найдено"

  echo -e "\n[+] Проверка таблицы маршрутов ($ROUTE_TABLE_ID):"
  ip route show table $ROUTE_TABLE_ID || echo "[!] Таблица пуста или не существует"

  echo -e "\n[+] Проверка цепочек iptables (mangle):"
  iptables -t mangle -L $XRAY_CHAIN -n -v 2>/dev/null || echo "[!] Цепочка $XRAY_CHAIN (mangle) отсутствует"
  iptables -t mangle -L $XRAY_SELF_CHAIN -n -v 2>/dev/null || echo "[!] Цепочка $XRAY_SELF_CHAIN отсутствует"
  iptables -t mangle -S PREROUTING | grep "$XRAY_CHAIN" || echo "[!] $XRAY_CHAIN не подключена к PREROUTING (mangle)"
  iptables -t mangle -S OUTPUT | grep "$XRAY_SELF_CHAIN" || echo "[!] $XRAY_SELF_CHAIN не подключена к OUTPUT"

  echo -e "\n[+] Проверка цепочек iptables (nat):"
  iptables -t nat -L $XRAY_CHAIN -n -v 2>/dev/null || echo "[!] Цепочка $XRAY_CHAIN (nat) отсутствует"
  iptables -t nat -S PREROUTING | grep "$XRAY_CHAIN" || echo "[!] $XRAY_CHAIN не подключена к PREROUTING (nat)"

  echo -e "\n[+] Используемые порты:"
  echo "  ├─ TPROXY_PORT:      ${XRAY_TPROXY_PORT:-не определён}"
  echo "  └─ REDIRECT_PORT:    ${XRAY_REDIRECT_PORT:-не определён}"

  echo -e "\n[+] Исключения CIDR (${#CUSTOM_BYPASS_CIDRS[@]}):"
  for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do echo "  └─ $cidr"; done

  echo -e "\n[+] Исключения IP (${#CUSTOM_BYPASS_IPS[@]}):"
  for ip in "${CUSTOM_BYPASS_IPS[@]}"; do echo "  └─ $ip"; done

  echo -e "\n[+] Исключения PORT (${#CUSTOM_BYPASS_PORTS[@]}):"
  for port in "${CUSTOM_BYPASS_PORTS[@]}"; do echo "  └─ $port"; done

  echo -e "\n[+] Сетевой интерфейс:"
  echo "  ├─ LAN_IF:      ${LAN_IF:-не определён}"
  echo "  └─ LOCAL_CIDRS: ${LOCAL_CIDRS:-не определены}"

  echo -e "\n[+] Статус systemd-юнита:"
  systemctl is-active --quiet xray && echo "  └─ xray.service: Active" || echo "  └─ xray.service: Inactive"
  systemctl is-active --quiet xray-iptables && echo "  └─ xray-iptables.service: Active" || echo "  └─ xray-iptables.service: Inactive"

  echo "==============================================="
}

install_unit() {
  echo "[INFO] Установка systemd юнитов: $UNIT_NAME и $IPTABLE_RESTART_UNIT_NAME..."

  # === Юнит для управления iptables ===
  cat > "$UNIT_PATH" <<EOF
[Unit]
Description=XRAY iptables manager
After=network.target xray.service
BindsTo=xray.service
PartOf=xray.service
ConditionPathExists=$SCRIPT_PATH

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPT_PATH start
ExecStop=$SCRIPT_PATH stop
WorkingDirectory=$SCRIPT_DIR
StandardOutput=journal
StandardError=journal
SuccessExitStatus=0
User=root

[Install]
WantedBy=multi-user.target
EOF

  # === Юнит для рестарта iptables при рестарте xray ===
  cat > "$IPTABLE_RESTART_UNIT_PATH" <<EOF
[Unit]
Description=Restart iptables when Xray restarts
After=xray.service
PartOf=xray.service
Requires=xray.service

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart $UNIT_NAME

[Install]
WantedBy=xray.service
EOF

  # === Очистка systemd журналов ===
  echo "[INFO] Очистка systemd журналов для $UNIT_NAME и $IPTABLE_RESTART_UNIT_NAME..."
  if journalctl --unit="$UNIT_NAME" --rotate \
    && journalctl --unit="$UNIT_NAME" --vacuum-time=1s \
    && journalctl --unit="$IPTABLE_RESTART_UNIT_NAME" --rotate \
    && journalctl --unit="$IPTABLE_RESTART_UNIT_NAME" --vacuum-time=1s; then
    echo "[OK] Журналы systemd очищены"
  else
    echo "[ERROR] Не удалось очистить systemd journal"
    exit 1
  fi

  # === Перезагрузка systemd и enable юнитов ===
  echo "[INFO] Перезагрузка systemd и активация юнитов..."
  systemctl daemon-reexec
  systemctl daemon-reload

  if systemctl enable "$UNIT_NAME"; then
    echo "[OK] Юнит $UNIT_NAME включён"
  else
    echo "[ERROR] Не удалось включить $UNIT_NAME"
    exit 1
  fi

  if systemctl enable "$IPTABLE_RESTART_UNIT_NAME"; then
    echo "[OK] Юнит $IPTABLE_RESTART_UNIT_NAME включён"
  else
    echo "[ERROR] Не удалось включить $IPTABLE_RESTART_UNIT_NAME"
    exit 1
  fi
}


uninstall_unit() {
  echo "[INFO] Удаление systemd юнита $UNIT_NAME..."

  if systemctl is-enabled --quiet "$UNIT_NAME"; then
    systemctl disable "$UNIT_NAME" || echo "[WARN] Не удалось отключить юнит"
  fi

  if systemctl is-active --quiet "$UNIT_NAME"; then
    systemctl stop "$UNIT_NAME" || echo "[WARN] Не удалось остановить юнит"
  fi

  rm -f "$UNIT_PATH" && echo "[OK] Файл юнита удалён: $UNIT_PATH"
  systemctl daemon-reexec
  systemctl daemon-reload
}

main() {
  trap 'echo "[FATAL] Скрипт аварийно завершён на строке $LINENO"; exit 1' ERR

  echo "Ключ запуска: "$1
  detect_interfaces
  ensure_exclusion_files_exist
  load_custom_exclusions
  extract_xray_port_protocol

  case "$1" in
    start|apply)
      echo "[ACTION] Применение правил маршрутизации и iptables"
      apply_rules
      print_status_debug
      ;;
    stop|clear)
      echo "[ACTION] Очистка всех правил маршрутизации и iptables"
      clear_rules
      print_status_debug
      ;;
    restart|reload)
      echo "[ACTION] Перезапуск iptables правил..."
      clear_rules
      apply_rules
      print_status_debug
      ;;
    status)
      echo "[ACTION] Проверка статуса..."
      print_status_debug
      ;;
    install)
      install_unit
      ;;
    uninstall)
      uninstall_unit
      ;;
    reinstall)
      uninstall_unit
      install_unit
      print_status_debug
      ;;
    ""|--help|-h)
      echo "Usage: $0 {start|stop|restart|status|install|uninstall|reinstall}"
      exit 0
      ;;
    *)
      echo "[ERROR] Неизвестная команда: $1"
      exit 1
      ;;
  esac

  exit 0

}

main "$@"