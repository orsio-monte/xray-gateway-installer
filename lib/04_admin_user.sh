#!/usr/bin/env bash

setup_admin_user() {
  if [[ "$SKIP_ADMIN_USER_SETUP" == "true" ]]; then
    log "INFO" "Пропуск создания/настройки пользователя $ADMIN_USER (SKIP_ADMIN_USER_SETUP=true)"
    return
  fi

  log "INFO" "Настройка безопасной учётной записи администратора"

  # Предложить пользователю отказаться от настройки
  read -rp "Создать/настроить администратора (рекомендуется)? [Y/n]: " confirm
  confirm="${confirm,,}" # to lowercase

  if [[ "$confirm" == "n" || "$confirm" == "no" ]]; then
    log "WARN" "Создание пользователя администратора пропущено по выбору пользователя"
    return
  fi

  if [[ -z "$ADMIN_USER" ]]; then
    read -rp "Введите имя нового администратора [adminuser]: " input_user
    ADMIN_USER="${input_user:-adminuser}"
  fi

  create_or_update_admin_user
  set_admin_password
  set_admin_ssh_key
  disable_root_access

  log "OK" "Пользователь $ADMIN_USER настроен. root отключён"
}

create_or_update_admin_user() {
  local group_list
  group_list="$(IFS=,; echo "${ADMIN_EXTRA_GROUPS[*]}")"

  if id "$ADMIN_USER" &>/dev/null; then
    log "OK" "Пользователь $ADMIN_USER уже существует"

    while true; do
      read -rp "Обновить пароль и SSH-ключ пользователя $ADMIN_USER? [y/N]: " answer
      case "$answer" in
        [Yy]*) update_user=true; break ;;
        [Nn]*|"") log "INFO" "Пропуск настройки $ADMIN_USER"; return 1 ;;
        *) echo "Пожалуйста, ответьте y или n." ;;
      esac
    done

    usermod -aG "$group_list" "$ADMIN_USER"
    log "OK" "Добавлены группы: $group_list → $ADMIN_USER"
  else
    log "INFO" "Создание пользователя $ADMIN_USER"
    useradd -m -s /bin/bash -G "$group_list" "$ADMIN_USER"
    log "OK" "Пользователь $ADMIN_USER создан с группами: $group_list"
    update_user=true
  fi

  echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
  chmod 440 "/etc/sudoers.d/$ADMIN_USER"
}

set_admin_password() {
  [[ "$update_user" != true ]] && return
  read -rsp "Введите пароль для $ADMIN_USER (ENTER для генерации случайного): " user_pass
  echo
  if [[ -z "$user_pass" ]]; then
    user_pass=$(tr -dc 'A-Za-z0-9@#%+=_' < /dev/urandom | head -c 16)
    log "WARN" "Пароль не введён — сгенерирован случайный: $user_pass"
  fi
  echo "$ADMIN_USER:$user_pass" | chpasswd
}

set_admin_ssh_key() {
  [[ "$update_user" != true ]] && return
  if [[ -z "${ADMIN_SSH_KEY:-}" ]]; then
    IFS= read -r -p "Вставьте публичный SSH ключ (одной строкой): " ADMIN_SSH_KEY
  fi

  if [[ -n "$ADMIN_SSH_KEY" ]]; then
    local ssh_dir="/home/$ADMIN_USER/.ssh"
    mkdir -p "$ssh_dir"
    echo "$ADMIN_SSH_KEY" > "$ssh_dir/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "$ssh_dir/authorized_keys"
    chown -R "$ADMIN_USER:$ADMIN_USER" "$ssh_dir"
    log "OK" "SSH ключ установлен для $ADMIN_USER"
  else
    log "WARN" "Публичный SSH ключ не предоставлен"
  fi
}

disable_root_access() {
  log "INFO" "Отключение root-доступа и shell"
  passwd -l root
  usermod -s /usr/sbin/nologin root

  if grep -q '^#\?PermitRootLogin' /etc/ssh/sshd_config; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  else
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  fi

  systemctl restart sshd
}
