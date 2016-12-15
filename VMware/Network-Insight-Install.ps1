
param (
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Platform_OVA,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_OVA,

  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$VM_Name,
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
  [string]$IP,
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
  [parameter(Mandatory=$true, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$NTP,

  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Shared_Secret,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_IP,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Proxy_Port,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$Syslog,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Telemetry,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Log_Push,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Deploy_Platform,
  [parameter(Mandatory=$false, ValueFromPipeLine=$true, ValueFromPipeLineByPropertyName=$true)]
  [ValidateNotNullOrEmpty()]
  [switch]$Deploy_Proxy
)

if(!($Deploy_Platform.IsPresent) -and !($Deploy_Proxy.IsPresent))
{
  Write-Host "Please use either -Deploy_Platform or -Deploy_Proxy to start deploying vRealize Network Insight." -ForegroundColor "red"
  Exit
}

if($Deploy_Platform.IsPresent)
{

  if (!(Test-Path $Platform_OVA)) {
    Write-Host "Network Insight Plaform OVA not found! ($Platform_OVA)" -ForegroundColor "red"
    Exit
  }

  ## Using the PowerCLI, get the OVF configuration and fill the parameters
  $OvfConfiguration = Get-OvfConfiguration -Ovf $Platform_OVA

  $OvfConfiguration.Common.IP_Address.value = $IP
  $OvfConfiguration.Common.Netmask.value = $Netmask
  $OvfConfiguration.Common.Default_Gateway.value = $Gateway
  $OvfConfiguration.Common.DNS.value = $DNS
  $OvfConfiguration.Common.Domain_Search.value = $Domain
  $OvfConfiguration.Common.NTP.value = $NTP
  $OvfConfiguration.Common.Web_Proxy_IP.value = $Proxy_IP
  $OvfConfiguration.Common.Web_Proxy_Port.value = $Proxy_Port
  $OvfConfiguration.Common.Rsyslog_IP.value = $Syslog

  $OvfConfiguration.NetworkMapping.Vlan256_corp_2.value = (Get-VirtualPortGroup -Name $TargetPortGroup)

  if($Log_Push.IsPresent) {
    $OvfConfiguration.Common.Log_Push.value = $True
  }
  else {
    $OvfConfiguration.Common.Log_Push.value = $False
  }
  if($Telemetry.IsPresent) {
    $OvfConfiguration.Common.Health_Telemetry_Push.value = $True
  }
  else {
    $OvfConfiguration.Common.Health_Telemetry_Push.value = $False
  }

  # Deploy the OVA.
  Write-Progress -Activity "Deploying vRealize Network Insight Platform OVA"
  $VM = Import-vApp -Source $Platform_OVA -OvfConfiguration $OvfConfiguration -Name $VM_Name -VMHost $TargetVMHost -Datastore $TargetDatastore -DiskStorageFormat Thin

  Write-Progress -Activity "Starting vRealize Network Insight Platform"
  $VM | Start-VM

  Write-Host "vRealize Network Insight Platform VM has been deployed and started!" -ForegroundColor "green"
  Write-Host "Wait for https://$IP to initialize, enter the license and generate the proxy shared secret, copy that and deploy the proxy using -Deploy_Proxy"
}

if($Deploy_Proxy.IsPresent)
{
  if (!(Test-Path $Proxy_OVA)) {
    Write-Host "Network Insight Proxt OVA not found! ($Proxy_OVA)" -ForegroundColor "red"
    Exit
  }
  
  if([string]::IsNullOrEmpty($Shared_Secret)) {
    Write-Host "The Proxy Shared Secret is mandatory - please copy and paste (into -Shared_Secret) that from the Platform UI" -ForegroundColor "red"
    Exit
  }
  
  ## Using the PowerCLI, get the OVF configuration and fill the parameters
  $OvfConfiguration = Get-OvfConfiguration -Ovf $Proxy_OVA

  $OvfConfiguration.Common.Proxy_Shared_Secret.value = $Shared_Secret
  $OvfConfiguration.Common.IP_Address.value = $IP
  $OvfConfiguration.Common.Netmask.value = $Netmask
  $OvfConfiguration.Common.Default_Gateway.value = $Gateway
  $OvfConfiguration.Common.DNS.value = $DNS
  $OvfConfiguration.Common.Domain_Search.value = $Domain
  $OvfConfiguration.Common.NTP.value = $NTP
  $OvfConfiguration.Common.Web_Proxy_IP.value = $Proxy_IP
  $OvfConfiguration.Common.Web_Proxy_Port.value = $Proxy_Port
  $OvfConfiguration.Common.Rsyslog_IP.value = $Syslog

  $OvfConfiguration.NetworkMapping.Vlan256_corp_2.value = (Get-VirtualPortGroup -Name $TargetPortGroup)

  if($Log_Push.IsPresent) {
    $OvfConfiguration.Common.Log_Push.value = $True
  }
  else {
    $OvfConfiguration.Common.Log_Push.value = $False
  }
  if($Telemetry.IsPresent) {
    $OvfConfiguration.Common.Health_Telemetry_Push.value = $True
  }
  else {
    $OvfConfiguration.Common.Health_Telemetry_Push.value = $False
  }

  # Deploy the OVA.
  Write-Progress -Activity "Deploying vRealize Network Insight Proxy OVA"
  $VM = Import-vApp -Source $Proxy_OVA -OvfConfiguration $OvfConfiguration -Name $VM_Name -VMHost $TargetVMHost -Datastore $TargetDatastore -DiskStorageFormat Thin

  Write-Progress -Activity "Starting vRealize Network Insight Proxy"
  $VM | Start-VM

  Write-Host "vRealize Network Insight Proxy VM has been deployed and started!" -ForegroundColor "green"
  Write-Host "Go look in the Platform UI for it to appear." -ForegroundColor "green"
  
}
  
