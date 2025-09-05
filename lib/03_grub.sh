#!/usr/bin/env bash

configure_grub() {
  log "INFO" "Настройка параметров GRUB..."

  if ! [[ -f "$GRUB_FILE" ]]; then
    log "ERROR" "Файл $GRUB_FILE не найден"
    exit 1
  fi

  local distributor
  distributor="$(lsb_release -i -s 2>/dev/null || echo "Unknown")"
  log "INFO" "Дистрибутив определён как: $distributor"

  # GRUB_DEFAULT и GRUB_TIMEOUT
  log "INFO" "Установка GRUB_DEFAULT=0 и GRUB_TIMEOUT=1"
  sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' "$GRUB_FILE"
  sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=1|' "$GRUB_FILE"

  # GRUB_DISTRIBUTOR
  if grep -q '^GRUB_DISTRIBUTOR=' "$GRUB_FILE"; then
    log "INFO" "Обновление GRUB_DISTRIBUTOR=$distributor"
    sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=$distributor|" "$GRUB_FILE"
  else
    log "INFO" "Добавление GRUB_DISTRIBUTOR=$distributor"
    echo "GRUB_DISTRIBUTOR=$distributor" >> "$GRUB_FILE"
  fi

  # GRUB_CMDLINE_LINUX_DEFAULT
  local default_cmdline='net.ifnames=0 biosdevname=0 nohz=on nowatchdog'
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
    log "INFO" "Обновление GRUB_CMDLINE_LINUX_DEFAULT=\"$default_cmdline\""
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$default_cmdline\"|" "$GRUB_FILE"
  else
    log "INFO" "Добавление GRUB_CMDLINE_LINUX_DEFAULT=\"$default_cmdline\""
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$default_cmdline\"" >> "$GRUB_FILE"
  fi

  # GRUB_CMDLINE_LINUX
  local kernel_cmdline='mitigations=off transparent_hugepage=never ipv6.disable=1 net.core.default_qdisc=fq net.ipv4.tcp_congestion_control=bbr'
  if grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE"; then
    log "INFO" "Обновление GRUB_CMDLINE_LINUX=\"$kernel_cmdline\""
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$kernel_cmdline\"|" "$GRUB_FILE"
  else
    log "INFO" "Добавление GRUB_CMDLINE_LINUX=\"$kernel_cmdline\""
    echo "GRUB_CMDLINE_LINUX=\"$kernel_cmdline\"" >> "$GRUB_FILE"
  fi

  log "INFO" "Применение изменений GRUB"
  
  # Определяем команду обновления GRUB в зависимости от дистрибутива
  local grub_update_cmd=""
  if command -v update-grub >/dev/null 2>&1; then
    grub_update_cmd="update-grub"
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub_update_cmd="grub-mkconfig -o /boot/grub/grub.cfg"
  elif command -v grub2-mkconfig >/dev/null 2>&1; then
    grub_update_cmd="grub2-mkconfig -o /boot/grub2/grub.cfg"
  else
    log "ERROR" "Не найдена команда обновления GRUB"
    exit 1
  fi
  
  log "INFO" "Выполняется: $grub_update_cmd"
  if eval "$grub_update_cmd"; then
    log "OK" "GRUB успешно обновлён"
  else
    log "ERROR" "Ошибка обновления GRUB"
    exit 1
  fi
}