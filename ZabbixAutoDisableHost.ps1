# ======= Настройки =======
function funcrep($param1) {
    if ($null -eq $param1) { return $param1 }
    $param1 = $param1.Trim()
    if ($param1 -match '~') {
        return $param1.Replace('~', ' ')
    } else {
        return $param1
    }
}

# ======= Функция отправки email =======
function Send-EmailAlert {
    param(
        [string]$ToAddress,
        [string]$Subject,
        [string]$Body
    )
    
    try {
        # Параметры SMTP
        $SmtpServer = "SmtpServer"
        $SmtpPort = 587
        $FromAddress = "SmtpServer_Address"
        $Username = "SmtpServer_Username"
        $Password = "SmtpServer_Password"
        
        # Создание SMTP клиента
        $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $SmtpClient.EnableSsl = $true
        $SmtpClient.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
        
        # Создание сообщения
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $MailMessage.From = $FromAddress
        $MailMessage.To.Add($ToAddress)
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body
        $MailMessage.IsBodyHtml = $false
        
        # Отправка сообщения
        $SmtpClient.Send($MailMessage)
        Write-Host "Email alert sent successfully to: $ToAddress"
    }
    catch {
        Write-Host "ERROR: Failed to send email alert: $_"
    }
    finally {
        if ($SmtpClient) { $SmtpClient.Dispose() }
        if ($MailMessage) { $MailMessage.Dispose() }
    }
}

# Аргументы
$HOSTNAME   = "MDC test"
$POC_NAME   = "MDC test"
$POC_EMAIL  = "MDC test"
$URL_SD     = "MDC test"

# Настройка обхода SSL (осторожно: только для тестов!)
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# ======= Функция для получения hostid =======
function Get-HostIdByName {
    param (
        [string]$hostname,
        [string]$apiUrl,
        [string]$apiToken
    )
    $headers = @{
        "Content-Type" = "application/json; charset=utf-8"
        "Authorization" = "Bearer $apiToken"
    }
    $body = @{
        jsonrpc = "2.0"
        method = "host.get"
        params = @{
            output = @("hostid", "host")  # полезно для отладки
            search = @{ host = "*$hostname*" }
            searchWildcardsEnabled = $true
        }
        id = 1
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType "application/json; charset=utf-8"
        if ($response.error) {
            throw "API Error: $($response.error)"
        }
        if (-not $response.result -or $response.result.Count -eq 0) {
            throw "HostNotFound"
        }
        # Берём первый найденный хост (можно улучшить логику, если нужно точнее)
        return $response.result[0].hostid
    }
    catch {
        if ($_.Exception.Message -like "*HostNotFound*") {
            throw "HostNotFound"
        } else {
            throw "Request failed: $_"
        }
    }
}

# ======= Функция отключения хоста =======
function Disable-Host {
    param (
        [string]$hostid,
        [string]$apiUrl,
        [string]$apiToken,
        [string]$pocName,
        [string]$pocEmail,
        [string]$urlSd
    )
    $headers = @{
        "Content-Type" = "application/json; charset=utf-8"
        "Authorization" = "Bearer $apiToken"
    }
    $body = @{
        jsonrpc = "2.0"
        method = "host.update"
        params = @{
            hostid = $hostid
            status = 1
            inventory_mode = 1
            inventory = @{
                poc_1_name      = $pocName
                poc_1_email     = $pocEmail
                notes           = ""
                poc_1_phone_a   = ""
                poc_1_phone_b   = ""
                url_b           = $urlSd
            }
        }
        id = 2
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType "application/json; charset=utf-8"
        if ($response.error) {
            throw "API Error: $($response.error)"
        }
        return $response
    }
    catch {
        throw "Disable request failed: $_"
    }
}

# ======= Основной блок =======
$ZABBIX_MAIN_URL  = "https://zabbix.ru/api_jsonrpc.php"
$ZABBIX_MAIN_TOKEN = "Токен"

$ZABBIX_PRE_URL   = "https://prezabbix.ru/api_jsonrpc.php"
$ZABBIX_PRE_TOKEN  = "Токен"

# Email настройки (можно изменить получателя)
$AlertEmailTo = $POC_EMAIL  # Отправляем на email из параметров, или можно указать фиксированный

$hostid = $null
$usedApiUrl = $null
$usedApiToken = $null
$scriptSuccess = $false
$errorMessage = ""

try {
    Write-Host "Trying to find host '$HOSTNAME' in main Zabbix..."
    $hostid = Get-HostIdByName -hostname $HOSTNAME -apiUrl $ZABBIX_MAIN_URL -apiToken $ZABBIX_MAIN_TOKEN
    $usedApiUrl = $ZABBIX_MAIN_URL
    $usedApiToken = $ZABBIX_MAIN_TOKEN
    Write-Host "Found in main Zabbix. Host ID: $hostid"
}
catch {
    if ($_.Exception.Message -like "*HostNotFound*") {
        Write-Host "Host not found in main Zabbix. Trying prezabbix..."
        try {
            $hostid = Get-HostIdByName -hostname $HOSTNAME -apiUrl $ZABBIX_PRE_URL -apiToken $ZABBIX_PRE_TOKEN
            $usedApiUrl = $ZABBIX_PRE_URL
            $usedApiToken = $ZABBIX_PRE_TOKEN
            Write-Host "Found in prezabbix. Host ID: $hostid"
        }
        catch {
            $errorMessage = "Host '$HOSTNAME' not found in either Zabbix or prezabbix. Error: $($_.Exception.Message)"
            Write-Host "Error: $errorMessage"
            throw
        }
    } else {
        $errorMessage = "Error during main Zabbix lookup: $($_.Exception.Message)"
        Write-Host "Error: $errorMessage"
        throw
    }
}

# Отключаем хост в соответствующем Zabbix
try {
    Write-Host "Disabling host '$HOSTNAME' in $($usedApiUrl -replace 'https://','' -replace '/.*')..."
    $result = Disable-Host -hostid $hostid -apiUrl $usedApiUrl -apiToken $usedApiToken -pocName $POC_NAME -pocEmail $POC_EMAIL -urlSd $URL_SD
    Write-Host "Host has been successfully disabled and inventory updated."
    $scriptSuccess = $true
}
catch {
    $errorMessage = "Error disabling host: $($_.Exception.Message)"
    Write-Host "Error: $errorMessage"
    throw
}
finally {
    # Если скрипт завершился с ошибкой, отправляем email алерт
    if (-not $scriptSuccess) {
        $emailSubject = "ALERT: Zabbix Host Disable Script Failed - $HOSTNAME"
        $emailBody = @"
Zabbix Host Disable Script Execution Failed

Hostname: $HOSTNAME
POC Name: $POC_NAME
POC Email: $POC_EMAIL
URL SD: $URL_SD

Error Details:
$errorMessage

Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Script: $($MyInvocation.MyCommand.Path)
"@
        
        Write-Host "Sending email alert about script failure..."
        Send-EmailAlert -ToAddress $AlertEmailTo -Subject $emailSubject -Body $emailBody
    } else {
        Write-Host "Script completed successfully. No alert needed."
    }
}

# Если мы дошли до этой точки и успех - выходим с кодом 0
if ($scriptSuccess) {
    exit 0
} else {
    exit 1
}
