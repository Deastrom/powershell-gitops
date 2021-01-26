Function Deploy-GitOpsBuild {
    <#
    .SYNOPSIS
    Compares each file in the build directory with its representation in the
    destination directory and copies the build directory file over if the
    destination file does not match.
    
    .DESCRIPTION
    The 'Deploy-GitOpsBuild' function check each file in the build directory
    against it's file in the destination directory.  It checks for the file hash
    of the Destination file.  If the file is there and the hash matches the Build
    hash, the file is not copied.  Otherwise, the file is copied.

    .PARAMETER Build
    The Directory that will be parsed and copied from.

    .PARAMETER Destination
    The Directory that will be parsed and copied to.

    .PARAMETER Source
    Not Used in this function. Added for splatting purposes.

    .PARAMETER ToSession
    Session where the Destination can be found. Can be null to represent local.

    .INPUTS
    System.IO.DirectoryInfo can be piped into Build.

    .OUTPUTs
    None
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [String]
        $Build,
        [ValidateScript( {
                Test-Path $_ -IsValid -PathType Container
            })]
        [String]
        $Destination,
        [System.Management.Automation.Runspaces.PSSession]
        $ToSession,
        [String]
        $Source
    )
    Process {
        $CopyParams = @{}
        $InvCmdParams = @{}
        If ($PSBoundParameters['ToSession']) {
            Write-Verbose "Using $($ToSession | Select-Object -Property * | ConvertTo-Json)"
            $CopyParams.ToSession = $ToSession
            $InvCmdParams.Session = $ToSession
        }
        $BuildDirectory = Get-Item -Path $Build
        If (-not $(Invoke-Command -ScriptBlock { Test-Path $using:Destination } @InvCmdParams)) {
            Write-Verbose "Creating $Destination directory"
            Invoke-Command -ScriptBlock { New-Item $using:Destination -ItemType Directory } @InvCmdParams | Out-Null
        }
        $DestinationDirectory = Invoke-Command -ScriptBlock { Get-Item $using:Destination } @InvCmdParams
        ForEach ($BuildFile in $(Get-ChildItem $BuildDirectory -Recurse -File)) {
            $DestinationFile = @{
                FullName = Join-Path -Path $DestinationDirectory.FullName -ChildPath $BuildFile.FullName.Replace($BuildDirectory.FullName,"")
                Directory = Join-Path -Path $DestinationDirectory.FullName -ChildPath $BuildFile.Directory.Fullname.Replace($BuildDirectory.FullName, "")
            }
            $BuildFileHash = Get-FileHash $BuildFile
            $DestinationFileHash = Invoke-Command -ScriptBlock { Get-FileHash $using:DestinationFile.FullName -ErrorAction SilentlyContinue } @InvCmdParams
            If ($DestinationFileHash -and ($BuildFileHash.Hash -eq $DestinationFileHash.Hash)) {
                Write-Verbose "$($DestinationFileHash.Path) hash matches $($BuildFileHash.Path) hash, not copying."
            } Else {
                Write-Verbose "Copying $($BuildFile.FullName) to $($DestinationFile.FullName)"
                if (-Not $(Invoke-Command -ScriptBlock { Test-Path $using:DestinationFile.Directory } @InvCmdParams)) {
                    Write-Verbose "Creating $($DestinationFile.Directory) directory"
                    Invoke-Command -ScriptBlock { New-Item $using:DestinationFile.Directory -ItemType Directory } @InvCmdParams | Out-Null
                }
                Copy-Item $BuildFile -Destination $DestinationFile.FullName @CopyParams
            }
        }
    }
}