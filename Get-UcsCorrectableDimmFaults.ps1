funtion Get-UcsCorrectableDimmFaults
{
param(
        [string]$OutFile = "\\path\UCSDIMMCorrectableErrorReport\CorrectableErrorsReport_$(Get-Date -UFormat %d%b%Y_%H%M).xlsx",
        [pscredential]$Credential,
        [array]$DomainList
     )

Import-Module PSExcel
Import-Module ProtectedData

$ROCred      = Import-Clixml -Path "path\UCSRo.xml"    | Unprotect-Data
$Report      = @()

# Add multiple UCS/UCSCentral support
    $null = Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true

# Disconnect any active sessions
    $disconnect = Disconnect-Ucs
    $disconnect = Disconnect-UcsCentral

    # Initialize arrays
    $DomainList  = @()
    $UcsCentrals = @("x.x.x.x","x.x.x.x")

    # Build UCS domain list
    foreach ($UcsCentral in $UcsCentrals) 
    {
            $connect = Connect-UcsCentral $UcsCentral -Credential $ROCred
        
        #Add domains to the array
            $DomainList += Get-UcsCentralUcsDomain | Select Name,Ip | Sort Name
        

        #Disconnect from UCS Central
        $disconnect = Disconnect-UcsCentral
    }


    foreach ($ucsDomain in $DomainList)
{
        #Connect to UCS domain
        $connect = Connect-Ucs $ucsDomain.Ip -Credential $ROCred
    
        #Clear ReportTale
        $ReportTable = @{}

        write-host 'Pulling correctable DIMM error list from' $ucsDomain.Name

        #Get Correctable DIMM errors
        $MemErrors = Get-UcsMemoryArray -Hierarchy | where-object {$_.dn -match 'error-stats' -and $_.EccSinglebitErrors1Week -gt "0"} | select -Property UCS, dn, EccSinglebitErrors, EccSinglebitErrors15Min, EccSinglebitErrors1Hour, EccSinglebitErrors1Day, EccSinglebitErrors1Week

        #Build hashtable
        foreach($DN in $MemErrors)
            {
                # Get blade Dn
                $BladeDn = ($DN.Dn -split '/')[0..2] -join '/'

                # Add new blade Dn if it's not in the table
                if($ReportTable.Keys -notcontains $BladeDn)
                {
                    # Create new entry in table
                    $ReportTable.Add($BladeDn,@{OneMin=@();FifteenMin=@();OneHour=@();OneDay=@();OneWeek=@()})

                }
                $ReportTable[$BladeDn]["OneMin"] += ($DN.EccSinglebitErrors)
                $ReportTable[$BladeDn]["FifteenMin"] += ($DN.EccSinglebitErrors15Min)
                $ReportTable[$BladeDn]["OneHour"] += ($DN.EccSinglebitErrors1Hour)
                $ReportTable[$BladeDn]["OneDay"] += ($DN.EccSinglebitErrors1Day)
                $ReportTable[$BladeDn]["OneWeek"] += ($DN.EccSinglebitErrors1Week)

            }

        #build report
        foreach($Key in $($ReportTable.Keys))
            {
                
                # Get blade info 
                $Blade = Get-UcsBlade -Dn $Key
            
                # Get service profile name
                $ServiceProfile = (($Blade.AssignedToDn -split '/') | Select -Last 1) -replace "ls-",""

                # If no profile, add in a space so the export works ok
                if($ServiceProfile -eq "")
                {
                    $ServiceProfile = "$($Blade.Ucs) - chassis-$($Blade.ChassisId) slot-$($Blade.SlotId) - $($Blade.Serial)"
                }

                # Create object entry for this blade
                $BladeObject = [PSCustomObject]@{
                                                    ServiceProfile  = $ServiceProfile
                                                    Domain          = $Blade.Ucs
                                                    Chassis         = "chassis-" + $Blade.ChassisId
                                                    Slot            = "slot-"    + $Blade.SlotId
                                                    SerialNumber    = $Blade.Serial
                                                    OneMin          = $ReportTable[$Key]["OneMin"] -join ","
                                                    FifteenMin      = $ReportTable[$Key]["FifteenMin"]   -join ","
                                                    OneHour         = $ReportTable[$Key]["OneHour"] -join ","
                                                    OneDay          = $ReportTable[$Key]["OneDay"] -join ","
                                                    OneWeek         = $ReportTable[$Key]["OneWeek"] -join ","

                                                }

                # Add blade object to report array
                $Report += $BladeObject
               
            }

        # Disconnect from domain
        $disconnect = Disconnect-Ucs
    }

    # Sort Report by Service Profile Name
    $Report = $Report | sort -Property ServiceProfile
    
    $Report | Export-XLSX $OutFile -Table -AutoFit
    Write-Host "Report has been exported to $OutFile"
}