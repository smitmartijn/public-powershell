param (
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$VI_Server,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Platform_OVA,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_OVA,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$License,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Platform_VM_Name,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_VM_Name,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetVMHost,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetDatastore,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$TargetPortGroup,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Platform_IP,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_IP,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Netmask,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Gateway,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$DNS,
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Domain,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NTP,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Web_Proxy_IP,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Web_Proxy_Port,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Syslog,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Telemetry,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Log_Push
)

# Load PowerCLI
if (!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
  if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
    $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
  }
  else {
    $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
  }
  .(join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
if (!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
  Write-Host "VMware modules not loaded/unable to load"
  Exit
}

if (!(Test-Path $Platform_OVA)) {
  Write-Host "[$(Get-Date)] Network Insight Plaform OVA not found! ($Platform_OVA)" -ForegroundColor "red"
  Exit
}

if (!(Test-Path $Proxy_OVA)) {
  Write-Host "[$(Get-Date)] Network Insight Proxt OVA not found! ($Proxy_OVA)" -ForegroundColor "red"
  Exit
}

# Ignore SSL certificate errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

function loginNetworkInsight([string]$Platform_VM_IP)
{

  $POST_Data = @{
    username = 'admin@local'
    password = 'admin'
  }
  $json = $POST_Data | ConvertTo-Json

  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/auth/login" -Method POST -Body $json -ContentType 'application/json' -SessionVariable webSessionJar 
    $global:webSessionJar = $webSessionJar
  } 
  catch 
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Platform VM still initializing, sleeping for 30 seconds and trying again.." -ForegroundColor "yellow"
      Start-Sleep -s 30
      loginNetworkInsight $Platform_VM_IP
    }
    else 
    {
      if($response.message -ne "Logged in") {
        Write-Host "[$(Get-Date)] Unable to login with default credentials!" -ForegroundColor "red" 
        Exit
      }
    }
  }
}

function validateLicense([string]$Platform_VM_IP, [string]$License)
{
  $POST_Data = @{
    licenseKey = $License
  }
  $json = $POST_Data | ConvertTo-Json

  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/management/licensing/validate" -Method POST -Body $json -ContentType 'application/json' -WebSession $global:webSessionJar 
  } 
  catch 
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Platform VM still initializing, sleeping for 30 seconds and trying again.." -ForegroundColor "yellow"
      Start-Sleep -s 30
      validateLicense $Platform_VM_IP $License
    }
  }

  if($response.message -eq "License key is OK") {
    $sockets = $response.data.numberOfSockets
    Write-Host "[$(Get-Date)] License validated for $sockets sockets!" -ForegroundColor "green"
  }
}

function activateLicense([string]$Platform_VM_IP, [string]$License)
{
  $POST_Data = @{
    licenseKey = $License
  }
  $json = $POST_Data | ConvertTo-Json
	
  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/management/licensing/activate" -Method POST -Body $json -ContentType 'application/json' -WebSession $global:webSessionJar
  }
  catch 
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) 
    {
      Write-Host "[$(Get-Date)] Activating the license failed!" -ForegroundColor "red" 
      if($Debug.IsPresent) { $_.Exception.Response }				
      Exit
    }
  }
	
  if($response.message -eq "License applied") {
    Write-Host "[$(Get-Date)] License activated!" -ForegroundColor "green"
  }
}

function generateSharedSecret([string]$Platform_VM_IP)
{
  try {
    $response = Invoke-RestMethod "https://$Platform_VM_IP/api/management/nodes" -Method POST -ContentType 'application/json' -WebSession $global:webSessionJar
  }
  catch 
  {
    if($_.Exception.Response.StatusCode.value__ -ne 200) {
      Write-Host "[$(Get-Date)] Generating the Shared Secret failed!" -ForegroundColor "red"
      if($Debug.IsPresent) { $_.Exception.Response }		
      Exit
    }
  }

  if($response.message -eq "Proxy Key Generated") {
    $shared_secret = $response.data
    Write-Host "[$(Get-Date)] Proxy Shared Secret generated!" -ForegroundColor "green"
  }
	
  return $shared_secret
}
 
if(!(Connect-VIServer -Server $VI_Server)) {
  Write-Host "Unable to connect to vCenter!" -ForegroundColor "red"
  Exit
}


## Get the OVF configuration and fill the parameters
$OvfConfiguration = Get-OvfConfiguration -Ovf $Platform_OVA

$OvfConfiguration.Common.IP_Address.value = $Platform_IP
$OvfConfiguration.Common.Netmask.value = $Netmask
$OvfConfiguration.Common.Default_Gateway.value = $Gateway
$OvfConfiguration.Common.DNS.value = $DNS
$OvfConfiguration.Common.Domain_Search.value = $Domain
$OvfConfiguration.Common.NTP.value = $NTP
$OvfConfiguration.Common.Web_Proxy_IP.value = $Web_Proxy_IP
$OvfConfiguration.Common.Web_Proxy_Port.value = $Web_Proxy_Port
$OvfConfiguration.Common.Rsyslog_IP.value = $Syslog

$OvfConfiguration.NetworkMapping.Vlan256_corp_2.value = (Get-VDPortgroup -Name $TargetPortGroup)

if($Log_Push.IsPresent) { $OvfConfiguration.Common.Log_Push.value = $True }
else { $OvfConfiguration.Common.Log_Push.value = $False }
if($Telemetry.IsPresent) { $OvfConfiguration.Common.Health_Telemetry_Push.value = $True }
else { $OvfConfiguration.Common.Health_Telemetry_Push.value = $False }

# Deploy the OVA.
Write-Host "[$(Get-Date)] Deploying vRealize Network Insight Platform OVA"
Write-Progress -Activity "Deploying vRealize Network Insight Platform OVA"
$VM = Import-vApp -Source $Platform_OVA -OvfConfiguration $OvfConfiguration -Name $Platform_VM_Name -VMHost $TargetVMHost -Datastore $TargetDatastore -DiskStorageFormat Thin

# Testlab edition: change vHW & strip reservations from VM
#$tmp = ($VM | Set-VM -NumCpu 4 -Confirm:$false)
#$tmp = ($VM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -MemReservationMB 0 -Confirm:$false)
#$tmp = ($VM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0 -Confirm:$false)
 
Write-Host "[$(Get-Date)] Starting vRealize Network Insight Platform"
Write-Progress -Activity "Starting vRealize Network Insight Platform"
$VM | Start-VM

Write-Host "[$(Get-Date)] vRealize Network Insight Platform VM has been deployed and started!" -ForegroundColor "green"
Write-Host "[$(Get-Date)] This script is now going to wait until the Platform VM has initialized, insert the license and generate a shared secret for the Proxy VM. All this is tested on 3.2 and uses UNSUPPORTED APIs, so any other version may break."

# Before bugging the Platform VM, give it 2 minutes for the initial boot
Sleep -s 120

# Login to UI first to get authenticated, the license activation and shared secret generating appear to require authentication
Write-Host "[$(Get-Date)] Logging into Network Insight.."
loginNetworkInsight $Platform_IP
Write-Host "[$(Get-Date)] Validating license.."
validateLicense $Platform_IP $License 
Write-Host "[$(Get-Date)] Activating license.."
activateLicense $Platform_IP $License
Write-Host "[$(Get-Date)] Generating Shared Secret.."
$Shared_Secret = generateSharedSecret $Platform_IP
 
Write-Host "[$(Get-Date)] Deploying Proxy VM.."
## Get the OVF configuration and fill the parameters
$OvfConfiguration = Get-OvfConfiguration -Ovf $Proxy_OVA

$OvfConfiguration.Common.Proxy_Shared_Secret.value = $Shared_Secret
$OvfConfiguration.Common.IP_Address.value = $Proxy_IP
$OvfConfiguration.Common.Netmask.value = $Netmask
$OvfConfiguration.Common.Default_Gateway.value = $Gateway
$OvfConfiguration.Common.DNS.value = $DNS
$OvfConfiguration.Common.Domain_Search.value = $Domain
$OvfConfiguration.Common.NTP.value = $NTP
$OvfConfiguration.Common.Web_Proxy_IP.value = $Web_Proxy_IP
$OvfConfiguration.Common.Web_Proxy_Port.value = $Web_Proxy_Port
$OvfConfiguration.Common.Rsyslog_IP.value = $Syslog

$OvfConfiguration.NetworkMapping.Vlan256_corp_2.value = (Get-VDPortgroup -Name $TargetPortGroup)

if($Log_Push.IsPresent) { $OvfConfiguration.Common.Log_Push.value = $True }
else { $OvfConfiguration.Common.Log_Push.value = $False }
if($Telemetry.IsPresent) { $OvfConfiguration.Common.Health_Telemetry_Push.value = $True }
else { $OvfConfiguration.Common.Health_Telemetry_Push.value = $False }

# Deploy the OVA.
Write-Host "[$(Get-Date)] Deploying vRealize Network Insight Proxy OVA"
Write-Progress -Activity "Deploying vRealize Network Insight Proxy OVA"
$VM = Import-vApp -Source $Proxy_OVA -OvfConfiguration $OvfConfiguration -Name $Proxy_VM_Name -VMHost $TargetVMHost -Datastore $TargetDatastore -DiskStorageFormat Thin

# Testlab edition: strip reservations from VM
#$tmp = ($VM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -MemReservationMB 0 -Confirm:$false)
#$tmp = ($VM | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0 -Confirm:$false)

Write-Host "[$(Get-Date)] Starting vRealize Network Insight Proxy"
Write-Progress -Activity "Starting vRealize Network Insight Proxy"
#$VM | Start-VM

Write-Host "[$(Get-Date)] vRealize Network Insight Proxy VM has been deployed and started!" -ForegroundColor "green"
Write-Host "[$(Get-Date)] The deployment should now be complete. Login to the Platform UI and add your data sources." -ForegroundColor "green"
 
 
 

  
