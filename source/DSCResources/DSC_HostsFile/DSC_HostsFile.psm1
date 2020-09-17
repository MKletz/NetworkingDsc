$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the Networking Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'NetworkingDsc.Common' `
            -ChildPath 'NetworkingDsc.Common.psm1'))

Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'DscResource.Common')

# Import Localization Strings
$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

<#
    .SYNOPSIS
        Returns the current state of a hosts file entry.

    .PARAMETER HostName
        Specifies the name of the computer that will be mapped to an IP address.

    .PARAMETER IPAddress
        Specifies the IP Address that should be mapped to the host name.

    .PARAMETER Ensure
        Specifies if the hosts file entry should be created or deleted.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName,

        [Parameter()]
        [System.String]
        $IPAddress,

        [Parameter()]
        [System.String]
        $Comment,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
    )

    Write-Verbose -Message ($script:localizedData.StartingGet -f $HostName)

    $result = Get-HostEntry -HostName $HostName

    if ($null -ne $result)
    {
        return @{
            HostName  = $result.HostName
            IPAddress = $result.IPAddress
            Comment   = $result.Comment
            Ensure    = 'Present'
        }
    }
    else
    {
        return @{
            HostName  = $HostName
            IPAddress = $null
            Comment   = $null
            Ensure    = 'Absent'
        }
    }
}

<#
    .SYNOPSIS
        Adds, updates or removes a hosts file entry.

    .PARAMETER HostName
        Specifies the name of the computer that will be mapped to an IP address.

    .PARAMETER IPAddress
        Specifies the IP Address that should be mapped to the host name.

    .PARAMETER Ensure
        Specifies if the hosts file entry should be created or deleted.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName,

        [Parameter()]
        [System.String]
        $IPAddress,

        [Parameter()]
        [System.String]
        $Comment,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
    )

    $hostPath = "$env:windir\System32\drivers\etc\hosts"
    $currentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message ($script:localizedData.StartingSet -f $HostName)

    if ($Ensure -eq 'Present' -and $PSBoundParameters.ContainsKey('IPAddress') -eq $false)
    {
        New-InvalidArgumentException `
            -Message $($($script:localizedData.UnableToEnsureWithoutIP) -f $Address, $AddressFamily) `
            -ArgumentName 'IPAddress'
    }

    if ($currentValues.Ensure -eq 'Absent' -and $Ensure -eq 'Present')
    {
        Write-Verbose -Message ($script:localizedData.CreateNewEntry -f $HostName)
        Add-Content -Path $hostPath -Value "`r`n$IPAddress`t$HostName`t$Comment"
    }
    else
    {
        $hosts = Get-Content -Path $hostPath
        $replace = $hosts | Where-Object -FilterScript {
            [System.String]::IsNullOrEmpty($_) -eq $false -and $_.StartsWith('#') -eq $false -and $_ -like "*$HostName*"
        }

        $multiLineEntry = $false
        $data = $replace -split '\s+'

        if ($data.Length -gt 2)
        {
            $multiLineEntry = $true
        }

        if ($Ensure -eq 'Present')
        {
            Write-Verbose -Message ($script:localizedData.UpdateExistingEntry -f $HostName)

            if ($multiLineEntry -eq $true)
            {
                $newReplaceLine = $replace -replace $HostName, ''
                $hosts = $hosts -replace $replace, $newReplaceLine
                $hosts += "$IPAddress`t$HostName"
            }
            else
            {
                $hosts = $hosts -replace $replace, "$IPAddress`t$HostName"
            }
        }
        else
        {
            Write-Verbose -Message ($script:localizedData.RemoveEntry -f $HostName)

            if ($multiLineEntry -eq $true)
            {
                $newReplaceLine = $replace -replace $HostName, ''
                $hosts = $hosts -replace $replace, $newReplaceLine
            }
            else
            {
                $hosts = $hosts -replace $replace, ''
            }
        }

        Set-Content -Path $hostPath -Value $hosts
    }
}

<#
    .SYNOPSIS
        Tests the current state of a hosts file entry.

    .PARAMETER HostName
        Specifies the name of the computer that will be mapped to an IP address.

    .PARAMETER IPAddress
        Specifies the IP Address that should be mapped to the host name.

    .PARAMETER Ensure
        Specifies if the hosts file entry should be created or deleted.
#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName,

        [Parameter()]
        [System.String]
        $IPAddress,

        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
    )

    $currentValues = Get-TargetResource @PSBoundParameters

    Write-Verbose -Message ($script:localizedData.StartingTest -f $HostName)

    if ($Ensure -ne $currentValues.Ensure)
    {
        return $false
    }

    if ($Ensure -eq 'Present' -and $IPAddress -ne $currentValues.IPAddress)
    {
        return $false
    }

    return $true
}

function Get-HostEntry
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName
    )

    [System.String]$hostPath = "$($env:windir)\System32\drivers\etc\hosts"

    [System.Collections.ArrayList]$allHosts = @()
    $allHosts += Get-Content -Path $hostPath | Where-Object -FilterScript {
        [System.String]::IsNullOrEmpty($_) -eq $false -and $_.StartsWith('#') -eq $false
    }

    foreach ($hosts in $allHosts)
    {
        $data = $hosts.Trim() -split '\s+'

        [System.String[]]$hostArray = @()
        [System.String]$ipAddress = $data[0]
        [System.String]$comment = [System.String]::Empty

        for ($i = 1; $i -lt $data.Length; $i++)
        {
            if ($data[$i] -eq '#')
            {
                [int]$commentStart = $i + 1
                [int]$commentEnd = $data.Length - 1
                $comment = '# ' + $data[$commentStart..$commentEnd] -join ' '
                break
            }

            $hostArray += $data[$i]
        }

        if ($HostName -in $hostArray)
        {
            $return = [PSCustomObject]@{
                HostName  = $hostArray
                IPAddress = $ipAddress
                Comment   = $comment
            }

            $return | Add-Member -MemberType 'ScriptMethod' -Name 'EntryText' -Value {"$($this.IPAddress)`t$($this.HostName -join ' ')`t$($this.Comment)"}
            return $return
        }
    }
}

function Remove-HostEntry
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName
    )

    if($entry = Get-HostEntry -HostName $HostName)
    {
        [System.String]$hostPath = "$($env:windir)\System32\drivers\etc\hosts"
        [System.String]$Line = (Select-String -Path $hostPath -Pattern $HostName).Line
        $entry.HostName = $entry.HostName | Where-Object -FilterScript {$_ -ne $HostName}

        if($entry.HostName.Length -eq 0)
        {
            (Get-Content -Path $hostPath) | Where-Object -FilterScript {$_ -notmatch $Line} | Set-Content -Path $hostPath
        }
        else
        {
            (Get-Content -Path $hostPath) -replace $Line,$entry.EntryText() | Set-Content -Path $hostPath
        }
    }
}

function Add-HostEntry
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $HostName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $IPAddress,

        [Parameter()]
        [System.String]
        $Comment
    )

    [System.String]$hostPath = "$($env:windir)\System32\drivers\etc\hosts"
    $Comment = $Comment.Trim()

    if($Comment -and !$Comment.StartsWith('#'))
    {
        $Comment = "# $($comment)"
    }

    [System.String]$Content = "$($IPAddress)`t$($HostName -join ' ')`t$($Comment)".Trim()
    Add-Content -Path $hostPath -Value "`r`n$($Content)"
}
