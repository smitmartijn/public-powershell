#
# vSphere-Set-MTU.ps1
#
# This script can set the MTU on all vSwitches and VMKernel PortGroups
# with a certain name inside a specific DRS Cluster. Easy use for changing
# the MTU size across a multitude of ESXi hosts.
#
# Usage: .\vSphere-Set-MTU.ps1
#   -vCenterServer <vCenter Server>
#   -Cluster       <Cluster Name>   - DRS Cluster which you want to change
#   -MTU           [MTU Size]       - Optional MTU size, defaults to 9000
#   -vSwitches     [$True|$False]   - Change MTU for all vSwitches (standard & DVS, defaults to $True)
#   -NFS           [$True|$False]   - Change MTU for all vmknics with 'NFS' in the name
#   -iSCSI         [$True|$False]   - Change MTU for all vmknics with 'iSCSI' in the name
#   -vMotion       [$True|$False]   - Change MTU for all vmknics with 'vMotion' in the name
#   -VSAN          [$True|$False]   - Change MTU for all vmknics with 'VSAN' in the name
#
# Example:
#
# PowerCLI Z:\PowerShell> .\vSphere-Set-MTU.ps1 -vCenterServer vcenter.lab.local -MTU 9000 -vMotion $True -Cluster MyCluster
# This will set the MTU size to 9000 of all vSwitches and VMKernel PortGroups where the names contain:
#
# - vMotion
#
# Please be sure your network and/or storage equipment already supports a MTU of 9000
#
# Press enter to start!
# Working...
# Finding and configuring all Standard vSwitches..
# - Configured Standard vSwitch 'vSwitch0' to MTU 9000
# - Configured Standard vSwitch 'vSwitch1' to MTU 9000
# Finding and configuring all Distributed vSwitches..
# - Configured Distributed vSwitch 'dvSwitch' to MTU 9000
# Finding and configuring VMKernel PortGroups..
# - Configured interface 'vMotion' on 'esxi01.lab.local' to MTU 9000
# - Configured interface 'vMotion' on 'esxi02.lab.local' to MTU 9000
# - Configured interface 'test-vMotion' on 'esxi02.lab.local' to MTU 9000
# All done!
#
# PowerCLI Z:\PowerShell>
#
# ChangeLog:
#
# 12-02-2016 - Martijn Smit <martijn@lostdomain.org>
# - Initial script
#

Param(
	[String]$vCenterServer = "",
	[String]$Cluster = "",
	[Boolean]$NFS = $False,
	[Boolean]$iSCSI = $False,
	[Boolean]$vMotion = $False,
	[Boolean]$VSAN = $False,
  [Boolean]$vSwitches = $True,
  [Int]$MTU = 9000
)

Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue;

# We need to point the PSModulePath variable to the PowerCLI modules directory,
# for some reason the PowerCLI installer doesn't do this for us:
$p = [Environment]::GetEnvironmentVariable("PSModulePath");
$p += ";C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Modules\";
[Environment]::SetEnvironmentVariable("PSModulePath",$p);
# Now import distributed vSwitch module!
Import-Module VMware.VimAutomation.Vds

$scriptName = $MyInvocation.MyCommand.Name;

function Usage
{
	Write-Host ""
	Write-Host "Usage: .\$scriptName "
	Write-Host "   -vCenterServer <vCenter Server>"
	Write-Host "   -Cluster       <Cluster Name>   - DRS Cluster which you want to change"
	Write-Host "   -MTU        [MTU Size]     - Optional MTU size, defaults to 9000"
  Write-Host "   -vSwitches  [$True|$False] - Change MTU for all vSwitches (defaults to $True)"
	Write-Host "   -NFS        [$True|$False] - Change MTU for all vmknics with 'NFS' in the name"
	Write-Host "   -iSCSI      [$True|$False] - Change MTU for all vmknics with 'iSCSI' in the name"
	Write-Host "   -vMotion    [$True|$False] - Change MTU for all vmknics with 'vMotion' in the name"
	Write-Host "   -VSAN       [$True|$False] - Change MTU for all vmknics with 'VSAN' in the name"
	Write-Host ""
	return;
}
function setVMKernelPortGroupsMTU
{
	Write-Host "Finding and configuring VMKernel PortGroups.."
	# Get a list of all VMKernel ports on the ESXi hosts attached to the requested cluster
	$vmkInterfaces = Get-VMHostNetworkAdapter -VMKernel -VMHost (Get-Cluster $Cluster | Get-VMHost);

	# Go through all found vmkernel interfaces
	foreach($interface in $vmkInterfaces)
	{
		# Next is some logic to determine whether to change the MTU of the current interface
		$skip = $True
		if($NFS -eq $True -and $interface.PortGroupName -like "*nfs*") { $skip = $False }
		if($iSCSI -eq $True -and $interface.PortGroupName -like "*iscsi*") { $skip = $False }
		if($VSAN -eq $True -and $interface.PortGroupName -like "*vsan*") { $skip = $False }
		if($vMotion -eq $True -and $interface.PortGroupName -like "*vmotion*") { $skip = $False }
		if($skip -eq $True) { continue }

		# Configure the interface to the requested MTU
		if(Set-VMHostNetworkAdapter -VirtualNic $interface -Mtu $MTU -Confirm:$False) {
			Write-Host "- Configured interface '$($interface.PortGroupName)' on '$($interface.VMHost)' to MTU $MTU" -foregroundcolor "green"
		}
		else {
			Write-Host "- Failed to configure interface '$($interface.PortGroupName)' on '$($interface.VMHost)' to MTU $MTU" -foregroundcolor "red"
		}
	}
}
function setStandardvSwitchesMTU
{
	Write-Host "Finding and configuring all Standard vSwitches.."
	# Get a list of all vSwitches on the ESXi hosts that are in the requested DRS cluster
	$vswitches = Get-VirtualSwitch -Standard -VMHost (Get-Cluster $Cluster | Get-VMHost);

	# Go through all found vSwitches
	foreach($vswitch in $vswitches)
	{
		if(Set-VirtualSwitch $vswitch -Mtu $MTU -Confirm:$False) {
			Write-Host "- Configured Standard vSwitch '$($vswitch.Name)' to MTU $MTU" -foregroundcolor "green"
		}
		else {
			Write-Host "- Failed to configure vSwitch '$($vswitch.Name)' to MTU $MTU" -foregroundcolor "red"
		}
	}
}
function setDistributedvSwitchesMTU
{
	Write-Host "Finding and configuring all Distributed vSwitches.."
	# Get a list of all Distributed vSwitches on the ESXi hosts that are in the requested DRS cluster
	$vswitches = Get-VDSwitch -VMHost (Get-Cluster $Cluster | Get-VMHost);

	# Go through all found vSwitches
	foreach($vswitch in $vswitches)
	{
		if(Set-VDSwitch $vswitch -Mtu $MTU -Confirm:$False) {
			Write-Host "- Configured Distributed vSwitch '$($vswitch.Name)' to MTU $MTU" -foregroundcolor "green"
		}
		else {
			Write-Host "- Failed to configure Distributed vSwitch '$($vswitch.Name)' to MTU $MTU" -foregroundcolor "red"
		}
	}
}

if($vCenterServer -eq "" -or $Cluster -eq "")
{
	Write-Host "Please supply a vCenter Server and a Cluster Name!" -foregroundcolor "red"
	Usage;
	return;
}

if(($NFS -eq $FALSE) -and ($iSCSI -eq $FALSE) -and ($vMotion -eq $FALSE) -and ($VSAN -eq $FALSE))
{
	Write-Host "Please supply one of these params: NFS, iSCSI, vMotion or VSAN" -foregroundcolor "red"
	Usage;
	return;
}

if(($MTU -lt 1500) -or ($MTU -gt 9000))
{
	Write-Host "Using a MTU size of less than 1500 or greater than 9000 is usually not advised." -foregroundcolor "yellow"
	Usage;
	return;
}

# Connect to vCenter
if (!(Connect-VIServer -Server $vCenterServer)) {
	Write-Host "Connection to vCenter failed!" -foregroundcolor "red"
	return;
}

# Confirmation?
Write-Host "This will set the MTU size to $MTU of all vSwitches and VMKernel PortGroups where the names contain:"
Write-Host ""
if($NFS -eq $True)     { Write-Host " - NFS" }
if($iSCSI -eq $True)   { Write-Host " - iSCSI" }
if($VSAN -eq $True)    { Write-Host " - VSAN" }
if($vMotion -eq $True) { Write-Host " - vMotion" }
Write-Host ""
Write-Host "Please be sure your network and/or storage equipment already supports a MTU of $MTU" -foregroundcolor "yellow"
Write-Host ""
Write-Host "Press enter to start!"
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); # Pause
Write-Host "Working..."

if($vSwitches -eq $True) {
  setStandardvSwitchesMTU;
  setDistributedvSwitchesMTU;
}

setVMKernelPortGroupsMTU;

Write-Host "All done!"
Write-Host ""
