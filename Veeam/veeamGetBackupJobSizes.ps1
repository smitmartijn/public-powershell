# This script goes through all backup jobs configured on your Veeam
# Backup & Replication Management server and calculates the amount of
# data (the size of the data in the VMs) and the backup sizes (the size
# of the data on the backup disk).
#
# There is more information in the backup job object for you to use, but this
# script was intended for billing purposes based on GB of backup storage.
#
# Tested and working on Veeam B&R 8. Might not work with Veeam B&R 9.
#
# Martijn Smit <martijn@lostdomain.org>
#
# v1.0 - 11-12-2015: Initial release

if ((Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue) -eq $null) {
    Add-PsSnapin -Name VeeamPSSnapIn
}

$global:newBackupData = @();

function getBackupInfo()
{
	$VeeamVersion = ((Get-PSSnapin VeeamPSSnapin).Version.Major);
	$backupJobs = Get-VBRBackup

	foreach ($job in $backupJobs)
	{
		# get all restore points inside this backup job - use different function for Veeam B&R 9+
		if($VeeamVersion -ge 9) {
			$restorePoints = $job.GetAllStorages() | sort CreationTime -descending
		}
		else {
			$restorePoints = $job.GetStorages() | sort CreationTime -descending
		}

		$jobBackupSize = 0;
		$jobDataSize = 0;

		$jobName = ($job | Select -ExpandProperty JobName);

		Write-Host "Processing backup job: $jobName"

		# get list of VMs associated with this backup job
		$vmList = ($job | Select @{n="vm";e={$_.GetObjectOibsAll() | %{@($_.name,"")}}} | Select -ExpandProperty vm);
		$amountVMs = 0;
		$vms = ""
		foreach($vmName in $vmList)
		{
			if([string]::IsNullOrEmpty($vmName)) {
				continue
			}
			$vms += "$vmName,"
			$amountVMs = $amountVMs + 1
		}

		# cut last ,
		if(![string]::IsNullOrEmpty($vmName)) {
			$vms = $vms.Substring(0, $vms.Length - 1);
		}

		# go through restore points and add up the backup and data sizes
		foreach ($point in $restorePoints)
		{
			$jobBackupSize += [long]($point | Select-Object -ExpandProperty stats | Select -ExpandProperty BackupSize);
			$jobDataSize += [long]($point | Select-Object -ExpandProperty stats | Select -ExpandProperty DataSize);
		}

		# convert to GB
		$jobBackupSize = [math]::Round(($jobBackupSize / 1024 / 1024 / 1024), 2);
		$jobDataSize = [math]::Round(($jobDataSize / 1024 / 1024 / 1024), 2);

		# format record into an array and save it into the global data array
		$newEntry = New-Object -TypeName PSObject
        	$newEntry | Add-Member -Name 'Job' -Membertype NoteProperty -Value $jobName
		$newEntry | Add-Member -Name 'VMs' -MemberType Noteproperty -Value $vms
        	$newEntry | Add-Member -Name 'jobBackupSize' -MemberType Noteproperty -Value $jobBackupSize
        	$newEntry | Add-Member -Name 'jobDataSize' -MemberType Noteproperty -Value $jobDataSize
        	$newEntry | Add-Member -Name 'amountVMs' -MemberType Noteproperty -Value $amountVMs
		$global:newBackupData += $newEntry;

		# now do something with these stats! :-)
		Write-Host "Total VMs: " $amountVMs;
		Write-Host "Total Backup Size: " $jobBackupSize;
		Write-Host "Total Data Size: " $jobDataSize;
		Write-Host "List of VMs: " $vms;
		Write-Host "------------";
	}
}

getBackupInfo;
