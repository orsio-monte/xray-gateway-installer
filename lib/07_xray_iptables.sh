#!/usr/bin/env bash


force_use_iptables_legacy() {
  log "INFO" "Переключение iptables и родственных утилит на legacy-бэкенд"

  for tool in iptables ip6tables arptables ebtables; do
    local legacy_path="/usr/sbin/${tool}-legacy"
    if [[ -x "$legacy_path" ]]; then
      update-alternatives --install "/usr/sbin/$tool" "$tool" "$legacy_path" 100
      update-alternatives --set "$tool" "$legacy_path"
      log "OK" "$tool переключён на legacy-бэкенд"
    else
      log "INFO" "Пропуск $tool: legacy-бэкенд отсутствует"
    fi
  done

  local backend
  backend=$(update-alternatives --query iptables | awk '/Value: / {print $2}')
  if [[ "$backend" != "/usr/sbin/iptables-legacy" ]]; then
    log "ERROR" "iptables не использует legacy-бэкенд: $backend"
    exit 1
  else
    log "OK" "iptables работает в режиме legacy"
  fi


  validate_xray_configs() {
    local bin="/usr/local/bin/xray"
    local config_dir="$XRAY_JSONS_PATH"

    log INFO "Проверка конфигурации Xray через \`$bin -test -confdir $config_dir\`..."

    if [[ ! -x "$bin" ]]; then
      log ERROR "Не найден бинарник Xray: $bin"
      return 1
    fi

    if [[ ! -d "$config_dir" ]]; then
      log ERROR "Каталог конфигурации не найден: $config_dir"
      return 1
    fi

    if "$bin" run -test -confdir "$config_dir" &> >(tee /tmp/xray-test.log); then
      log OK "Конфигурация Xray прошла проверку успешно"
      return 0
    else
      log ERROR "Xray обнаружил ошибки в конфигурации:"
      sed 's/^/    └─ /' /tmp/xray-test.log
      return 1
    fi
  }
}


generate_xray_iptables_script() {
  local template_name="xray-iptables.template.sh"
  local template_path="$TEMPLATE_DIR/$template_name"
  local output_path="$XRAY_FOLDER/iptables/xray-iptables.sh"
  local output_dir
  output_dir="$(dirname "$output_path")"
  local remote_url="$GITHUB_REPO_RAW/template/$template_name"

  log INFO "Начата генерация скрипта iptables: $output_path"

  # Если шаблон отсутствует — пробуем скачать с GitHub
  if [[ ! -f "$template_path" ]]; then
    log WARN "Шаблон $template_name не найден локально. Загружаю с $remote_url..."
    mkdir -p "$TEMPLATE_DIR"
    if curl -fsSL "$remote_url" -o "$template_path"; then
      log OK "Шаблон успешно загружен: $template_path"
    else
      log ERROR "Не удалось загрузить шаблон с GitHub: $remote_url"
      return 1
    fi
  fi

  # Убедимся, что директория назначения существует
  if [[ ! -d "$output_dir" ]]; then
    mkdir -p "$output_dir" || {
      log ERROR "Не удалось создать каталог: $output_dir"
      return 1
    }
    log OK "Каталог создан: $output_dir"
  fi

  # Подстановка переменных
  sed -e "s|__XRAY_GID__|$XRAY_GID|g" \
      -e "s|__XRAY_CONFIG_DIR__|$XRAY_JSONS_PATH|g" \
      -e "s|__IPTABLE_UNIT_NAME__|$IPTABLE_UNIT_NAME|g" \
      -e "s|__IPTABLE_UNIT_PATH__|$IPTABLE_UNIT_PATH|g" \
      -e "s|__IPTABLE_RESTART_UNIT_NAME__|$IPTABLE_RESTART_UNIT_NAME|g" \
      -e "s|__IPTABLE_RESTART_UNIT_PATH__|$IPTABLE_RESTART_UNIT_PATH|g" \
      "$template_path" > "$output_path"

  # Проверка и запуск
  if [[ -s "$output_path" ]]; then
    chmod +x "$output_path" && log OK "Скрипт сгенерирован и сделан исполняемым: $output_path"
    ls -l $output_path
  else
    log ERROR "Скрипт не сгенерирован: файл пустой"
    return 1
  fi

  $output_path reinstall
}
