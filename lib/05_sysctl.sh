#!/usr/bin/env bash

configure_sysctl() {
  log "INFO" "Создание sysctl-конфигурации в $SYSCTL_CONF"

  cat > "$SYSCTL_CONF" <<EOF
##################### Ядро сети и производительность #####################
# Алгоритм очередей по умолчанию для интерфейсов.
# fq (Fair Queueing) - распределение трафика для уменьшения задержек.
# Значение по умолчанию: pfifo_fast.
net.core.default_qdisc = fq

# Алгоритм управления перегрузками TCP.
# Значение по умолчанию: cubic.
net.ipv4.tcp_congestion_control = bbr

# Включение маршрутизации IPv4. Требуется для проксирования. По умолчанию: 0
net.ipv4.ip_forward = 1

# Алгоритм очереди по умолчанию. FQ улучшает равномерность и задержки. По умолчанию: pfifo_fast
net.core.default_qdisc = fq

# Максимальное количество пакетов в очереди интерфейса. По умолчанию: 1000
net.core.netdev_max_backlog = 250000

# Размеры сокетных буферов по умолчанию и максимум. По умолчанию: 212992 / 212992
net.core.rmem_default = 262144
net.core.rmem_max = 134217728
net.core.wmem_default = 262144
net.core.wmem_max = 134217728

##################### UDP буферы #####################
# Используются Xray и TProxy для обработки большого количества UDP трафика
# По умолчанию: 4096 16384 262144
net.ipv4.udp_mem = 65536 131072 262144
# Минимальный приёмный буфер
net.ipv4.udp_rmem_min = 8192
# Минимальный передаваемый буфер
net.ipv4.udp_wmem_min = 8192

##################### TCP ускорение и оптимизация #####################
# Увеличение производительности TCP и уменьшение задержек
# Защита от TIME-WAIT атак
net.ipv4.tcp_rfc1337 = 1
# Минимизация задержек (может отключать bulk throughput оптимизации)
net.ipv4.tcp_low_latency = 1
# Очередь соединений в SYN состоянии (по умолчанию 128)
net.ipv4.tcp_max_syn_backlog = 30000
# Повторное использование TIME-WAIT сокетов (по умолчанию 0)
net.ipv4.tcp_tw_reuse = 1
# Таймаут FIN_WAIT2 (по умолчанию 60)
net.ipv4.tcp_fin_timeout = 15
# Интервал между keepalive (секунд)
net.ipv4.tcp_keepalive_time = 1200
# Кол-во keepalive попыток
net.ipv4.tcp_keepalive_probes = 5
# Интервал между probe
net.ipv4.tcp_keepalive_intvl = 30
# Автоматическое определение MTU
net.ipv4.tcp_mtu_probing = 2
# Включает TCP Fast Open на клиенте и сервере
net.ipv4.tcp_fastopen = 3
# Отключение slow start после простоя
net.ipv4.tcp_slow_start_after_idle = 0
# Selective ACK, улучшает восстановление потерь
net.ipv4.tcp_sack = 1

# Убираем временные метки (для защиты от fingerprinting)
net.ipv4.tcp_timestamps = 0

# Масштабирование окна TCP
net.ipv4.tcp_window_scaling = 1

# Автонастройка recv буфера
net.ipv4.tcp_moderate_rcvbuf = 1

# ECN (Explicit Congestion Notification)
net.ipv4.tcp_ecn = 1

##################### Conntrack (для NAT и TProxy) #####################
# Максимум активных соединений (по умолчанию: 65536 или auto)
net.netfilter.nf_conntrack_max = 262144

# Время хранения соединений в разных состояниях (сек.)
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60

##################### Защита и фильтрация #####################
# SYN cookies — защита от SYN-flood (по умолчанию: 1)
net.ipv4.tcp_syncookies = 1

# Игнорировать широковещательные ICMP (по умолчанию: 1)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ограничить ICMP по частоте (по умолчанию: 1000 мс)
net.ipv4.icmp_ratelimit = 1

# Защита от IP spoofing — обратная фильтрация
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Запрет Source Routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Запрет ICMP Redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

##################### ARP фильтрация #####################
# Обработка ARP-запросов только на интерфейсе, где был получен
net.ipv4.conf.all.arp_filter = 1
net.ipv4.conf.default.arp_filter = 1

##################### Отключение IPv6 полностью #####################
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

EOF

  if [[ -f "$SYSCTL_CONF" ]]; then
    log "OK" "Файл $SYSCTL_CONF создан"
  else
    log "ERROR" "Файл $SYSCTL_CONF не был создан"
    exit 1
  fi

  if sysctl --system; then
    log "OK" "Настройки sysctl применены"
  else
    log "ERROR" "Ошибка применения настроек sysctl"
    exit 1
  fi

  log "INFO" "Проверка ключевых параметров:"

  if sysctl -n net.ipv4.ip_forward | grep -q 1; then
    log "OK" "IP форвардинг включён"
  else
    log "ERROR" "net.ipv4.ip_forward НЕ включён"
    exit 1
  fi

  if sysctl -n net.ipv4.tcp_congestion_control | grep -q bbr; then
    log "OK" "Используется BBR"
  else
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    log "ERROR" "BBR не активен, используется: $current_cc"
    exit 1
  fi

  if sysctl -n net.core.default_qdisc | grep -q fq; then
    log "OK" "qdisc = fq"
  else
    current_qdisc=$(sysctl -n net.core.default_qdisc)
    log "ERROR" "Очередь по умолчанию не fq, а: $current_qdisc"
    exit 1
  fi

}

