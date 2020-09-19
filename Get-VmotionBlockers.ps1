function Get-VmotionBlockers {

    <#
        .SYNOPSIS
        Lists any attached ISOs or VMtools installations that are in progress that will prevent an ESXi host from entering Maintenance Mode

        .DESCRIPTION
        This function will find any attached ISOs or VMtools installations that are in progress for the specified cluster that will prevent an ESXi host from entering Maintenance Mode

        .PARAMETER vcenter
        FQDN or IP address of vCenter

        .PARAMETER cluster
        Name of compute clsuter to check for vMotion blockers

        .EXAMPLE
        PS C:\> Get-VmotionBlockers -vcenter vcenter01.example.com -cluster Cluster01
    #>

    param(
        [Parameter(Mandatory=$true)]
        [string]$vcenter,
        [Parameter(Mandatory=$true)]
        [string]$cluster
    )

    begin{

        #Initialize report array
        $report = @()

        #Close any open vCenter connections
        if($Global:DefaultVIServer){
            try{
                $disconnect = Disconnect-VIServer * -Confirm:$false -ErrorAction Stop
            }
            catch{
                return "Unable to close open vCenter connections. Please use the command 'Disconnect-VIServer' to manually close any open connections. Script terminated."
            }
        }

        #Connect to the specified vCenter
        $vcenter_creds = Get-Credential -Message "Enter vCenter login credentials"
        Write-Host "Connecting to vCenter" -ForegroundColor Green -NoNewline

        try{
            $connection = Connect-VIServer -Server $vcenter -Credential $vcenter_creds -ErrorAction Stop
            Write-Host "...Done" -ForegroundColor Green
        }
        catch{
            return "`nUnable to connect to vCenter. Please verify your firewall connectivity and vCenter name and try again. Script terminated."
        }
    }

    process{

        #Get the managed object of the specified cluster
        Write-Host "Getting cluster object for cluster: $cluster" -ForegroundColor Green -NoNewline
        try{
            $cluster_object = Get-Cluster -Name $cluster -ErrorAction Stop
            Write-Host "...Done" -ForegroundColor Green
        }
        catch{
            return "`nUnable to get the cluster object for $cluster. Please double check the cluster name and try again. Script terminated."
        }

        #Get the list of VMs in the specified cluster
        Write-Host "Getting VMs in cluster: $($cluster_object.Name)" -ForegroundColor Green -NoNewline
        try{
            $vm_list =  $cluster_object | Get-VM -ErrorAction Stop
            Write-Host "...Done" -ForegroundColor Green
        }
        catch{
            return "`nUnable to get the VM list for $($cluster_object.Name). Script terminated."
        }

        #Check each VM for mounted ISOs and VMtools installs that are in progress
        $count = 0
        foreach($vm in $vm_list){
            $count++
            Write-Progress -Activity "Processing VMs" -Status "Processing $($vm.Name)" -PercentComplete (($count / $vm_list.Count) * 100)

            #Check for attached ISOs
            $attached_iso = Get-CDDrive $vm | select Parent, IsoPath

            #Add VM name and ISO path to report if present
            if($attached_iso.IsoPath){
                $report += "$($attached_iso.Parent) - $($attached_iso.IsoPath)"
            }

            #Check for VMtools install in progress
            $tools_status = ($vm | Get-View).Runtime.ToolsInstallerMounted

            #Add Vm name and install status to report if VMtools mounted
            if($tools_status){
                $report += "$($vm.Name) - VMtools install in progress"
            }
        }
    }

    end{
        #Return report
        if($report){
            return $report
        }
        else{
            return "No vMotion blockers found. Go have a beer :)"
        }
    }
}
