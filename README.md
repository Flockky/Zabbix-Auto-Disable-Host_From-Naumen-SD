# 🤖 Zabbix Host Auto-Disable Script

> PowerShell-скрипт для автоматического отключения хостов в Zabbix по запросу из **Naumen Service Desk**

---

## 📋 Описание

Скрипт предназначен для автоматизации процесса отключения хостов в Zabbix (Production и Pre-Production) при поступлении соответствующего запроса из системы учёта заявок **Naumen Service Desk**.

### 🔹 Основные возможности:
- ✅ Поиск хоста по имени в двух инстансах Zabbix (основной и pre)
- ✅ Отключение хоста (`status = 1`) и обновление инвентарных данных через Zabbix API
- ✅ Отправка уведомлений об ошибках выполнения по email (SMTP)
- ✅ Корректные коды возврата (`exit 0` / `exit 1`) для интеграции с внешними системами
- ✅ Обработка параметров с заменой `~` на пробел (для совместимости с Naumen SD)
- ✅ Поддержка TLS 1.2 и обход проверки сертификатов *(только для тестов!)*

---

## ⚙️ Требования

| Компонент | Версия / Примечание |
|-----------|---------------------|
| PowerShell | 5.1+ / 7.x |
| Zabbix | 6.0+ (API v2.0, метод `host.get`, `host.update`) |
| Naumen Service Desk | Интеграция через вызов PowerShell-скрипта |
| Сеть | Доступ к Zabbix API (`/api_jsonrpc.php`) и SMTP-серверу |

---

## 🗂️ Структура конфигурации

### 🔐 Секция настроек (в начале скрипта)

```powershell
# ======= Настройки =======
$ZABBIX_MAIN_URL   = "https://zabbix.ru/api_jsonrpc.php"
$ZABBIX_MAIN_TOKEN = "ВАШ_ТОКЕН"

$ZABBIX_PRE_URL    = "https://prezabbix.ru/api_jsonrpc.php"
$ZABBIX_PRE_TOKEN  = "ВАШ_ТОКЕН"

# SMTP настройки
$SmtpServer        = "smtp.yourcompany.ru"
$SmtpPort          = 587
$FromAddress       = "noreply@yourcompany.ru"
$Username          = "smtp_user"
$Password          = "smtp_password"  # ⚠️ Рекомендуется использовать защищённое хранение!
```

### 📨 Параметры, передаваемые из Naumen SD

| Переменная | Описание | Пример |
|------------|----------|--------|
| `$HOSTNAME` | Имя хоста в Zabbix | `srv-app-01` |
| `$POC_NAME` | Контактное лицо (имя) | `Иванов Иван` |
| `$POC_EMAIL` | Email для уведомлений | `ivanov@company.ru` |
| `$URL_SD` | Ссылка на заявку в Naumen | `https://sd.company.ru/request/12345` |

> 💡 Символ `~` в параметрах автоматически заменяется на пробел функцией `funcrep()`.

---

## 🚀 Использование

### ▶️ Запуск вручную (тестирование)

```powershell
.\Disable-ZabbixHost.ps1
```

### ▶️ Интеграция с Naumen Service Desk

1. Создайте действие/сценарий в Naumen SD, вызывающий скрипт:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File "C:\Scripts\Disable-ZabbixHost.ps1"
   ```
2. Передайте параметры через аргументы или окружение:
   ```powershell
   -HOSTNAME "{hostname}" -POC_NAME "{poc_name}" -POC_EMAIL "{poc_email}" -URL_SD "{sd_url}"
   ```
3. Настройте обработку кодов возврата:
   - `0` — успех
   - `1` — ошибка (триггерит уведомление и логирование)

---

## 🔌 Работа с Zabbix API

### Методы, используемые в скрипте:

| Метод | Назначение | Документация |
|-------|------------|--------------|
| `host.get` | Поиск hostid по имени хоста | [Zabbix API: host.get](https://www.zabbix.com/documentation/current/ru/manual/api/reference/host/get) |
| `host.update` | Отключение хоста и обновление инвентаря | [Zabbix API: host.update](https://www.zabbix.com/documentation/current/ru/manual/api/reference/host/update) |

### 🔑 Токен доступа
- Создайте токен в **Zabbix → Administration → API tokens**
- Минимальные права: `Read` + `Write` для объектов `Host`
- ⚠️ Не храните токен в открытом виде в продакшене — используйте защищённые хранилища (Vault, Windows Credential Manager)

---

## 📧 Уведомления об ошибках

При сбое скрипт автоматически отправляет email с деталями:

```
Тема: ALERT: Zabbix Host Disable Script Failed - srv-app-01

Содержимое:
- Имя хоста, контактные данные, ссылка на заявку
- Текст ошибки и стек трейс
- Временная метка и путь к скрипту
```

---

## 🧪 Тестирование

1. Проверьте доступность API:
   ```powershell
   Invoke-WebRequest -Uri "https://zabbix.ru/api_jsonrpc.php" -Method Head
   ```
2. Протестируйте поиск хоста:
   ```powershell
   Get-HostIdByName -hostname "test-host" -apiUrl $ZABBIX_MAIN_URL -apiToken $ZABBIX_MAIN_TOKEN
   ```
3. Запустите скрипт в режиме отладки:
   ```powershell
   Set-PSDebug -Trace 1
   .\Disable-ZabbixHost.ps1
   ```

---

## 🛠️ Устранение неполадок

| Проблема | Возможная причина | Решение |
|----------|-------------------|---------|
| `HostNotFound` | Хост не найден в обоих инстансах | Проверьте точное имя хоста в Zabbix |
| `401 Unauthorized` | Неверный/истёкший токен | Пересоздайте API-токен в Zabbix |
| `SMTP connection failed` | Блокировка порта/неверные учётные данные | Проверьте настройки SMTP и брандмауэр |
| `SSL handshake failed` | Самоподписанный сертификат | Для тестов: оставьте `TrustAllCertsPolicy`, для прода — установите доверенный сертификат |
