#!/usr/bin/env bash

xray_create_user_and_dirs() {
  log "INFO" "Создание пользователя $XRAY_USER и директорий Xray"

  if ! getent group "$XRAY_USER_GROUP" >/dev/null; then
    if groupadd -g "$XRAY_GID" "$XRAY_USER_GROUP"; then
      log "OK" "Группа $XRAY_USER_GROUP создана"
    else
      log "ERROR" "Не удалось создать группу $XRAY_USER_GROUP"
      exit 1
    fi
  else
    log "INFO" "Группа $XRAY_USER_GROUP уже существует"
  fi

  if ! getent passwd "$XRAY_USER" > /dev/null; then
    log "INFO" "Создание системного пользователя $XRAY_USER с GID $XRAY_GID"
    if useradd -r -M -s /usr/sbin/nologin -u "$XRAY_GID" -g "$XRAY_USER_GROUP" "$XRAY_USER"; then
      log "OK" "Пользователь $XRAY_USER создан"
    else
      log "ERROR" "Не удалось создать пользователя $XRAY_USER"
      exit 1
    fi
  else
    log "INFO" "Пользователь $XRAY_USER уже существует"
  fi

	# Добавление в группы — всегда
	if [[ "${#XRAY_EXTRA_GROUPS[@]}" -gt 0 ]]; then
	  if usermod -aG "$(IFS=,; echo "${XRAY_EXTRA_GROUPS[*]}")" "$XRAY_USER"; then
		log "OK" "$XRAY_USER добавлен в группы: ${XRAY_EXTRA_GROUPS[*]}"
	  else
		log "WARN" "Не удалось добавить $XRAY_USER в дополнительные группы"
	  fi
	fi

  if ! id "$XRAY_USER" &>/dev/null; then
    log "ERROR" "Пользователь $XRAY_USER не определён после создания"
    exit 1
  fi

  # Создание директорий
  if mkdir -p "$XRAY_DAT_PATH" "$XRAY_JSONS_PATH" "$XRAY_LOG_PATH"; then
    log "OK" "Директории Xray созданы"
  else
    log "ERROR" "Ошибка создания директорий Xray"
    exit 1
  fi

  # Обновление символической ссылки
  if [[ -L /usr/local/share/xray || -d /usr/local/share/xray || -f /usr/local/share/xray ]]; then
    if rm -rf /usr/local/share/xray; then
      log "OK" "Удалён старый путь /usr/local/share/xray"
    else
      log "ERROR" "Не удалось удалить /usr/local/share/xray"
      exit 1
    fi
  else
    log "INFO" "Символическая ссылка /usr/local/share/xray отсутствует — пропуск удаления"
  fi

}

xray_install() {
  log "INFO" "Скачивание Xray-инсталлятора: $XRAY_INSTALLER_URL"

  if curl -fsSL "$XRAY_INSTALLER_URL" -o "$XRAY_INSTALLER_PATH"; then
    log "OK" "Инсталлятор загружен в $XRAY_INSTALLER_PATH"
  else
    log "ERROR" "Не удалось загрузить Xray-инсталлятор"
    exit 1
  fi

  if chmod +x "$XRAY_INSTALLER_PATH"; then
    log "OK" "Права на выполнение даны для $XRAY_INSTALLER_PATH"
  else
    log "ERROR" "Не удалось задать права на $XRAY_INSTALLER_PATH"
    exit 1
  fi

  log "INFO" "Удаление предыдущей установки Xray (если была)"
  if bash "$XRAY_INSTALLER_PATH" remove; then
    log "OK" "Старая установка удалена (или не обнаружена)"
  else
    log "WARN" "Удаление завершилось с ошибкой, возможно Xray не был установлен"
  fi

  log "INFO" "Отключение сброса переменных DAT_PATH и JSON_PATH"
  if sed -i 's|^DAT_PATH=.*|# \0|' "$XRAY_INSTALLER_PATH" && \
     sed -i 's|^JSON_PATH=.*|# \0|' "$XRAY_INSTALLER_PATH"; then
    log "OK" "Сброс путей DAT/JSON отключён"
  else
    log "ERROR" "Не удалось закомментировать DAT_PATH/JSON_PATH"
    exit 1
  fi

  log "INFO" "Установка Xray от пользователя $XRAY_USER"
  if bash "$XRAY_INSTALLER_PATH" install -u "$XRAY_USER"; then
    log "OK" "Xray успешно установлен"
  else
    log "ERROR" "Установка завершилась с ошибкой"
    exit 1
  fi

  log "INFO" "Удаление инсталлятора"
  if rm -f "$XRAY_INSTALLER_PATH"; then
    log "OK" "Инсталлятор удалён"
  else
    log "ERROR" "Не удалось удалить $XRAY_INSTALLER_PATH"
    exit 1
  fi

  log "INFO" "Удаление конфликтующих systemd drop-in конфигураций"

  for dir in /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d; do
    if [[ -d "$dir" ]]; then
      if rm -rf "$dir"; then
        log "OK" "Удалён каталог с конфигурациями: $dir"
      else
        log "ERROR" "Не удалось удалить $dir"
        exit 1
      fi
    else
      log "INFO" "Каталог $dir не найден — пропуск"
    fi
  done


  if ln -s "$XRAY_DAT_PATH" /usr/local/share/xray; then
    log "OK" "Создана новая ссылка: /usr/local/share/xray → $XRAY_DAT_PATH"
  else
    log "ERROR" "Не удалось создать символическую ссылку /usr/local/share/xray"
    exit 1
  fi

}

xray_override_systemd_unit() {
  log "INFO" "Создание override-конфигурации systemd для xray"

  [[ -z "$XRAY_USER" || -z "$XRAY_LOG_PATH" || -z "$XRAY_JSONS_PATH" ]] && {
    log "ERROR" "Одна из обязательных переменных (XRAY_USER, XRAY_LOG_PATH, XRAY_JSONS_PATH) не задана"
    return 1
  }

  [[ ! -x "/usr/local/bin/xray" ]] && {
    log "ERROR" "Xray не найден в /usr/local/bin/xray"
    return 1
  }

  [[ ! -d "$XRAY_JSONS_PATH" ]] && {
    log "ERROR" "Каталог конфигурации не существует: $XRAY_JSONS_PATH"
    return 1
  }

  local override_dir="/etc/systemd/system/xray.service.d"
  local override_file="$override_dir/z90-custom-override.conf"

  mkdir -p "$override_dir" && log "OK" "Каталог override создан: $override_dir"

  cat > "$override_file" <<EOF
[Service]
ExecStart=
User=$XRAY_USER
Group=nogroup
ExecStartPre=/usr/bin/find $XRAY_LOG_PATH -type f -name '*.log' -exec truncate -s 0 {} +
ExecStartPre=/usr/local/bin/xray run -test -confdir $XRAY_JSONS_PATH
ExecStart=/usr/local/bin/xray run -confdir $XRAY_JSONS_PATH
Restart=on-failure
RestartSec=5s
WorkingDirectory=/opt/xray
SuccessExitStatus=0
StandardOutput=journal
StandardError=journal
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
EOF

  if [[ -f "$override_file" ]]; then
    log "OK" "Override-файл создан: $override_file"
  else
    log "ERROR" "Override-файл не был создан"
    return 1
  fi

  log "INFO" "Перезагрузка systemd-демонов"
  systemctl daemon-reexec && systemctl daemon-reload \
    && log "OK" "Systemd перезагружен" \
    || { log "ERROR" "Не удалось перезагрузить systemd"; return 1; }
}

xray_create_sample_configs() {
  log "INFO" "Создание базового лог-конфига Xray: $XRAY_JSONS_PATH/00_log.json"

  local json_log="$XRAY_JSONS_PATH/00_log.json"
  local json_policy="$XRAY_JSONS_PATH/04_policy.json"
  local json_inbounds="$XRAY_JSONS_PATH/05_inbounds.json.json"

  # Убедимся, что директория существует
  if [[ ! -d "$XRAY_JSONS_PATH" ]]; then
    log "ERROR" "Директория конфигураций отсутствует: $XRAY_JSONS_PATH"
    exit 1
  fi

  if ! cat > "$json_log" <<EOF
{
    "log": {
        "access": "$XRAY_LOG_PATH/access.log",
        "error": "$XRAY_LOG_PATH/error.log",
        "loglevel": "info",
        "dnsLog": true,
        "maskAddress": "quarter"
    }
}
EOF
  then
    log "ERROR" "Ошибка записи в файл: $json_log"
    exit 1
  fi

  if [[ -f "$json_log" ]]; then
    log "OK" "Конфигурационный файл создан: $json_log"
  else
    log "ERROR" "Файл $json_log не был создан"
    exit 1
  fi

  if ! cat > "$json_policy" <<EOF
{
    "policy": {
        "levels": {
            "0": {
                "handshake": 4,
                "connIdle": 300,
                "uplinkOnly": 2,
                "downlinkOnly": 5,
                "statsUserUplink": false,
                "statsUserDownlink": false,
                "statsUserOnline": false,
                "bufferSize": 4
            }
        },
        "system": {
            "statsInboundUplink": false,
            "statsInboundDownlink": false,
            "statsOutboundUplink": false,
            "statsOutboundDownlink": false
        }
    }
}
EOF
  then
    log "ERROR" "Ошибка записи в файл: $json_policy"
    exit 1
  fi

  if [[ -f "$json_policy" ]]; then
    log "OK" "Конфигурационный файл создан: $json_policy"
  else
    log "ERROR" "Файл $json_policy не был создан"
    exit 1
  fi

  if ! cat > "$json_inbounds" <<EOF
{
    "inbounds": [
        {
            "port": 12345,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp,udp",
                "followRedirect": true
            },
            "streamSettings": {
                "sockopt": {
                    "tproxy": "tproxy",
                    "mark": 1
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            },
            "tag": "tproxy"
        },
        {
            "port": 12346,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp",
                "followRedirect": true,
                "mark": 1
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            },
            "tag": "redirect"
        }
    ]
}
EOF
  then
    log "ERROR" "Ошибка записи в файл: $json_inbounds"
    exit 1
  fi

  if [[ -f "$json_inbounds" ]]; then
    log "OK" "Конфигурационный файл создан: $json_inbounds"
  else
    log "ERROR" "Файл $json_inbounds не был создан"
    exit 1
  fi
  
}

xray_setup_log_rotation() {
  log "INFO" "Создание пустых лог-файлов и очистка systemd-журналов"

  local access_log="$XRAY_LOG_PATH/access.log"
  local error_log="$XRAY_LOG_PATH/error.log"

  # Создание лог-файлов
  if install -o "$XRAY_USER" -g nogroup -m 640 /dev/null "$access_log" && \
     install -o "$XRAY_USER" -g nogroup -m 640 /dev/null "$error_log"; then
    log "OK" "Лог-файлы созданы: $access_log, $error_log"
  else
    log "ERROR" "Не удалось создать лог-файлы в $XRAY_LOG_PATH"
    exit 1
  fi

  # Очистка systemd-журнала
  log "INFO" "Очистка systemd журнала для xray.service"
  if journalctl --unit=xray.service --rotate && \
     journalctl --unit=xray.service --vacuum-time=1s; then
    log "OK" "Журналы systemd очищены"
  else
    log "ERROR" "Не удалось очистить systemd journal для xray"
    exit 1
  fi
}

xray_fix_permissions() {
  log "INFO" "Настройка доступа к $XRAY_FOLDER для группы $XRAY_USER_GROUP"

  # Убедиться, что /opt доступен
  chmod 755 /opt 2>/dev/null || true

  # Установить владельца и группу
  chown -R "$XRAY_USER:$XRAY_USER_GROUP" "$XRAY_FOLDER"

  # Установить права доступа
  find "$XRAY_FOLDER" -type d -exec chmod 2775 {} \;  # setgid + rwxrwxr-x
  find "$XRAY_FOLDER" -type f -exec chmod 764 {} \;   # rwxrw-r--

  log "OK" "Права и владельцы установлены для $XRAY_FOLDER с общей группой $XRAY_USER_GROUP"
  log "OK" "Убедись, что нужные пользователи добавлены в $XRAY_USER_GROUP"
}


xray_enable_and_start() {
  xray_fix_permissions

  log "INFO" "Активация и запуск xray.service"

  log "INFO" "Проверка владельца каталога конфигурации"
  ls -ld "$XRAY_FOLDER"

  log "INFO" "Перезапуск systemd-демонов"
  systemctl daemon-reexec && systemctl daemon-reload && log "OK" "Systemd перезапущен" || {
    log "ERROR" "Не удалось перезапустить systemd"
    exit 1
  }

  log "INFO" "Включение автозапуска Xray"
  systemctl enable xray.service && log "OK" "Xray добавлен в автозагрузку" || {
    log "ERROR" "Не удалось включить автозапуск Xray"
    exit 1
  }

  log "INFO" "Запуск Xray"
  if systemctl restart xray.service; then
    log "OK" "Xray запущен"
  else
    log "ERROR" "Ошибка запуска Xray"
    journalctl --no-pager -xeu xray.service
    systemctl status xray.service --no-pager
    exit 1
  fi

  log "INFO" "Проверка статуса xray.service"
  if systemctl is-active --quiet xray.service; then
    log "OK" "Xray работает корректно"
  else
    log "ERROR" "Xray не активен после запуска"
    exit 1
  fi
}

xray_print_final_info() {
  echo
  log "OK" "Xray успешно установлен и запущен"

  echo -e "\n[i] Пути и конфигурация:"
  echo "    ├─ Бинарник:      /usr/local/bin/xray"
  echo "    ├─ Конфиги:       $XRAY_JSONS_PATH"
  echo "    ├─ Логи:          $XRAY_LOG_PATH"
  echo "    └─ Запуск от:     user: $XRAY_USER, groop: $XRAY_USER_GROUP"

  echo -e "\n[i] Версия Xray:"
  if /usr/local/bin/xray version; then
    :
  else
    log "WARN" "Не удалось получить версию Xray"
  fi

  echo -e "\n[i] Статус systemd:"
  if systemctl status xray.service --no-pager; then
    :
  else
    log "WARN" "Не удалось получить статус systemd"
  fi

  echo -e "\n[✔] Установка завершена."
}
