# VMware Scripts
## Network-Insight-Bulk-Add-Datasources.ps1
Bulk adding of data sources within vRealize Network Insight. 

> Note: This script uses the very much UNSUPPORTED private API of Network Insight. VMware will in no way support this and it might break on a different version than 3.2 (currently tested). Use at your own risk.

Also, this script will hopefully be obsolete one day, when Network Insight natively starts to support bulk import. But for now, this will do the trick!

### CSV - network-insight-data-sources.csv (example)

The input CSV is pretty straightforward. There's an example in the repository which you can use to model your own against. The header has to look like this:

> DatasourceType,IP,Username,Password,Nickname,NSX_VC_URL,NSX_Controller_PW

I'll go over each column below, starting with the one that's most important and isn't straightforward.

#### DatasourceType
This is the type of data source you're adding to Network Insight. NI uses codes to determine which type of source it is. Here's a list of the available types. Copy/paste the ones you need.
- VCENTER: VMware vCenter
- NSX: VMware NSX Manager
- PAN: Palo Alto Networks Panorama 
- CISCOUCS: Cisco UCS Manager
- HPVIRTUALCONNECT: HP Virtual Connect Manager 
- CISCOCATALYST3750: Cisco Catalyst 3000
- CISCOCATALYST4500: Cisco Catalyst 4500
- CISCOCATALYST6500: Cisco Catalyst 6500
- CISCON1K: Cisco VSM (N1K)
- CISCON5K: Cisco Nexus 5K
- CISCON7K: Cisco Nexus 7K
- CISCON9K: Cisco Nexus 9K
- ARISTASWITCH: Arista Switch SSH
- BROCADESWITCH: Brocade Switch SSH
- JUNIPERSWITCH: Juniper Switch SSH
- DELLSWITCH: Dell Switch SSH
- FORCE10MXL10: Dell Force10MXL10
- FORCE10S6K: Dell Force10S6K

#### Rest of the columns
The rest of the columns are pretty straightforward, all relating to the data source itself (so IP of the switch/vcenter/panorama/etc/etc and credentials to login) except for the last 2. Those will only be used when adding a NSX Manager (*NSX*), where *NSX_VC_URL* is the hostname of the vCenter which is linked to this NSX Manager and *NSX_Controller_PW* is the password of the NSX Controllers present in the NSX environment.

### How to run

The script has a few parameters which are pretty straightforward. Here's an example of how to run it:

```powershell
PowerCLI > .\Network-Insight-Bulk-Add-Datasources.ps1 -NI_IP network-insight.lab -NI_Username 'admin@local' -NI_Password admin -DatasourcesCSV .\network-insight-data-sources.csv
[12/30/2016 16:32:50] Logged into Network Insight!
[12/30/2016 16:32:50] Added Data Source: VCENTER with IP vcenter.lab.lostdomain.local
[12/30/2016 16:32:50] Added Data Source: NSX with IP manager.nsx.lab.lostdomain.local
[12/30/2016 16:32:50] Added Data Source: CISCON1K with IP 10.8.25.15
```
