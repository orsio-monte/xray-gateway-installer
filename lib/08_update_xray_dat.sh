#!/bin/bash

generate_xray_dat_update() {
  local SCRIPT_NAME="xray-dat-update.sh"
  local TEMPLATE_NAME="xray-dat-update.template.sh"
  local TARGET_DIR="/opt/xray/dat-check"
  local TARGET_FILE="$TARGET_DIR/$SCRIPT_NAME"
  local TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE_NAME"
  local GITHUB_TEMPLATE_URL="$GITHUB_REPO_RAW/templates/$TEMPLATE_NAME"

  log INFO "Генерация скрипта обновления GeoIP/GeoSite: $SCRIPT_NAME"

  mkdir -p "$TARGET_DIR"
  chown "$XRAY_USER:$XRAY_USER_GROUP" "$TARGET_DIR"

  # Получение шаблона: локально или с GitHub
  local TMP_TEMPLATE
  TMP_TEMPLATE="$(mktemp)"

  if [[ -f "$TEMPLATE_PATH" ]]; then
    cp "$TEMPLATE_PATH" "$TMP_TEMPLATE"
    log OK "Шаблон найден локально: $TEMPLATE_PATH"
  else
    log WARN "Локальный шаблон не найден, пробуем загрузить с GitHub: $GITHUB_TEMPLATE_URL"
    local success=false
    for attempt in {1..3}; do
      if curl -fsSL "$GITHUB_TEMPLATE_URL" -o "$TMP_TEMPLATE"; then
        log OK "Шаблон успешно загружен (попытка $attempt)"
        success=true
        break
      else
        log WARN "Не удалось загрузить шаблон (попытка $attempt), повтор через 2 секунды..."
        sleep 2
      fi
    done

    if [[ "$success" != true ]]; then
      log ERROR "Ошибка загрузки шаблона с GitHub после 3 попыток"
      rm -f "$TMP_TEMPLATE"
      exit 1
    fi
  fi
  
  # Генерация скрипта из шаблона
  local TMP_FILE
  TMP_FILE="$(mktemp)"

  sed -e "s#__XRAY_FOLDER__#$XRAY_FOLDER#g" \
      -e "s#__XRAY_USER__#$XRAY_USER#g" \
      -e "s#__XRAY_USER_GROUP__#$XRAY_USER_GROUP#g" \
      "$TMP_TEMPLATE" > "$TMP_FILE"
  rm -f "$TMP_TEMPLATE"

  if [[ -f "$TARGET_FILE" ]] && cmp -s "$TMP_FILE" "$TARGET_FILE"; then
    log INFO "Скрипт не изменился — обновление не требуется"
    rm -f "$TMP_FILE"
  else
    mv "$TMP_FILE" "$TARGET_FILE"
    chmod +x "$TARGET_FILE"
    chown "$XRAY_USER:$XRAY_USER_GROUP" "$TARGET_FILE"
    log OK "Скрипт создан или обновлён: $TARGET_FILE"
  fi

  log INFO "Первичный запуск в режиме -ci для добавления cron"
  "$TARGET_FILE" -ci
}
