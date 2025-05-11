[![Last Commit](https://img.shields.io/github/last-commit/Torotin/xray-gateway-installer)](https://github.com/Torotin/xray-gateway-installer/commits)
<!-- Дополнительные проекты -->
[![Debian](https://img.shields.io/badge/platform-Debian_12+-A81D33?logo=debian)](https://www.debian.org/)
[![Xray-core](https://img.shields.io/badge/Xray--core-%F0%9F%94%A5-7B16FF?logo=linux)](https://github.com/XTLS/Xray-core)
[![XKeen (Skrill0)](https://img.shields.io/badge/XKeen-Skrill0-FF8800?logo=github)](https://github.com/Skrill0/XKeen)
[![XKeen (Corvus-Malus)](https://img.shields.io/badge/XKeen-Corvus--Malus-FF5500?logo=github)](https://github.com/Corvus-Malus/XKeen)
[![AntiFilter-IP](https://img.shields.io/badge/GeoIP-AntiFilter--IP-22AA88?logo=ipfs)](https://github.com/Skrill0/AntiFilter-IP)
[![AntiFilter-Domains](https://img.shields.io/badge/Geosite-AntiFilter--Domains-229977?logo=dns)](https://github.com/Skrill0/AntiFilter-Domains)
[![zkeen-ip](https://img.shields.io/badge/GeoIP-zkeen--ip-5C4EE5?logo=server)](https://github.com/jameszeroX/zkeen-ip)
[![zkeen-domains](https://img.shields.io/badge/Geosite-zkeen--domains-3F74D1?logo=server)](https://github.com/jameszeroX/zkeen-domains)
[![v2fly geoip](https://img.shields.io/badge/GeoIP-v2fly-lightgrey?logo=cloudflare)](https://github.com/v2fly/geoip)
[![v2fly geosite](https://img.shields.io/badge/Geosite-v2fly-lightgrey?logo=cloudflare)](https://github.com/v2fly/domain-list-community)
[![AntiZapret](https://img.shields.io/badge/GeoDB-AntiZapret-7777DD?logo=lock)](https://github.com/savely-krasovsky/antizapret-sing-box)
[![RunetFreedom GeoIP](https://img.shields.io/badge/Blocked--IP-RunetFreedom-DD5555?logo=bancontact)](https://github.com/runetfreedom/russia-blocked-geoip)
[![RunetFreedom Geosite](https://img.shields.io/badge/Blocked--Domains-RunetFreedom-CC4444?logo=bancontact)](https://github.com/runetfreedom/russia-blocked-geosite)

# Xray Gateway Installer

**Xray Gateway Installer** — это автоматизированный установщик клиента [Xray-core](https://github.com/XTLS/Xray-core) с полной маршрутизацией всего исходящего трафика через прокси на основе `iptables` и `TProxy`.

Создан для **простого развёртывания** на Debian 12+ в роли шлюза, с максимальной автоматизацией и надёжной обработкой сетевых сценариев, включая исключения, fallback-режим и защиту от сбоев сети.

## Для чего нужен?

Проект предназначен для:

* организации **прозрачного туннелирования** всего трафика через V2Ray/Xray,
* использования шлюза в **локальной сети** или на **виртуальной машине** (например, Proxmox),
* автоматического применения правил с изоляцией от ручной настройки сети и `iptables`.

## Основные возможности

* Установка `Xray-core` в `/opt/xray`, запуск от пользователя `xray:xray`.
* Автоматическая генерация systemd unit-файлов (`xray.service`, `xray-iptables.service`).
* TProxy-маршрутизация для UDP, REDIRECT для TCP, с поддержкой `fwmark`, `ip rule`, `ip route`.
* Полная маршрутизация трафика через Xray:

  * с автоматическим определением интерфейсов,
  * с исключениями по IP, CIDR, портам,
  * с автозащитой локальных подсетей.
* Fallback-цепочка `XRAY_DISABLED` (DROP), если Xray отключён.
* Обновление GRUB, `sysctl`, включение IP Forward, модули ядра `xt_TPROXY`, `nf_tproxy_core`.
* Создание административного пользователя с SSH-ключом (опционально).
* Цветной лог, проверка ошибок, диагностика шагов.
* Генерация дампа текущих интерфейсов на случай потери сети.


## Быстрый старт

### Установка

```bash
git clone https://github.com/Torotin/xray-gateway-installer.git
cd xray-gateway-installer
chmod +x ./install.sh
sudo ./install.sh
```

> 💡 В процессе скрипт автоматически:
>
> * создаст пользователя `xray`;
> * установит бинарник Xray в `/opt/xray`;
> * создаст конфиги и логи;
> * применит системные настройки (`GRUB`, `sysctl`);
> * активирует маршрутизацию через `iptables` и `TProxy`;
> * установит все необходимые зависимости.

## Проверка работы

После установки проверь, что службы работают:

```bash
systemctl status xray
systemctl status xray-iptables
```

### 🛠 Конфиги

Все json-конфигурации Xray находятся в:

```bash
/opt/xray/configs/*.json
```

После редактирования конфигов — обязательно перезапусти службу:

```bash
sudo systemctl restart xray
```


## 🛑 Исключения из маршрутизации

Файлы для исключений:

* `xray-exclude-iptables.cidrs` — подсети
* `xray-exclude-iptables.ips` — IP-адреса
* `xray-exclude-iptables.ports` — порты

После изменения:

```bash
sudo /opt/xray/iptables/xray-iptables.sh restart
```

## ❗️ Изменение имени интерфейса после перезагрузки

При изменении параметров `GRUB` (например, отключении `predictable interface names`), после перезагрузки интерфейс может смениться (`ens18` → `eth0` и т.п.).

Скрипт заранее сохраняет список интерфейсов в `network-ifaces.dump`.

### Восстановление сети:

1. Открыть консоль Proxmox/VM.
2. Найти актуальное имя интерфейса (`ip a`).
3. Обновить `/etc/network/interfaces`.
4. Применить: `systemctl restart networking`.

## 📁 Структура проекта

```text
xray-gateway-installer/
├── install.sh                       # Главный установочный скрипт
├── lib/                             # Модули (по этапам установки)
│   ├── 01_common.sh                 # Общие функции (права, окружение)
│   ├── 02_network.sh                # Обнаружение интерфейсов, дамп сети
│   ├── 03_grub.sh                   # Обновление параметров загрузки
│   ├── 04_admin_user.sh             # Создание администратора и SSH-ключа
│   ├── 05_sysctl.sh                 # Настройка sysctl и ip_forward
│   ├── 06_xray_core.sh              # Установка Xray-core и systemd unit
│   └── 07_xray_iptables.sh          # Настройка iptables, TProxy, systemd
├── network-ifaces.dump              # Дамп текущих сетевых интерфейсов перед изменениями
└── template/
    ├── xray-iptables.template.sh    # Шаблон скрипта xray-iptables
    └── xray-dat-update.template.sh  # Шаблон скрипта xray-dat-update
```

## 🌍 Обновление GeoIP/GeoSite баз

Скрипт поддерживает **автоматическое обновление** баз:

* [`geoip.dat`](https://github.com/v2fly/geoip) — IP-диапазоны по странам
* [`geosite.dat`](https://github.com/v2fly/domain-list-community) — доменные группы (Google, Ads, Telegram и др.)

Также поддерживаются альтернативные источники (AntiFilter, zkeen и др.).

### 🛠 Автоматическая настройка

При установке создаётся и настраивается скрипт:

```bash
/opt/xray/tools/xray-dat-update.sh
```

Он:

* проверяет наличие обновлений по `ETag` и `SHA256`,
* скачивает и сохраняет `.dat`-файлы,
* валидирует и перезапускает службу `xray` при необходимости.

### 🔁 Добавление в `cron`

Для автоматического запуска используется `cron`. При первом запуске предлагается выбрать:

```bash
sudo /opt/xray/tools/xray-dat-update.sh -ci
```

Скрипт предложит:

* день недели,
* ежедневный режим,
* отключение расписания.

Можно изменить расписание позже через:

```bash
crontab -e
```

Пример строки в `cron` (ежедневно в 04:00):

```cron
0 4 * * * /opt/xray/tools/xray-dat-update.sh >> /opt/xray/logs/xray-dat-update.log 2>&1
```

### 📦 Источники поддерживаемых баз

| Название               | Тип     | Источник                                                                                         |
|------------------------|---------|--------------------------------------------------------------------------------------------------|
| `geoip_v2fly.dat`      | ![geoip](https://img.shields.io/badge/-geoip-blue?labelColor=gray) | [![v2fly](https://img.shields.io/badge/v2fly-geoip-blue?logo=github)](https://github.com/v2fly/geoip) |
| `geosite_v2fly.dat`    | ![geosite](https://img.shields.io/badge/-geosite-blueviolet?labelColor=gray) | [![v2fly](https://img.shields.io/badge/v2fly-geosite-blueviolet?logo=github)](https://github.com/v2fly/domain-list-community) |
| `geoip_antifilter.dat` | ![geoip](https://img.shields.io/badge/-geoip-green?labelColor=gray) | [![AntiFilter-IP](https://img.shields.io/badge/Skrill0-AntiFilter--IP-green?logo=github)](https://github.com/Skrill0/AntiFilter-IP) |
| `geosite_antifilter.dat` | ![geosite](https://img.shields.io/badge/-geosite-green?labelColor=gray) | [![AntiFilter-Domains](https://img.shields.io/badge/Skrill0-AntiFilter--Domains-green?logo=github)](https://github.com/Skrill0/AntiFilter-Domains) |
| `geoip_zkeen.dat`      | ![geoip](https://img.shields.io/badge/-geoip-5C4EE5?labelColor=gray) | [![zkeen-ip](https://img.shields.io/badge/jameszeroX-zkeen--ip-5C4EE5?logo=github)](https://github.com/jameszeroX/zkeen-ip) |
| `geosite_zkeengeo.dat` | ![geosite](https://img.shields.io/badge/-geosite-3F74D1?labelColor=gray) | [![zkeen-domains](https://img.shields.io/badge/jameszeroX-zkeen--domains-3F74D1?logo=github)](https://github.com/jameszeroX/zkeen-domains) |
| `geoip_antizapret.dat` | ![geoip](https://img.shields.io/badge/-geoip-7777DD?labelColor=gray) | [![AntiZapret](https://img.shields.io/badge/AntiZapret-geoip-7777DD?logo=github)](https://github.com/savely-krasovsky/antizapret-sing-box) |
| `geosite_antizapret.dat` | ![geosite](https://img.shields.io/badge/-geosite-7777DD?labelColor=gray) | [![AntiZapret](https://img.shields.io/badge/AntiZapret-geosite-7777DD?logo=github)](https://github.com/savely-krasovsky/antizapret-sing-box) |
| `geoip_russia-blocked.dat` | ![geoip](https://img.shields.io/badge/-geoip-DD5555?labelColor=gray) | [![RunetFreedom](https://img.shields.io/badge/RunetFreedom-geoip-DD5555?logo=github)](https://github.com/runetfreedom/russia-blocked-geoip) |
| `geosite_russia-blocked.dat` | ![geosite](https://img.shields.io/badge/-geosite-CC4444?labelColor=gray) | [![RunetFreedom](https://img.shields.io/badge/RunetFreedom-geosite-CC4444?logo=github)](https://github.com/runetfreedom/russia-blocked-geosite) |




## 📖 FAQ

### ❓ Скрипт завис на определении интерфейса, что делать?

Проверь, что у системы **есть активный IPv4-интерфейс**. Если присутствует только IPv6 — автоматическое определение может завершиться неудачей.

```bash
ip -o -4 addr show scope global
```

Также проверь конфигурацию сети:

```bash
cat /etc/network/interfaces
```

Пример корректной настройки:

```ini
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp
```

Убедись, что:

* интерфейс указан верно (`auto eth0`, `iface eth0 inet dhcp`);
* интерфейс поднят (`ip link show eth0` → state UP);
* в `/etc/network/interfaces` нет конфликтующих записей.

Если интерфейс не определяется автоматически, можно временно задать его вручную перед запуском установки:

```bash
export LAN_IF="eth0"
```

Затем перезапусти `install.sh`.

---

### ❓ Как проверить, что весь трафик действительно проходит через Xray?

1. Убедитесь, что `xray-iptables` и `xray` активны:

   ```bash
   systemctl status xray xray-iptables
   ```

2. Проверьте логи Xray (например, DNS-запросы или outbound):

   ```bash
   journalctl -u xray -e
   ```

3. Используйте сайт [https://ipleak.net](https://ipleak.net) с устройства, чей трафик маршрутизируется через шлюз.

---

### ❓ Как полностью отключить маршрутизацию через Xray?

Просто остановите службу:

```bash
sudo systemctl stop xray
```

Трафик начнёт **дропаться**, если включена fallback-цепочка `XRAY_DISABLED`.

Если хотите разрешить трафик в обход Xray, временно отключите `xray-iptables`:

```bash
sudo systemctl stop xray-iptables
```

---

### ❓ Как вручную обновить базы `geoip.dat` и `geosite.dat`?

```bash
sudo /opt/xray/tools/xray-dat-update.sh
```

Если базы не изменились — они не будут перезаписаны.

---

### ❓ Как отключить автоматическое обновление GeoIP/GeoSite?

Открой `cron`:

```bash
crontab -e
```

И удалите строку, начинающуюся с `/opt/xray/tools/xray-dat-update.sh`.


## 🔗 Связанные проекты и источники

> Проект использует или интегрирует данные из следующих репозиториев:

| Название проекта                | Назначение                                                  | Проект (ссылка)                                                                                   | Последний коммит                                 |
| ------------------------------ | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Xray-core**                   | Основной прокси-движок (VLESS, VMess, Trojan и др.)         | [![Xray-core](https://img.shields.io/badge/Xray--core-Repo-7B16FF?logo=github)](https://github.com/XTLS/Xray-core) | ![last](https://img.shields.io/github/last-commit/XTLS/Xray-core) |
| **XKeen (от Skrill0)**          | Скрипты маршрутизации с TProxy, inspiration source          | [![XKeen](https://img.shields.io/badge/XKeen-Skrill0-FF8800?logo=github)](https://github.com/Skrill0/XKeen) | ![last](https://img.shields.io/github/last-commit/Skrill0/XKeen) |
| **XKeen (от Corvus-Malus)**     | Форк XKeen с расширенной логикой                            | [![XKeen](https://img.shields.io/badge/XKeen-Corvus--Malus-FF5500?logo=github)](https://github.com/Corvus-Malus/XKeen) | ![last](https://img.shields.io/github/last-commit/Corvus-Malus/XKeen) |
| **AntiFilter-IP**               | GeoIP-база от AntiFilter                                    | [![AF-IP](https://img.shields.io/badge/AntiFilter--IP-Repo-22AA88?logo=github)](https://github.com/Skrill0/AntiFilter-IP) | ![last](https://img.shields.io/github/last-commit/Skrill0/AntiFilter-IP) |
| **AntiFilter-Domains**          | Geosite-база от AntiFilter                                  | [![AF-Domains](https://img.shields.io/badge/AntiFilter--Domains-Repo-229977?logo=github)](https://github.com/Skrill0/AntiFilter-Domains) | ![last](https://img.shields.io/github/last-commit/Skrill0/AntiFilter-Domains) |
| **zkeen-ip**                    | zkeen GeoIP-база                                   | [![zkeen-ip](https://img.shields.io/badge/zkeen--ip-Repo-5C4EE5?logo=github)](https://github.com/jameszeroX/zkeen-ip) | ![last](https://img.shields.io/github/last-commit/jameszeroX/zkeen-ip)   |
| **zkeen-domains**               | zkeen GeoSite-база                                 | [![zkeen-domains](https://img.shields.io/badge/zkeen--domains-Repo-3F74D1?logo=github)](https://github.com/jameszeroX/zkeen-domains) | ![last](https://img.shields.io/github/last-commit/jameszeroX/zkeen-domains) |
| **v2fly geoip**                 | Официальная GeoIP-база                                      | [![v2fly-geoip](https://img.shields.io/badge/v2fly--geoip-Repo-lightgray?logo=github)](https://github.com/v2fly/geoip) | ![last](https://img.shields.io/github/last-commit/v2fly/geoip) |
| **v2fly domain-list-community** | Официальная GeoSite                                         | [![v2fly-dlc](https://img.shields.io/badge/domain--list--community-Repo-lightgray?logo=github)](https://github.com/v2fly/domain-list-community) | ![last](https://img.shields.io/github/last-commit/v2fly/domain-list-community) |
| **AntiZapret (sing-box)**       | GeoIP/Geosite-базы `.db` AntiZapret                         | [![antizapret](https://img.shields.io/badge/AntiZapret-Repo-7777DD?logo=github)](https://github.com/savely-krasovsky/antizapret-sing-box) | ![last](https://img.shields.io/github/last-commit/savely-krasovsky/antizapret-sing-box) |
| **RunetFreedom: GeoIP**         | Официальный источник российских GeoIP файлов для v2rayN     | [![rf-geoip](https://img.shields.io/badge/RunetFreedom--GeoIP-Repo-DD5555?logo=github)](https://github.com/runetfreedom/russia-blocked-geoip) | ![last](https://img.shields.io/github/last-commit/runetfreedom/russia-blocked-geoip) |
| **RunetFreedom: Geosite**       | Официальный источник российских Geosite файлов для v2rayN   | [![rf-geosite](https://img.shields.io/badge/RunetFreedom--Geosite-Repo-CC4444?logo=github)](https://github.com/runetfreedom/russia-blocked-geosite) | ![last](https://img.shields.io/github/last-commit/runetfreedom/russia-blocked-geosite) |





## 🧬 Лицензия и поддержка

> [!WARNING]
> Данный проект предоставляется исключительно в _**научно-исследовательских, технических и некоммерческих целях**_.
>
> _**Коммерческое использование запрещено.**_
>
> Автор **не несёт ответственности** за любое противоправное или недобросовестное использование данного программного обеспечения.
>
> Если вы **не согласны с этими условиями**, немедленно удалите все материалы, полученные из данного репозитория, со своих устройств.

---

* 🔐 **Тип лицензии:** [📄 Custom Research License](LICENSE.md) — лицензия для личного и исследовательского использования
* ⚠ **Ограничения:** запрещено использовать в коммерческих продуктах, облачных сервисах, VPN и иных платных решениях
* 🛠 **Ответственность:** полная ответственность за соблюдение законодательства лежит на пользователе
* 📬 **Обратная связь:** предложения и вопросы — через [Issues на GitHub](https://github.com/Torotin/xray-gateway-installer/issues)

